{{flutter_js}}
{{flutter_build_config}}

const attaWebTitle = "Атта Маркет";
const attaShouldPreserveServerTitle = /^\/listing\/[^/]+\/?$/.test(window.location.pathname);
if (!attaShouldPreserveServerTitle) {
  document.title = attaWebTitle;
}

Promise.resolve(_flutter.loader.load({
  config: {
    renderer: "canvaskit",
  },
})).then(() => {
  if (!attaShouldPreserveServerTitle) {
    document.title = attaWebTitle;
  }
}).catch((error) => {
  console.error("ATTA Flutter bootstrap failed", error);
  if (typeof window.attaShowBootstrapError === "function") {
    window.attaShowBootstrapError();
  }
});
