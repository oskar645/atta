{{flutter_js}}
{{flutter_build_config}}

const attaWebTitle = "Атта Маркет";
document.title = attaWebTitle;

Promise.resolve(_flutter.loader.load({
  config: {
    renderer: "canvaskit",
  },
})).then(() => {
  document.title = attaWebTitle;
});
