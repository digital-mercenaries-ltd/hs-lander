// Google Analytics for __DOMAIN__
(function() {
  var script = document.createElement('script');
  script.src = 'https://www.googletagmanager.com/gtag/js?id=__GA4_ID__';
  script.async = true;
  document.head.appendChild(script);

  window.dataLayer = window.dataLayer || [];
  function gtag() { dataLayer.push(arguments); }
  gtag('js', new Date());
  gtag('config', '__GA4_ID__');
})();
