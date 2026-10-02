(() => {
    function record(event) {
        if (!event.isTrusted) return;
        const anchor = event.composedPath().find(node => node instanceof HTMLAnchorElement);
        window.webkit.messageHandlers.irisGesture.postMessage({
            href: anchor ? anchor.href : null
        });
    }
    document.addEventListener('pointerdown', record, true);
    document.addEventListener('click', record, true);
})();
