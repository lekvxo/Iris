(() => {
    const states = new WeakMap();
    const sessions = new Set();
    const selections = new WeakMap();
    const bridges = new WeakMap();
    const nativeTracks = new WeakMap();
    const pending = new WeakMap();
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
            if (selections.has(player)) {
                const track = selections.get(player);
                return {track, enabled: !!track, language: track?.language || '', known: true};
            }
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
    // The React DOM does not expose player.textTracks. These public Vidstack
    // events provide the selected track itself, including its already-loaded cues.
    document.addEventListener('text-track-change', event => {
        const player = event.target;
        if (!(player instanceof Element) || !player.matches('media-player[data-media-player]')) return;
        const track = event.detail;
        if (track !== null && (!track || !['subtitles', 'captions'].includes(track.kind) ||
            typeof track.addEventListener !== 'function' || !Array.isArray(track.cues))) return;
        selections.set(player, track);
        for (const video of player.querySelectorAll('video')) {
            if (sessions.has(video)) transfer(video);
            diagnose(video, 4);
        }
    }, true);
    function clearBridge(video) {
        const state = bridges.get(video);
        if (!state) return;
        for (const name of ['load', 'add-cue', 'remove-cue']) state.source.removeEventListener(name, state.update);
        state.native.mode = 'hidden';
        for (const cue of [...(state.native.cues || [])]) state.native.removeCue(cue);
        state.native.mode = 'disabled';
        bridges.delete(video);
    }
    function transfer(video) {
        const source = selections.get(customPlayer(video));
        const previous = bridges.get(video);
        if (previous?.source === source) return;
        clearBridge(video);
        if (!source || source.mode !== 'showing') return;
        // Leave sources with working native captions under their existing renderer.
        if ([...video.textTracks].some(t => ['subtitles', 'captions'].includes(t.kind) && t.mode === 'showing')) return;
        let cache = nativeTracks.get(video);
        if (!cache) { cache = new Map(); nativeTracks.set(video, cache); }
        const key = JSON.stringify([source.kind, source.label, source.language]);
        let native = cache.get(key);
        if (!native) {
            native = video.addTextTrack('subtitles', `${source.label || 'Website subtitles'} (Iris)`, source.language || '');
            cache.set(key, native);
        }
        native.mode = 'hidden';
        const state = {source, native, copies: new Map()};
        state.update = () => {
            const cues = new Set(source.cues.slice(0, 20000));
            for (const [cue, copy] of state.copies) if (!cues.has(cue)) {
                native.removeCue(copy); state.copies.delete(cue);
            }
            for (const cue of cues) {
                if (state.copies.has(cue) || !Number.isFinite(cue.startTime) || !Number.isFinite(cue.endTime) ||
                    cue.endTime <= cue.startTime || typeof cue.text !== 'string') continue;
                // Keep text/timing; use native cue layout, not the website overlay's CSS.
                const copy = new VTTCue(cue.startTime, cue.endTime, cue.text);
                native.addCue(copy); state.copies.set(cue, copy);
            }
            if (!state.started && state.copies.size) { native.mode = 'showing'; state.started = true; }
            diagnose(video, 4);
        };
        bridges.set(video, state);
        for (const name of ['load', 'add-cue', 'remove-cue']) source.addEventListener(name, state.update);
        state.update();
    }
    window.irisPrepareNativeCaptions = video => {
        sessions.add(video);
        transfer(video);
        clearTimeout(pending.get(video));
        pending.set(video, setTimeout(() => {
            pending.delete(video);
            if (!states.has(video) && !nativeActive(video)) end(video);
        }, 5000));
    };
    window.irisRestoreNativeCaptions = video => end(video);
    // This embed's wrapper-fullscreen path black-screens on the headset, while
    // direct video fullscreen works. Handle only its public, user-initiated
    // Vidstack request; leave browser prototypes and other sites untouched.
    document.addEventListener('media-enter-fullscreen-request', event => {
        if (location.hostname !== 'strm.cx' || !navigator.userActivation?.isActive || event.defaultPrevented) return;
        const target = event.target;
        const player = target instanceof Element ? target.closest('media-player[data-media-player]') : null;
        const videos = player?.querySelectorAll('video');
        if (videos?.length !== 1) return;
        const video = videos[0];
        if (video.readyState < 1 || nativeActive(video) || document.fullscreenElement ||
            typeof video.webkitEnterFullscreen !== 'function') return;
        try {
            window.irisPrepareNativeCaptions(video);
            video.webkitEnterFullscreen();
            event.preventDefault();
            event.stopImmediatePropagation();
        } catch {
            end(video); // Let the website handle the original request if WebKit rejects it.
        }
    }, true);
    // Observe native presentation without overriding or redirecting fullscreen APIs.
    function diagnose(video, event) {
        const tracks = [...video.textTracks];
        window.webkit?.messageHandlers.irisFullscreen?.postMessage({captionEvent: event,
            ready: video.readyState, tracks: tracks.length,
            showing: tracks.filter(t => t.mode === 'showing').length,
            hidden: tracks.filter(t => t.mode === 'hidden').length,
            cues: tracks.reduce((n, t) => n + (t.cues?.length || 0), 0),
            active: tracks.reduce((n, t) => n + (t.activeCues?.length || 0), 0),
            custom: customPlayer(video)?.hasAttribute('data-captions') ? 1 : 0,
            selected: selections.get(customPlayer(video))?.cues?.length ?? -1});
    }
    function begin(video) {
        clearTimeout(pending.get(video));
        pending.delete(video);
        sessions.add(video);
        transfer(video);
        diagnose(video, 1);
        report(true);
        if (states.has(video)) return;
        // Bound observation to the transition; do not keep polling during a movie.
        let remaining = 10;
        const timer = setInterval(() => {
            diagnose(video, 2);
            if (--remaining === 0) clearInterval(timer);
        }, 1000);
        states.set(video, timer);
        sessions.add(video);
    }
    function end(video) {
        clearTimeout(pending.get(video));
        pending.delete(video);
        clearBridge(video);
        clearInterval(states.get(video));
        states.delete(video);
        sessions.delete(video);
        diagnose(video, 3);
        report(false);
    }
    document.addEventListener('webkitbeginfullscreen', e => {
        if (e.target instanceof HTMLVideoElement) begin(e.target);
    }, true);
    document.addEventListener('webkitendfullscreen', e => {
        if (e.target instanceof HTMLVideoElement && !nativeActive(e.target)) end(e.target);
    }, true);
    document.addEventListener('webkitpresentationmodechanged', e => {
        if (!(e.target instanceof HTMLVideoElement)) return;
        if (nativeActive(e.target)) begin(e.target); else end(e.target);
    }, true);
    document.addEventListener('fullscreenchange', () => {
        const element = document.fullscreenElement;
        if (element) {
            const videos = element instanceof HTMLVideoElement ? [element] : [...element.querySelectorAll('video')];
            if (videos.length === 1) begin(videos[0]); else report(true);
        } else {
            for (const video of [...sessions]) if (!nativeActive(video)) end(video);
            if (![...sessions].some(nativeActive)) report(false);
        }
    });
    window.addEventListener('pagehide', () => {
        for (const video of [...sessions]) {
            clearTimeout(pending.get(video)); pending.delete(video);
            clearInterval(states.get(video)); states.delete(video); clearBridge(video);
        }
        sessions.clear();
    });
    document.addEventListener('fullscreenerror', () => { for (const video of [...sessions]) end(video); }, true);
    document.addEventListener('playing', e => {
        if (e.target instanceof HTMLVideoElement) diagnose(e.target, 0);
    }, true);
})();
