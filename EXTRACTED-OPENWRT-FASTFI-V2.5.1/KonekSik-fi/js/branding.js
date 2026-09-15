/**
 * Login + navbar logo branding (stored in localStorage for this UI prototype).
 */
window.KskBrand = (function () {
  const LOGIN_KEY = "ksk_login_logo";
  const NAV_KEY = "ksk_nav_logo";
  const MAX_BYTES = 3 * 1024 * 1024;
  const DEFAULT_LOGIN = "public/Logo.png";
  const DEFAULT_NAV = "public/navbar.png";
  const TYPES = ["image/png", "image/jpeg", "image/webp", "image/gif"];

  function getLoginLogo() {
    try { return localStorage.getItem(LOGIN_KEY) || ""; } catch (e) { return ""; }
  }

  function getNavLogo() {
    try { return localStorage.getItem(NAV_KEY) || ""; } catch (e) { return ""; }
  }

  function setItem(key, value) {
    try {
      if (value) localStorage.setItem(key, value);
      else localStorage.removeItem(key);
      return true;
    } catch (e) {
      return false;
    }
  }

  function apply() {
    const loginSrc = getLoginLogo() || DEFAULT_LOGIN;
    const loginImg = document.getElementById("login-logo");
    if (loginImg && loginImg.getAttribute("src") !== loginSrc) loginImg.src = loginSrc;

    const navImg = document.getElementById("nav-logo");
    const wrap = document.getElementById("nav-logo-wrap");
    const navSrc = getNavLogo() || DEFAULT_NAV;
    if (navImg) {
      if (navImg.getAttribute("src") !== navSrc) navImg.src = navSrc;
      navImg.hidden = false;
      if (wrap) wrap.classList.add("has-image");
    }

    if (window.AppData && AppData.settings) {
      AppData.settings.loginLogo = getLoginLogo();
      AppData.settings.navLogo = getNavLogo();
    }
  }

  function readAsDataURL(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(new Error("Could not read that file."));
      reader.readAsDataURL(file);
    });
  }

  function loadImage(src) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error("That image could not be opened."));
      img.src = src;
    });
  }

  function resizeToDataURL(img, maxEdge, mime) {
    const w = img.naturalWidth || img.width;
    const h = img.naturalHeight || img.height;
    const scale = Math.min(1, maxEdge / Math.max(w, h));
    const cw = Math.max(1, Math.round(w * scale));
    const ch = Math.max(1, Math.round(h * scale));
    const canvas = document.createElement("canvas");
    canvas.width = cw;
    canvas.height = ch;
    const ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, cw, ch);
    ctx.drawImage(img, 0, 0, cw, ch);
    const keepAlpha = mime === "image/png" || mime === "image/webp";
    return keepAlpha ? canvas.toDataURL("image/png") : canvas.toDataURL("image/jpeg", 0.9);
  }

  async function fromFile(file, kind) {
    if (!file) throw new Error("Choose an image first.");
    if (file.size > MAX_BYTES) throw new Error("Image must be 3 MB or smaller.");
    const type = (file.type || "").toLowerCase();
    if (type && !TYPES.includes(type)) {
      throw new Error("Use PNG, JPG, or WEBP. Remove the background first.");
    }
    const dataUrl = await readAsDataURL(file);
    const img = await loadImage(dataUrl);
    const maxEdge = kind === "nav" ? 720 : 900;
    return resizeToDataURL(img, maxEdge, type || "image/png");
  }

  function saveLogin(dataUrl) {
    if (!setItem(LOGIN_KEY, dataUrl)) throw new Error("Could not save the logo. Try a smaller PNG.");
    apply();
  }

  function saveNav(dataUrl) {
    if (!setItem(NAV_KEY, dataUrl)) throw new Error("Could not save the logo. Try a smaller PNG.");
    apply();
  }

  function clearLogin() {
    setItem(LOGIN_KEY, "");
    apply();
  }

  function clearNav() {
    setItem(NAV_KEY, "");
    apply();
  }

  return {
    MAX_BYTES,
    DEFAULT_LOGIN,
    DEFAULT_NAV,
    getLoginLogo,
    getNavLogo,
    apply,
    fromFile,
    saveLogin,
    saveNav,
    clearLogin,
    clearNav,
  };
})();
