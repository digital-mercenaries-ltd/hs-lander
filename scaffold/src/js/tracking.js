// scaffold/src/js/tracking.js — GA4 measurement.
// __GA4_ID__ is substituted at build time per project.config.sh's GA4_MEASUREMENT_ID.
// HubSpot's standard_header_includes / standard_footer_includes provides
// HubSpot's own analytics (page-view, form submissions); this file adds GA4
// alongside, not instead.
(function () {
  if (!"__GA4_ID__" || "__GA4_ID__" === "") return;

  var script = document.createElement("script");
  script.async = true;
  script.src = "https://www.googletagmanager.com/gtag/js?id=__GA4_ID__";
  document.head.appendChild(script);

  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = gtag;
  gtag("js", new Date());
  gtag("config", "__GA4_ID__");
})();
