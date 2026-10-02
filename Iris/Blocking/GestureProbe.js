(() => {
    let pointer = null;
    function record(event) {
        if (!event.isTrusted) return;
        const anchor = event.composedPath().find(node => node instanceof HTMLAnchorElement);
        const href = anchor ? anchor.href : null;
        if (event.type === 'pointerdown') pointer = {anchor, href, time: performance.now()};
        // Keep the destination from pointerdown if a click handler mutates href.
        const original = event.type === 'click' && pointer &&
            pointer.anchor === anchor && performance.now() - pointer.time < 2000;
        window.webkit.messageHandlers.irisGesture.postMessage({
            href: original ? pointer.href : href
        });
        if (event.type === 'click') pointer = null;
    }
    window.addEventListener('pointerdown', record, true);
    window.addEventListener('click', record, true);
})();
