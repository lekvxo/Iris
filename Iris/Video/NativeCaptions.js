(() => {
    const states = new WeakMap();
    const sessions = new Set();
    const selections = new WeakMap();
    const bridges = new WeakMap();
    const nativeTracks = new WeakMap();
    const pending = new WeakMap();
    const renderers = new WeakMap();
    function prepareRenderer(video) {
        if (location.hostname !== 'strm.cx' || renderers.has(video)) return;
        const element = customPlayer(video);
        if (!element) return;
        let player;
        // The public remote-control discovery event also works with React players,
        // whose DOM element does not expose the controller's properties.
        element.dispatchEvent(new CustomEvent('find-media-player', {
            bubbles: true, composed: true, detail: value => { player = value; }
        }));
        const source = selections.has(element) ? selections.get(element) : player?.textTracks?.selected;
        if (typeof player?.state?.controls !== 'boolean' || !player.textTracks ||
            (!source && !player.textTracks.length) || (source &&
                (typeof source.setMode !== 'function' || !source.id || source.mode !== 'showing' ||
                    !Array.isArray(source.cues) || !['subtitles', 'captions'].includes(source.kind)))) return;
        const state = {player, controls: player.state.controls, source, starting: true, copies: [], native: null};
        renderers.set(video, state);
        // Ask the website's own renderer to manage its native tracks. An unrelated
        // addTextTrack track can be disabled by the player's selection machinery.
        player.controls = true;
    }
    function clearRendererCopies(state) {
        for (const name of ['load', 'add-cue', 'remove-cue']) state.selected?.removeEventListener(name, state.update);
        for (const name of ['load', 'error']) state.element?.removeEventListener(name, state.update);
        if (state.native && state.copies.length) {
            const mode = state.native.mode;
            if (mode === 'disabled') state.native.mode = 'hidden';
            const present = new Set(state.native.cues || []);
            for (const cue of state.copies) if (present.has(cue)) state.native.removeCue(cue);
            state.native.mode = mode;
        }
        state.copies = [];
        state.selected = null;
        state.element = null;
    }
    function updateRenderer(video, source) {
        const state = renderers.get(video);
        if (!state || state.starting) return;
        if (state.selected === source) return;
        clearRendererCopies(state);
        state.native = null;
        if (!source || source.mode !== 'showing') return;
        const elements = [...video.querySelectorAll('track')].filter(t => t.id === source.id &&
            ['subtitles', 'captions'].includes(t.kind));
        if (elements.length !== 1) return;
        const native = elements[0].track;
        state.native = native;
        state.selected = source;
        state.element = elements[0];
        // Use the existing renderer-owned track. Preserve any loaded native cues;
        // only supply already-loaded website cues when the native resource is empty.
        native.mode = 'hidden';
        if (!native.cues?.length) {
            const copies = new Map();
            state.update = () => {
                if (source.mode !== 'showing' || native.mode === 'disabled') return;
                const present = new Set(native.cues || []);
                // WebKit clears programmatic cues while the HTML track's own
                // resource finishes loading (or fails). Reconcile after that event.
                for (const [cue, copy] of copies) if (!present.has(copy)) copies.delete(cue);
                const copied = new Set(copies.values());
                if (state.element.readyState === 2 && [...present].some(cue => !copied.has(cue))) {
                    for (const copy of copies.values()) native.removeCue(copy);
                    copies.clear(); state.copies = []; return;
                }
                const cues = new Set(source.cues.slice(0, 20000));
                for (const [cue, copy] of copies) if (!cues.has(cue)) { native.removeCue(copy); copies.delete(cue); }
                for (const cue of cues) {
                    if (copies.has(cue) || !Number.isFinite(cue.startTime) || !Number.isFinite(cue.endTime) ||
                        cue.endTime <= cue.startTime || typeof cue.text !== 'string') continue;
                    const copy = new VTTCue(cue.startTime, cue.endTime, cue.text);
                    native.addCue(copy); copies.set(cue, copy);
                }
                state.copies = [...copies.values()];
            };
            for (const name of ['load', 'add-cue', 'remove-cue']) source.addEventListener(name, state.update);
            for (const name of ['load', 'error']) state.element.addEventListener(name, state.update);
            state.update();
        }
        native.mode = 'showing';
        diagnose(video, 4);
    }
    function restoreRenderer(video) {
        const state = renderers.get(video);
        if (!state) return;
        clearTimeout(state.activation);
        renderers.delete(video);
        clearRendererCopies(state);
        state.player.controls = state.controls;
        // A rejected or cancelled entry must also preserve the inline selection
        // that the native-renderer transition may temporarily have deselected.
        if (state.starting) state.source?.setMode('showing');
    }
    function nativeActive(video) {
        return video.webkitDisplayingFullscreen || ['fullscreen', 'picture-in-picture'].includes(video.webkitPresentationMode);
    }
    function customPlayer(video) {
        const player = video.closest('media-player');
        return player?.hasAttribute('data-media-player') ? player : null;
    }
    function eventPlayer(event) {
        // Maverick replaces event.target with a controller, not an Element.
        // The native propagation path retains the actual dispatching DOM node.
        const element = event.composedPath().find(node => node instanceof Element);
        return element?.closest('media-player[data-media-player]') || null;
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
        const player = eventPlayer(event);
        if (!player) return;
        const track = event.detail;
        if (track !== null && (!track || !['subtitles', 'captions'].includes(track.kind) ||
            typeof track.addEventListener !== 'function' || !Array.isArray(track.cues))) return;
        selections.set(player, track);
        for (const video of player.querySelectorAll('video')) {
            if (renderers.has(video)) updateRenderer(video, track);
            else if (sessions.has(video)) transfer(video);
            diagnose(video, 4);
        }
    }, true);
    function clearBridge(video) {
        const state = bridges.get(video);
        if (!state) return;
        clearTimeout(state.activation);
        for (const name of ['load', 'add-cue', 'remove-cue']) state.source.removeEventListener(name, state.update);
        state.native.mode = 'hidden';
        for (const cue of [...(state.native.cues || [])]) state.native.removeCue(cue);
        state.native.mode = 'disabled';
        bridges.delete(video);
    }
    function transfer(video) {
        if (renderers.has(video)) return;
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
        prepareRenderer(video);
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
        const player = eventPlayer(event);
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
            renderer: renderers.has(video) ? 1 : 0,
            nativeControls: renderers.get(video)?.player.state.controls ? 1 : 0,
            selected: selections.get(customPlayer(video))?.cues?.length ?? -1});
    }
    function begin(video) {
        clearTimeout(pending.get(video));
        pending.delete(video);
        sessions.add(video);
        prepareRenderer(video);
        transfer(video);
        const renderer = renderers.get(video);
        if (renderer?.starting && !renderer.activation) {
            renderer.activation = setTimeout(() => {
                if (renderers.get(video) !== renderer || !sessions.has(video)) return;
                renderer.starting = false;
                // Controls changes can transiently deselect the custom track. Restore
                // the explicit pre-entry selection once, through the player's API.
                renderer.source?.setMode('showing');
                updateRenderer(video, renderer.player.textTracks.selected || renderer.source);
            }, 0);
        }
        const bridge = bridges.get(video);
        if (bridge && !bridge.entered) {
            bridge.entered = true;
            // Native fullscreen resets the initial track selection. Apply the
            // website's explicit selection once after transition handlers finish.
            // Later Native Off choices must remain under the user's control.
            bridge.activation = setTimeout(() => {
                if (bridges.get(video) !== bridge || !sessions.has(video) ||
                    bridge.source.mode !== 'showing' || !bridge.copies.size) return;
                bridge.native.mode = 'showing';
                diagnose(video, 4);
            }, 0);
        }
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
        sessions.delete(video);
        restoreRenderer(video);
        clearBridge(video);
        clearInterval(states.get(video));
        states.delete(video);
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
            sessions.delete(video);
            clearTimeout(pending.get(video)); pending.delete(video);
            clearInterval(states.get(video)); states.delete(video); clearBridge(video);
            restoreRenderer(video);
        }
        sessions.clear();
    });
    document.addEventListener('fullscreenerror', () => { for (const video of [...sessions]) end(video); }, true);
    document.addEventListener('playing', e => {
        if (e.target instanceof HTMLVideoElement) diagnose(e.target, 0);
    }, true);
})();
