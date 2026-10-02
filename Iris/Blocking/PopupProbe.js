(() => {
    const original = window.open;
    window.open = function(target, ...args) {
        try {
            const url = new URL(target, location.href);
            if (url.protocol === 'http:' || url.protocol === 'https:') {
                // Reporting only: this bridge never authorizes a navigation.
                window.webkit.messageHandlers.irisPopup.postMessage({url: url.href});
            }
        } catch (_) {}
        return original.call(this, target, ...args);
    };
})();
