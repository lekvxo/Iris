(() => {
    const states = new WeakMap();
    function preference(video) {
        const tracks = [...video.textTracks].filter(t => ['subtitles', 'captions'].includes(t.kind));
        const showing = tracks.find(t => t.mode === 'showing');
        const activeHidden = tracks.filter(t => t.mode === 'hidden' && t.activeCues?.length);
        const track = showing || (activeHidden.length === 1 ? activeHidden[0] : null);
        return {track, enabled: !!track, language: track?.language || ''};
    }
    // Shared by the explicit AVPlayer handoff; never extracts media or invents captions.
    window.irisNativeCaptionPreference = video => {
        const {enabled, language} = preference(video);
        return {enabled, language};
    };
    function report(fullscreen) {
        window.webkit?.messageHandlers.irisFullscreen?.postMessage({fullscreen});
    }
    function prepare(video) {
        if (states.has(video)) return;
        const {track} = preference(video);
        const state = {track, mode: track?.mode, cues: []};
        states.set(video, state);
        if (track) {
            // Custom website players often keep their active track hidden and render it in the DOM.
            // Native fullscreen needs a showing track, with cues inside the video rather than at its clipped edge.
            for (const cue of [...(track.cues || [])].slice(0, 20000)) {
                if (!(cue instanceof VTTCue)) continue;
                state.cues.push({cue, line: cue.line, snapToLines: cue.snapToLines, position: cue.position,
                    positionAlign: cue.positionAlign, size: cue.size, align: cue.align});
                cue.snapToLines = true;
                cue.line = -3;
                cue.position = 50;
                cue.positionAlign = 'center';
                cue.size = 90;
                cue.align = 'center';
            }
            track.mode = 'showing';
        }
    }
    function restore(video) {
        const state = states.get(video);
        if (!state) return;
        for (const {cue, ...original} of state.cues) Object.assign(cue, original);
        // Respect captions turned off in Apple's UI instead of turning them back on.
        if (state.track && state.track.mode !== 'disabled') state.track.mode = state.mode;
        states.delete(video);
        report(false);
    }
    window.irisPrepareNativeCaptions = prepare;
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
        if (e.target instanceof HTMLVideoElement) { prepare(e.target); report(true); }
    }, true);
    document.addEventListener('webkitendfullscreen', e => { if (e.target instanceof HTMLVideoElement) restore(e.target); }, true);
    document.addEventListener('fullscreenchange', () => {
        if (document.fullscreenElement) report(true);
        else {
            for (const video of document.querySelectorAll('video')) restore(video);
            report(false);
        }
    });
    document.addEventListener('fullscreenerror', e => {
        if (e.target instanceof HTMLVideoElement) restore(e.target);
    }, true);
})();
