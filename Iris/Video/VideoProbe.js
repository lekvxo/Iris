(() => {
    let counter = 0;
    let manifest = null;
    let manifestAt = 0;
    let active = null;
    const session = Math.random().toString(36).slice(2);
    const encrypted = new WeakSet();
    function id(video) {
        if (!video.dataset.irisVideo) video.dataset.irisVideo = session + '-' + (++counter);
        return video.dataset.irisVideo;
    }
    // Busy pages mutate and fire timeupdate constantly; batch reports so native sees a few per second at most.
    const pending = new Set();
    const sent = new WeakMap();
    let timer = 0;
    let scanPending = false;
    function arm() { if (!timer) timer = setTimeout(flush, 250); }
    function flush() {
        if (scanPending) { scanPending = false; scan(); }
        const videos = [...pending];
        pending.clear();
        timer = 0;
        for (const video of videos) send(video);
    }
    function report(video) {
        if (!video) return;
        pending.add(video);
        arm();
    }
    function send(video) {
        if (!video.isConnected) return;
        const message = {
            id: id(video), src: video.currentSrc || video.src || '',
            time: Number.isFinite(video.currentTime) ? video.currentTime : 0,
            duration: Number.isFinite(video.duration) ? video.duration : null,
            drm: encrypted.has(video) || !!video.mediaKeys,
            manifest: Date.now() - manifestAt < 30000 ? manifest : null,
            nativeFullscreen: typeof video.webkitEnterFullscreen === 'function' || typeof video.requestFullscreen === 'function',
            playing: !video.paused && !video.ended
        };
        const key = JSON.stringify([message.src, message.duration, message.drm, message.manifest, message.nativeFullscreen, message.playing]);
        const previous = sent.get(video);
        const now = Date.now();
        // Playback time alone changes constantly; refresh it every few seconds.
        if (previous && previous.key === key && now - previous.at < 5000) return;
        sent.set(video, {key, at: now});
        window.webkit.messageHandlers.irisVideo.postMessage(message);
    }
    function note(raw) {
        try {
            const url = new URL(raw, location.href);
            if (/\.m3u8$/i.test(url.pathname)) {
                manifest = url.href; manifestAt = Date.now();
                if (active) report(active);
            }
            // Direct MP4 fetches are observed but never selected over a video's currentSrc.
            if (/\.mp4$/i.test(url.pathname) && active) report(active);
        } catch (_) {}
    }
    const originalFetch = window.fetch;
    window.fetch = function(input, ...args) {
        note(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
        return originalFetch.call(this, input, ...args);
    };
    const originalOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, ...args) {
        note(url);
        return originalOpen.call(this, method, url, ...args);
    };
    document.addEventListener('play', event => {
        if (event.target instanceof HTMLVideoElement) { active = event.target; report(active); }
    }, true);
    document.addEventListener('encrypted', event => {
        if (event.target instanceof HTMLVideoElement) { encrypted.add(event.target); report(event.target); }
    }, true);
    for (const event of ['loadedmetadata', 'durationchange', 'timeupdate', 'pause', 'ended']) {
        document.addEventListener(event, e => {
            if (e.target instanceof HTMLVideoElement && (!active || active === e.target)) report(e.target);
        }, true);
    }
    function scan() {
        if (active && active.isConnected) { report(active); return; }
        active = document.querySelector('video:not([hidden])');
        report(active);
    }
    new MutationObserver(() => { scanPending = true; arm(); }).observe(document.documentElement, {childList: true, subtree: true});
    scan();
})();
