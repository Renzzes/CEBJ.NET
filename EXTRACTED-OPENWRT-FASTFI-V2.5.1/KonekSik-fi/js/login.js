(function () {
  const AUTH_KEY = "ksk_auth";
  const form = document.getElementById("login-form");
  const user = document.getElementById("username");
  const pass = document.getElementById("password");
  const btn = document.getElementById("login-btn");
  const err = document.getElementById("login-error");
  const wrap = document.getElementById("login-wrap");
  const overlay = document.getElementById("success-overlay");
  const flash = document.getElementById("fail-flash");
  const toggle = document.getElementById("pw-toggle");

  function showApp() {
    document.body.classList.remove("is-login");
    document.body.classList.add("is-app");
    overlay.classList.remove("show");
    document.title = "KonekSik-fi Admin Console";
    if (window.KskApp) window.KskApp.init();
  }

  function showLogin() {
    document.body.classList.add("is-login");
    document.body.classList.remove("is-app");
    document.title = "KonekSik-fi — Sign in";
    overlay.classList.remove("show");
    btn.disabled = false;
    btn.innerHTML = "Sign in";
    if (window.KskBrand) window.KskBrand.apply();
    if (pass) pass.value = "";
    if (user) {
      user.value = "";
      user.focus();
    }
    err.classList.remove("show");
    document.querySelectorAll(".field.invalid").forEach((n) => n.classList.remove("invalid"));
  }

  window.KskAuth = { showApp, showLogin, AUTH_KEY };

  if (window.KskBrand) window.KskBrand.apply();

  if (sessionStorage.getItem(AUTH_KEY)) showApp();
  else showLogin();

  toggle.addEventListener("click", () => {
    const show = pass.type === "password";
    pass.type = show ? "text" : "password";
    toggle.setAttribute("aria-label", show ? "Hide password" : "Show password");
  });

  function fail(message) {
    wrap.classList.remove("shake");
    void wrap.offsetWidth;
    wrap.classList.add("shake");
    user.closest(".field").classList.add("invalid");
    pass.closest(".field").classList.add("invalid");
    err.textContent = message;
    err.classList.add("show");
    flash.classList.remove("show");
    void flash.offsetWidth;
    flash.classList.add("show");
    btn.disabled = false;
    btn.innerHTML = "Sign in";
  }

  function success() {
    sessionStorage.setItem(AUTH_KEY, "1");
    overlay.classList.add("show");
    setTimeout(showApp, 1200);
  }

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    err.classList.remove("show");
    user.closest(".field").classList.remove("invalid");
    pass.closest(".field").classList.remove("invalid");
    btn.disabled = true;
    btn.innerHTML = `<span class="spinner"></span> Signing in`;

    const u = user.value.trim();
    const p = pass.value;

    setTimeout(() => {
      if (u === "admin" && p === "admin") success();
      else fail("Invalid username or password.");
    }, 650);
  });

  user.addEventListener("input", () => user.closest(".field").classList.remove("invalid"));
  pass.addEventListener("input", () => pass.closest(".field").classList.remove("invalid"));
})();
