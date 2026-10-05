(() => {
    const states = new WeakMap();
    const sessions = new Set();
    function customPlayer(video) {
        const player = video.closest('media-player');
        const tracks = player?.textTracks;
        return player && typeof player.controls === 'boolean' && tracks !== video.textTracks &&
            typeof tracks?.[Symbol.iterator] === 'function' &&
            typeof tracks.addEventListener === 'function' && typeof tracks.removeEventListener === 'function'
            ? player : null;
    }
    function preference(video) {
        const player = customPlayer(video);
        if (player) {
            const tracks = [...player.textTracks].filter(t => ['subtitles', 'captions'].includes(t.kind));
            const showing = tracks.filter(t => t.mode === 'showing');
            const track = showing.length === 1 ? showing[0] : null;
            return {track, enabled: !!track, language: track?.language || '',
                known: !!track || tracks.every(t => t.mode === 'disabled')};
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
    function reconcile(video, state) {
        // Vidstack's public native renderer owns native track modes and selection.
        if (state.player) return;
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
                controls: player?.controls};
            states.set(video, state);
            sessions.add(video);
            if (player && !player.controls) player.controls = true;
            // A synchronous API failure, rejected promise, or fullscreenerror restores
            // immediately. This bounded timeout also covers a request with no begin event.
            state.pending = setTimeout(() => restore(video), 5000);
        }
        reconcile(video, state);
    }
    function begin(video) {
        prepare(video);
        const state = states.get(video);
        clearTimeout(state.pending);
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
        if (state.player && state.controls === false && state.player.controls === true) {
            state.player.controls = false;
        }
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
    document.addEventListener('webkitbeginfullscreen', e => {
        if (e.target instanceof HTMLVideoElement) begin(e.target);
    }, true);
    document.addEventListener('webkitendfullscreen', e => { if (e.target instanceof HTMLVideoElement) restore(e.target); }, true);
    document.addEventListener('fullscreenchange', () => {
        const element = document.fullscreenElement;
        if (element) {
            const videos = element instanceof HTMLVideoElement ? [element] : [...element.querySelectorAll('video')];
            // A wrapper with multiple videos is ambiguous; do not select one arbitrarily.
            if (videos.length === 1) begin(videos[0]);
            else report(true);
        } else { restoreAll(); report(false); }
    });
    document.addEventListener('fullscreenerror', restoreAll, true);
    window.addEventListener('pagehide', restoreAll);
})();
