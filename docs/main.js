(function () {
  var root = document.documentElement;
  var toggle = document.getElementById("lang-toggle");
  var titles = {
    zh: "Xeditor — 原生 macOS 文本编辑器",
    en: "Xeditor — A native macOS text editor"
  };

  function apply(lang) {
    root.dataset.lang = lang;
    root.lang = lang === "zh" ? "zh-Hans" : "en";
    document.title = titles[lang];
    if (toggle) {
      toggle.textContent = lang === "zh" ? "EN" : "中文";
      toggle.setAttribute("aria-label", lang === "zh" ? "Switch to English" : "切换到中文");
    }
  }

  var current = root.dataset.lang === "en" ? "en" : "zh";
  apply(current);

  if (toggle) {
    toggle.addEventListener("click", function () {
      var next = root.dataset.lang === "zh" ? "en" : "zh";
      apply(next);
      try { localStorage.setItem("xeditor.lang", next); } catch (e) {}
    });
  }
})();
