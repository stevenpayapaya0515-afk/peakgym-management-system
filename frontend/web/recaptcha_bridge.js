// Only the public Google site key is passed to the browser. Never the secret.
(function () {
  'use strict';
  const widgetIds = new WeakMap();
  const mounted = new WeakSet();

  window.peakgymRecaptchaMount = function (host, siteKey, onSuccess, onExpired, onError) {
    if (!host || mounted.has(host)) return;
    mounted.add(host);
    let tries = 0;
    const init = function () {
      if (!host.isConnected || !window.grecaptcha ||
          typeof window.grecaptcha.render !== 'function') {
        if (++tries < 150) {
          window.setTimeout(init, 100);
        } else {
          onError();
        }
        return;
      }
      try {
        const widgetId = window.grecaptcha.render(host, {
          sitekey: siteKey,
          theme: 'dark',
          size: 'normal',
          callback: onSuccess,
          'expired-callback': onExpired,
          'error-callback': onError
        });
        widgetIds.set(host, widgetId);
      } catch (err) {
        onError();
      }
    };
    init();
  };

  window.peakgymRecaptchaReset = function (host) {
    const widgetId = widgetIds.get(host);
    if (widgetId !== undefined && window.grecaptcha &&
        typeof window.grecaptcha.reset === 'function') {
      window.grecaptcha.reset(widgetId);
    }
  };
})();
