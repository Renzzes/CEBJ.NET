/**
 * CaptivePortalLivePreview — admin-only visual mock of the guest portal.
 * Banner: local blob after file pick ONLY (never auto-fetch saved appliance assets).
 * If appliance has custom banner but no local file → "Custom banner active" placeholder.
 */
(function (global) {
  "use strict";

  var DESIGN_WIDTH = 520;
  var state = {
    blobUrl: null,
    musicBlobUrl: null,
    hasApplianceCustom: false,
    credits: 0,
    secondsLeft: 0,
    connected: false,
    timerId: null,
    musicEl: null,
  };

  function $(id) {
    return document.getElementById(id);
  }

  function pad(n) {
    return String(n).padStart(2, "0");
  }

  function formatTime(sec) {
    var s = Math.max(0, sec | 0);
    return pad(Math.floor(s / 3600)) + ":" + pad(Math.floor((s % 3600) / 60)) + ":" + pad(s % 60);
  }

  function revoke(url) {
    if (url) {
      try {
        URL.revokeObjectURL(url);
      } catch (e) {}
    }
  }

  function setSyncPill(pending) {
    var pill = $("cpSyncPill");
    if (!pill) return;
    pill.classList.toggle("is-pending", !!pending);
    pill.textContent = pending ? "Unsaved local pick" : "Synced";
  }

  function renderBanner() {
    var img = $("plpBannerImg");
    var ph = $("plpBannerPlaceholder");
    if (!img || !ph) return;

    // DMA guard: never set img.src to /image/* appliance paths.
    if (state.blobUrl) {
      img.src = state.blobUrl;
      img.classList.add("is-active");
      ph.hidden = true;
      return;
    }

    img.removeAttribute("src");
    img.classList.remove("is-active");
    ph.hidden = false;
    if (state.hasApplianceCustom) {
      ph.innerHTML = "<strong>Custom banner active</strong>Pick a file to preview it here before upload.";
    } else {
      ph.innerHTML = "<strong>Default banner</strong>Pick an image to preview the uploaded banner.";
    }
  }

  function renderHud() {
    var status = $("plpStatus");
    var credits = $("plpCredits");
    var timer = $("plpTimer");
    var dateEl = $("plpDate");
    if (status) {
      status.textContent = state.connected ? "Connected" : "Disconnected";
      status.className = state.connected ? "is-on" : "is-off";
    }
    if (credits) credits.textContent = "₱" + Number(state.credits || 0).toFixed(2);
    if (timer) timer.textContent = formatTime(state.secondsLeft);
    if (dateEl) {
      dateEl.textContent = new Date().toLocaleString("en-PH", {
        weekday: "short",
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
      });
    }
  }

  function stopTimer() {
    if (state.timerId) {
      clearInterval(state.timerId);
      state.timerId = null;
    }
  }

  function stopMusic() {
    if (state.musicEl) {
      try {
        state.musicEl.pause();
        state.musicEl.currentTime = 0;
      } catch (e) {}
    }
  }

  function playLocalMusic() {
    if (!state.musicBlobUrl || !state.musicEl) return;
    try {
      state.musicEl.src = state.musicBlobUrl;
      state.musicEl.loop = true;
      state.musicEl.play().catch(function () {});
    } catch (e) {}
  }

  function startPreviewSession() {
    state.credits = Math.max(1, Number(state.credits) || 0) + 5;
    state.secondsLeft = Math.max(state.secondsLeft, 0) + 5 * 60;
    state.connected = true;
    stopTimer();
    renderHud();
    playLocalMusic();
    state.timerId = setInterval(function () {
      if (state.secondsLeft <= 0) {
        stopTimer();
        stopMusic();
        state.connected = false;
        renderHud();
        return;
      }
      state.secondsLeft -= 1;
      renderHud();
    }, 1000);
  }

  function scalePreview() {
    var viewport = $("plpViewport");
    var wrap = $("plpScaleWrap");
    var shell = $("plpShell");
    if (!viewport || !wrap || !shell) return;
    // Reset so we measure natural shell size
    wrap.style.transform = "scale(1)";
    wrap.style.width = DESIGN_WIDTH + "px";
    wrap.style.height = "auto";
    var availW = Math.max(200, viewport.clientWidth - 20);
    var availH = Math.max(280, viewport.clientHeight - 20);
    var naturalH = shell.offsetHeight || 1;
    var scaleW = availW / DESIGN_WIDTH;
    var scaleH = availH / naturalH;
    var scale = Math.min(1, scaleW, scaleH);
    wrap.style.transform = "scale(" + scale + ")";
    wrap.style.height = naturalH * scale + "px";
  }

  function setBannerFile(file) {
    revoke(state.blobUrl);
    state.blobUrl = null;
    var thumb = $("cpBannerThumb");
    if (file && file.type && file.type.indexOf("image/") === 0) {
      state.blobUrl = URL.createObjectURL(file);
      if (thumb) {
        thumb.src = state.blobUrl;
        thumb.classList.add("is-visible");
      }
      setSyncPill(true);
    } else if (thumb) {
      thumb.removeAttribute("src");
      thumb.classList.remove("is-visible");
      setSyncPill(false);
    }
    renderBanner();
  }

  function setMusicFile(file) {
    revoke(state.musicBlobUrl);
    state.musicBlobUrl = null;
    if (file && (/audio\//.test(file.type) || /\.mp3$/i.test(file.name || ""))) {
      state.musicBlobUrl = URL.createObjectURL(file);
      setSyncPill(true);
    }
  }

  function setApplianceCustom(hasCustom) {
    state.hasApplianceCustom = !!hasCustom;
    renderBanner();
  }

  function clearLocalPicks() {
    revoke(state.blobUrl);
    revoke(state.musicBlobUrl);
    state.blobUrl = null;
    state.musicBlobUrl = null;
    var thumb = $("cpBannerThumb");
    if (thumb) {
      thumb.removeAttribute("src");
      thumb.classList.remove("is-visible");
    }
    var bannerInput = $("bannerFile");
    if (bannerInput) bannerInput.value = "";
    var musicInput = $("audioFile_bg");
    if (musicInput) musicInput.value = "";
    setSyncPill(false);
    renderBanner();
  }

  function bind() {
    var bannerInput = $("bannerFile");
    if (bannerInput && !bannerInput._plpBound) {
      bannerInput._plpBound = true;
      bannerInput.addEventListener("change", function () {
        setBannerFile(bannerInput.files && bannerInput.files[0]);
      });
    }

    var musicInput = $("audioFile_bg");
    if (musicInput && !musicInput._plpBound) {
      musicInput._plpBound = true;
      musicInput.addEventListener("change", function () {
        setMusicFile(musicInput.files && musicInput.files[0]);
      });
    }

    var insertBtn = $("plpInsertCoin");
    if (insertBtn && !insertBtn._plpBound) {
      insertBtn._plpBound = true;
      insertBtn.addEventListener("click", function () {
        startPreviewSession();
      });
    }

    if (!state.musicEl) {
      state.musicEl = document.createElement("audio");
      state.musicEl.preload = "auto";
    }

    renderBanner();
    renderHud();
    scalePreview();
  }

  function init() {
    bind();
    scalePreview();
    if (!global._plpResizeBound) {
      global._plpResizeBound = true;
      global.addEventListener("resize", function () {
        scalePreview();
      });
    }
  }

  global.CaptivePortalLivePreview = {
    init: init,
    scale: scalePreview,
    setApplianceCustom: setApplianceCustom,
    clearLocalPicks: clearLocalPicks,
    setBannerFile: setBannerFile,
    setMusicFile: setMusicFile,
    render: function () {
      renderBanner();
      renderHud();
      scalePreview();
    },
  };
})(window);
