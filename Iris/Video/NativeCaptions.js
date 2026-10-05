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
    // Observe the unmodified WebKit path. No prototype overrides, track writes,
    // extra subtitle resources, controls changes, or fullscreen redirection.
    function diagnose(video, event) {
        const tracks = [...video.textTracks];
        window.webkit?.messageHandlers.irisFullscreen?.postMessage({captionEvent: event,
            ready: video.readyState, tracks: tracks.length,
            showing: tracks.filter(t => t.mode === 'showing').length,
            hidden: tracks.filter(t => t.mode === 'hidden').length,
            cues: tracks.reduce((n, t) => n + (t.cues?.length || 0), 0),
            active: tracks.reduce((n, t) => n + (t.activeCues?.length || 0), 0),
            custom: customPlayer(video)?.hasAttribute('data-captions') ? 1 : 0});
    }
    function begin(video) {
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
        for (const video of [...sessions]) { clearInterval(states.get(video)); states.delete(video); }
        sessions.clear();
    });
    document.addEventListener('playing', e => {
        if (e.target instanceof HTMLVideoElement) diagnose(e.target, 0);
    }, true);
})();
