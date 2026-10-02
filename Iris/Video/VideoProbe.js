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
    function report(video) {
        if (!video || !video.isConnected) return;
        window.webkit.messageHandlers.irisVideo.postMessage({
            id: id(video), src: video.currentSrc || video.src || '',
            time: Number.isFinite(video.currentTime) ? video.currentTime : 0,
            duration: Number.isFinite(video.duration) ? video.duration : null,
            drm: encrypted.has(video) || !!video.mediaKeys,
            manifest: Date.now() - manifestAt < 30000 ? manifest : null,
            nativeFullscreen: typeof video.webkitEnterFullscreen === 'function' || typeof video.requestFullscreen === 'function'
        });
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
    for (const event of ['loadedmetadata', 'durationchange', 'timeupdate']) {
        document.addEventListener(event, e => {
            if (e.target instanceof HTMLVideoElement && (!active || active === e.target)) report(e.target);
        }, true);
    }
    function scan() {
        if (active && active.isConnected) { report(active); return; }
        active = document.querySelector('video:not([hidden])');
        report(active);
    }
    new MutationObserver(scan).observe(document.documentElement, {childList: true, subtree: true});
    scan();
})();
