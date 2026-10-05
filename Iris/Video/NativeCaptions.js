(() => {
    const states = new WeakMap();
    const sessions = new Set();
    function nativeActive(video) {
        return video.webkitDisplayingFullscreen || ['fullscreen', 'picture-in-picture'].includes(video.webkitPresentationMode);
    }
    function customPlayer(video) {
        const player = video.closest('media-player');
        return player?.hasAttribute('data-media-player') ? player : null;
    }
    function preference(video) {
        const player = customPlayer(video);
        if (player) {
            // React Vidstack renders a plain <media-player>; it need not expose
            // the web component's textTracks/controls properties. Use its public
            // DOM state and only an unambiguous, existing subtitle resource.
            const enabled = player.hasAttribute('data-captions');
            const elements = [...video.querySelectorAll('track')].filter(t =>
                !t.hasAttribute('data-iris-caption') && ['subtitles', 'captions'].includes(t.kind) && t.src);
            const element = enabled && elements.length === 1 ? elements[0] : null;
            return {element, enabled, language: element?.srclang || '', known: !enabled || !!element};
        }
        const tracks = [...video.textTracks].filter(t => ['subtitles', 'captions'].includes(t.kind));
        const showing = tracks.filter(t => t.mode === 'showing');
        const hidden = tracks.filter(t => t.mode === 'hidden');
        const active = hidden.filter(t => t.activeCues?.length);
        // A single hidden track remains selected between cues. Multiple hidden tracks
        // without one active track do not tell us which language the site selected.
        const track = showing.length === 1 ? showing[0] : showing.length === 0
            ? (active.length === 1 ? active[0] : hidden.length === 1 ? hidden[0] : null) : null;
        return {track, enabled: !!track, language: track?.language || '',
            known: !!track || (showing.length === 0 && hidden.length === 0)};
    }
    window.irisNativeCaptionPreference = video => {
        const {enabled, language, known} = preference(video);
        return {enabled, language, known};
    };
    function report(fullscreen) {
        window.webkit?.messageHandlers.irisFullscreen?.postMessage({fullscreen});
    }
    function diagnose(video, event) {
        const bridge = states.get(video)?.bridge;
        // Counts only: no browsing URLs, subtitle text, or media credentials.
        window.webkit?.messageHandlers.irisFullscreen?.postMessage({captionEvent: event,
            ready: video.readyState, tracks: video.textTracks.length,
            showing: [...video.textTracks].filter(t => t.mode === 'showing').length,
            cues: bridge?.track.cues?.length || 0, bridgeReady: bridge?.readyState ?? -1});
    }
    function reconcileBridge(video, state) {
        if (state.nativeRenderer) return;
        const {element} = preference(video);
        if (state.bridge && (state.source !== element || state.sourceURL !== element?.src)) {
            state.bridge.track.mode = 'disabled';
            state.bridge.remove();
            state.bridge = null;
        }
        if (!element || state.bridge || state.nativeOff) return;
        const bridge = document.createElement('track');
        bridge.setAttribute('data-iris-caption', '');
        bridge.kind = element.kind;
        bridge.label = `${element.label || element.srclang || 'Captions'} (Iris)`;
        bridge.srclang = element.srclang;
        bridge.src = element.src;
        state.source = element;
        state.sourceURL = element.src;
        state.bridge = bridge;
        state.bridgeLoaded = false;
        bridge.addEventListener('load', () => {
            if (states.get(video) !== state || state.bridge !== bridge) return;
            // WebKit's initial automatic track selection can disable a newly
            // inserted track. Select once after loading, then respect native Off.
            bridge.track.mode = 'showing';
            state.bridgeLoaded = true;
            diagnose(video, 2);
        }, {once: true});
        bridge.addEventListener('error', () => diagnose(video, 3), {once: true});
        video.append(bridge);
        bridge.track.mode = 'showing';
    }
    function reconcile(video, state) {
        if (state.player) { reconcileBridge(video, state); return; }
        // Stop owning a track as soon as the site or Apple's controls change it.
        // Never repeatedly force a hidden/disabled track back on.
        if (state.track && state.track.mode !== 'showing') {
            state.released.add(state.track);
            state.track = null;
        }
        const {track} = preference(video);
        if (!track || track.mode !== 'hidden' || state.released.has(track)) return;
        if (state.track && state.track !== track && state.track.mode === 'showing') return;
        state.track = track;
        track.mode = 'showing';
    }
    function prepare(video) {
        let state = states.get(video);
        if (!state) {
            const player = customPlayer(video);
            state = {track: null, released: new WeakSet(), cleanup: [], player,
                nativeRenderer: [...video.textTracks].some(t =>
                    ['subtitles', 'captions'].includes(t.kind) && t.mode === 'showing')};
            states.set(video, state);
            sessions.add(video);
            if (player) {
                const observer = new MutationObserver(() => reconcileBridge(video, state));
                observer.observe(player, {subtree: true, childList: true, attributes: true,
                    attributeFilter: ['data-captions', 'src', 'kind', 'srclang']});
                const selectionChanged = () => {
                    if (state.bridgeLoaded && state.bridge && state.bridge.track.mode !== 'showing') state.nativeOff = true;
                };
                video.textTracks.addEventListener('change', selectionChanged);
                state.cleanup.push(() => observer.disconnect(),
                    () => video.textTracks.removeEventListener('change', selectionChanged));
            }
            // A synchronous API failure, rejected promise, or fullscreenerror restores
            // immediately. This bounded timeout also covers a request with no begin event.
            state.pending = setTimeout(() => nativeActive(video) ? begin(video) : restore(video), 5000);
        }
        reconcile(video, state);
        diagnose(video, 0);
    }
    function begin(video) {
        prepare(video);
        const state = states.get(video);
        clearTimeout(state.pending);
        diagnose(video, 1);
        if (state.player) { report(true); return; }
        if (!state.observing) {
            state.observing = true;
            const update = () => {
                for (const track of video.textTracks) {
                    if (state.observed.has(track)) continue;
                    state.observed.add(track);
                    track.addEventListener('cuechange', update);
                    state.cleanup.push(() => track.removeEventListener('cuechange', update));
                }
                reconcile(video, state);
            };
            state.observed = new WeakSet();
            for (const [target, name] of [[video.textTracks, 'addtrack'], [video.textTracks, 'removetrack'],
                [video.textTracks, 'change'], [video, 'loadedmetadata'], [video, 'load']]) {
                target.addEventListener(name, update, true);
                state.cleanup.push(() => target.removeEventListener(name, update, true));
            }
            // <track> load does not bubble; capture also observes late track elements.
            update();
        }
        report(true);
    }
    function restore(video) {
        const state = states.get(video);
        if (!state) return;
        clearTimeout(state.pending);
        for (const cleanup of state.cleanup) cleanup();
        diagnose(video, 4);
        if (state.bridge) { state.bridge.track.mode = 'disabled'; state.bridge.remove(); }
        if (state.track?.mode === 'showing') state.track.mode = 'hidden';
        states.delete(video);
        sessions.delete(video);
        report(false);
    }
    function restoreAll() { for (const video of [...sessions]) restore(video); }
    window.irisPrepareNativeCaptions = prepare;
    window.irisRestoreNativeCaptions = restore;
    for (const name of ['webkitEnterFullscreen', 'requestFullscreen']) {
        const original = HTMLVideoElement.prototype[name];
        if (typeof original !== 'function') continue;
        HTMLVideoElement.prototype[name] = function(...args) {
            prepare(this);
            try {
                const result = original.apply(this, args);
                if (result?.catch) return result.catch(error => { restore(this); throw error; });
                return result;
            } catch (error) { restore(this); throw error; }
        };
    }
    // Vidstack normally requests fullscreen on its wrapper (custom UI). In Iris,
    // use the same video presentation path as the toolbar, retaining the live
    // video/provider and the initiating user gesture. Other wrappers are untouched.
    for (const name of ['requestFullscreen', 'webkitRequestFullscreen']) {
        const original = Element.prototype[name];
        if (typeof original !== 'function') continue;
        Element.prototype[name] = function(...args) {
            const videos = this.matches('media-player[data-media-player]') ? this.querySelectorAll('video') : [];
            if (videos.length === 1 && typeof videos[0].webkitEnterFullscreen === 'function') {
                try { videos[0].webkitEnterFullscreen(); return Promise.resolve(); }
                catch (error) { return Promise.reject(error); }
            }
            return original.apply(this, args);
        };
    }
    const setPresentation = HTMLVideoElement.prototype.webkitSetPresentationMode;
    if (typeof setPresentation === 'function') {
        HTMLVideoElement.prototype.webkitSetPresentationMode = function(mode) {
            if (mode !== 'inline') prepare(this);
            try { return setPresentation.call(this, mode); }
            catch (error) { restore(this); throw error; }
        };
    }
    document.addEventListener('webkitpresentationmodechanged', e => {
        if (!(e.target instanceof HTMLVideoElement)) return;
        if (e.target.webkitPresentationMode === 'inline') restore(e.target);
        else begin(e.target);
    }, true);
    document.addEventListener('webkitbeginfullscreen', e => {
        if (e.target instanceof HTMLVideoElement) begin(e.target);
    }, true);
    document.addEventListener('webkitendfullscreen', e => {
        if (e.target instanceof HTMLVideoElement && !nativeActive(e.target)) restore(e.target);
    }, true);
    document.addEventListener('fullscreenchange', () => {
        const element = document.fullscreenElement;
        if (element) {
            const videos = element instanceof HTMLVideoElement ? [element] : [...element.querySelectorAll('video')];
            // A wrapper with multiple videos is ambiguous; do not select one arbitrarily.
            if (videos.length === 1) begin(videos[0]);
            else report(true);
        } else {
            for (const video of [...sessions]) if (!nativeActive(video)) restore(video);
            if (!sessions.size) report(false);
        }
    });
    document.addEventListener('fullscreenerror', restoreAll, true);
    window.addEventListener('pagehide', restoreAll);
})();
