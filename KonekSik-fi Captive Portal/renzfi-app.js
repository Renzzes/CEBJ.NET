(function () {
  "use strict";

  // ── configuration ──────────────────────────────────────────────────────────
  // API baseline = FastFi OpenWrt CGI (/cgi-bin/api?action=…), matching
  // EXTRACTED-OPENWRT-FASTFI-V2.5.1/rootfs/www/bootstrap.js exactly.
  // Do not call legacy /api/portal/* (RenzFi / MikroTik / ESP) endpoints.
  // Same-origin with the router (or local demo-server that mocks FastFi CGI).
  var CGI = (window.FastFiCgi && window.FastFiCgi.CGI) || "/cgi-bin/api";
  var STORAGE_PREFIX    = "koneksikPortalState";
  var INSERT_TIMEOUT    = 60;
  // Idle standby: no periodic heartbeat. Active paid sessions use a slow sync
  // only (local countdown owns the display). Coin modal uses COIN_POLL_MS
  // (FastFi bootstrap also polls fetchcoin every 500ms).
  var ACTIVE_SYNC_MS    = 60000;
  var COIN_POLL_MS      = 500;
  // After local time hits 0 / Expiring starts, keep a short live window so the
  // recycle → idle transition is not missed.
  var EXPIRE_SETTLE_MS       = 20000;
  var EXPIRE_SETTLE_POLL_MS  = 2000;

  // Consecutive background-request failures before showing the
  // "service temporarily unavailable" notice (see noteApplianceFailure()).
  var SERVICE_UNAVAILABLE_THRESHOLD = 2;

  // FastFi runtime (coin slot + rate computation mirrors bootstrap.js).
  var ff = {
    deviceId: "",
    clientId: "",
    slotMac: "",
    coinWindow: false,
    coinStartedAt: 0,
    currentCoin: 0,
    lastCoin: 0,
    totalSeconds: 0,
    totalDownload: 0,
    totalUpload: 0,
    totalPausedLimit: 0,
    totalDataLimit: 0,
    totalValidityMinutes: 0,
    ratesList: [],
    pauseLimit: 0
  };

  // ── timers ─────────────────────────────────────────────────────────────────
  var mainTimer      = null;
  var coinTimer      = null;
  var coinPollTimer  = null;
  var heartbeatTimer = null;

  // Monotonic generation for GET /session — overlapping responses must not
  // apply out of order (countdown rebase / coin-window races).
  var sessionSyncGen = 0;

  // Countdown anchors — the only place elapsed time is tracked in the browser.
  var sessionExpiryAt      = 0;     // wall-clock instant the session runs out
  var sessionFrozenSeconds = 0;     // value to show while the clock is stopped
  var sessionTimerRunning  = false; // firmware says the countdown is advancing
  var coinAnchorSeconds    = 0;
  var coinAnchorAt         = 0;

  // Coin modal lifecycle guards — prevent duplicate cancel/poll/timer requests.
  var coinModalVisible     = false;
  var coinCancelInFlight   = false;
  var donePayingInFlight   = false;
  var coinTimeoutHandled   = false;
  var lastWindowInserted   = 0;
  var sessionNoticeTicks   = 0;
  var warnedAt30Seconds    = false;
  var warnedAt15Seconds    = false;

  // ── device identification ──────────────────────────────────────────────────
  function textOf(id) {
    var el = document.getElementById(id);
    return el ? el.textContent.trim() : "";
  }

  function getDeviceMAC() {
    var mac = textOf("macAddress");
    return mac && mac.indexOf("$(") === -1 ? mac : "";
  }

  function getDeviceIP() {
    var ip = textOf("ipAddress");
    return ip && ip.indexOf("$(") === -1 ? ip : "";
  }

  function getDeviceKey() {
    var mac = getDeviceMAC();
    var ip  = getDeviceIP();
    return (mac || ip || "unknown-device").replace(/[^a-z0-9._:-]/gi, "_");
  }

  function deviceParams() {
    return { mac: getDeviceMAC(), ip: getDeviceIP() };
  }

  // ── FastFi CGI helpers (baseline bootstrap.js) ─────────────────────────────
  function cgi() {
    if (!window.FastFiCgi) throw new Error("FastFiCgi client missing — load fastfi-cgi.js first");
    return window.FastFiCgi;
  }

  function ensureDeviceIds() {
    try {
      ff.deviceId = localStorage.getItem("FASTFI_DEVICE_ID") || "";
      if (!ff.deviceId) {
        ff.deviceId = "web-" + Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
        localStorage.setItem("FASTFI_DEVICE_ID", ff.deviceId);
      }
    } catch (e) {
      ff.deviceId = ff.deviceId || ("web-" + Date.now());
    }
    try {
      ff.clientId = localStorage.getItem("FASTFI_CLIENT_ID") || ff.deviceId;
      if (!localStorage.getItem("FASTFI_CLIENT_ID")) {
        localStorage.setItem("FASTFI_CLIENT_ID", ff.clientId);
      }
    } catch (e2) {
      ff.clientId = ff.deviceId;
    }
    return ff.deviceId;
  }

  function setDomIdentity(mac, ip) {
    var macEl = document.getElementById("macAddress");
    var ipEl = document.getElementById("ipAddress");
    if (macEl && mac) macEl.textContent = mac;
    if (ipEl && ip) ipEl.textContent = ip;
  }

  function apiFail(message, code) {
    var err = new Error(message || "API request failed");
    err.code = code || "";
    return err;
  }

  /** Mirror bootstrap.js onCoinInserted() rate stacking. */
  function computeTotalsFromCoin(coins) {
    var ratesList = ff.ratesList || [];
    var validRates = ratesList.filter(function (r) { return Number(r.time) > 0 || Number(r.data_limit_mb) > 0; });
    var activeRates = validRates.length > 0 ? validRates : ratesList;
    var tiers = activeRates.slice().sort(function (a, b) {
      return Number(a.price) - Number(b.price);
    });
    if (!tiers.length) {
      ff.totalSeconds = 0;
      ff.totalDownload = 0;
      ff.totalUpload = 0;
      ff.totalPausedLimit = 0;
      ff.totalDataLimit = 0;
      ff.totalValidityMinutes = 0;
      return;
    }
    var base = tiers[0];
    var remaining = Number(coins) || 0;
    var totalTime = 0;
    var currentDownload = Number(base.download_mb) || 0;
    var currentUpload = Number(base.upload_mb) || 0;
    var computedPausedLimit = 0;
    var computedDataLimit = 0;
    var computedValidityMinutes = 0;
    var isUnliData = false;
    var highestTier = null;
    for (var i = 0; i < tiers.length; i++) {
      var t = tiers[i];
      if (Number(t.price) >= 1 && remaining >= Number(t.price)) highestTier = t;
    }
    if (highestTier) {
      totalTime = Number(highestTier.time) || 0;
      currentDownload = Number(highestTier.download_mb) || 0;
      currentUpload = Number(highestTier.upload_mb) || 0;
      computedPausedLimit = Number(highestTier.paused_limit) || 0;
      computedDataLimit = Number(highestTier.data_limit_mb) || 0;
      computedValidityMinutes = Number(highestTier.validity_minutes) || 0;
      if (computedDataLimit === 0) isUnliData = true;
      remaining -= Number(highestTier.price) || 0;
    } else if (coins > 0) {
      if ((Number(base.data_limit_mb) || 0) === 0) isUnliData = true;
    }
    var smallerTiers = tiers.filter(function (t) {
      return Number(t.price) >= 1 && Number(t.price) < Number(highestTier ? highestTier.price : Infinity);
    }).sort(function (a, b) { return Number(b.price) - Number(a.price); });
    for (var j = 0; j < smallerTiers.length; j++) {
      var st = smallerTiers[j];
      var price = Number(st.price) || 0;
      if (price <= 0) continue;
      var blocks = Math.floor(remaining / price);
      if (blocks > 0) {
        totalTime += blocks * (Number(st.time) || 0);
        computedPausedLimit += blocks * (Number(st.paused_limit) || 0);
        computedValidityMinutes += blocks * (Number(st.validity_minutes) || 0);
        var tData = Number(st.data_limit_mb) || 0;
        if (tData === 0) isUnliData = true;
        computedDataLimit += blocks * tData;
        remaining -= blocks * price;
      }
    }
    totalTime += remaining * (Number(base.time) || 0);
    computedPausedLimit += remaining * (Number(base.paused_limit) || 0);
    computedValidityMinutes += remaining * (Number(base.validity_minutes) || 0);
    var bData2 = Number(base.data_limit_mb) || 0;
    if (remaining > 0 && bData2 === 0) isUnliData = true;
    computedDataLimit += remaining * bData2;
    if (isUnliData) computedDataLimit = 0;
    if (totalTime === 0 && computedDataLimit > 0) {
      totalTime = computedValidityMinutes > 0
        ? computedValidityMinutes * 60
        : 30 * 24 * 60 * 60;
    }
    ff.totalSeconds = totalTime;
    ff.totalDownload = currentDownload;
    ff.totalUpload = currentUpload;
    ff.totalPausedLimit = computedPausedLimit;
    ff.totalDataLimit = computedDataLimit;
    ff.totalValidityMinutes = computedValidityMinutes;
  }

  function coinWindowRemaining() {
    if (!ff.coinWindow) return 0;
    var elapsed = Math.floor((Date.now() - ff.coinStartedAt) / 1000);
    return Math.max(0, INSERT_TIMEOUT - elapsed);
  }

  function sessionFromFastFi(device, status) {
    device = device || {};
    status = status || {};
    var remaining = Number(status.remaining);
    if (!(remaining > 0)) remaining = Number(device.time) || 0;
    var paused = Number(status.paused) === 1 || String(status.status) === "paused";
    var internetOn = Number(device.internet) === 1 || String(status.status) === "active";
    var connected = internetOn && remaining > 0 && !paused;
    var sessionState = "idle";
    if (ff.coinWindow) sessionState = "waiting_coin";
    else if (paused && remaining > 0) sessionState = "paused";
    else if (remaining > 0) sessionState = "active";

    var pauseLimit = Number(device.paused_limit);
    if (!(pauseLimit > 0)) pauseLimit = ff.pauseLimit || 0;

    return {
      secondsLeft: remaining,
      timerRunning: sessionState === "active" && !paused && remaining > 0,
      credits: ff.coinWindow ? ff.currentCoin : (Number(device.coin) || 0),
      paused: paused,
      connected: connected,
      coinSessionActive: ff.coinWindow,
      coinWindowActive: ff.coinWindow,
      coinCountdown: coinWindowRemaining(),
      coinWindowRemaining: coinWindowRemaining(),
      insertedAmount: ff.coinWindow ? ff.currentCoin : 0,
      purchasedMinutes: Math.floor((ff.totalSeconds || 0) / 60),
      sessionState: sessionState,
      pausesUsed: Number(device.pause_count) || 0,
      pausesRemaining: null,
      pauseLimit: pauseLimit,
      source: "portal",
      voucherCode: "",
      canInsertCoin: true,
      canPause: remaining > 0,
      canResume: paused,
      canTerminate: remaining > 0,
      canReconnect: false,
      serverNowMs: Date.now()
    };
  }

  function loadRatesCache() {
    return cgi().rates().then(function (responseData) {
      var rows = Array.isArray(responseData && responseData.data) ? responseData.data : [];
      // FastFi rates.lua: data[].time is already seconds (= DB minutes × 60).
      ff.ratesList = rows.map(function (r) {
        var timeSec = Number(r.time);
        if (!(timeSec > 0) && r.minutes != null) timeSec = (Number(r.minutes) || 0) * 60;
        return {
          price: Number(r.price) || 0,
          time: timeSec || 0,
          download_mb: Number(r.download_mb != null ? r.download_mb : r.dl_mb) || 0,
          upload_mb: Number(r.upload_mb != null ? r.upload_mb : r.ul_mb) || 0,
          paused_limit: Number(r.paused_limit != null ? r.paused_limit : r.pause_limit) || 0,
          validity_minutes: Number(r.validity_minutes) || 0,
          data_limit_mb: Number(r.data_limit_mb != null ? r.data_limit_mb : r.data_mb) || 0,
          minutes: timeSec > 0 ? Math.floor(timeSec / 60) : (Number(r.minutes) || 0)
        };
      });
      if (ff.ratesList.length && ff.ratesList[0].paused_limit) {
        ff.pauseLimit = Number(ff.ratesList[0].paused_limit) || ff.pauseLimit;
      }
      return ff.ratesList;
    });
  }

  function pickEspSlot(listPayload) {
    // FastFi list_esp_devices → { esp_devices:[{ slot_mac, status, license_status, … }] }
    var list = [];
    if (Array.isArray(listPayload)) list = listPayload;
    else if (listPayload && Array.isArray(listPayload.esp_devices)) list = listPayload.esp_devices;
    else if (listPayload && Array.isArray(listPayload.data)) list = listPayload.data;
    else if (listPayload && Array.isArray(listPayload.devices)) list = listPayload.devices;

    function slotMacOf(d) {
      return String((d && (d.slot_mac || d.mac)) || "");
    }
    function isOnline(d) {
      var st = String((d && d.status) || "").toLowerCase();
      return !st || st === "online";
    }
    function isLicensed(d) {
      var ls = String((d && d.license_status) || "").toLowerCase();
      return !ls || ls === "licensed" || ls === "active" || ls === "ok";
    }
    function isBusy(d) {
      var busy = d && (d.busy || d.locked || d.in_use);
      return busy === true || busy === 1 || busy === "1";
    }

    var i;
    for (i = 0; i < list.length; i++) {
      var d = list[i] || {};
      var mac = slotMacOf(d);
      if (!mac || isBusy(d) || !isOnline(d) || !isLicensed(d)) continue;
      return mac;
    }
    for (i = 0; i < list.length; i++) {
      var d2 = list[i] || {};
      var mac2 = slotMacOf(d2);
      if (!mac2 || isBusy(d2) || !isOnline(d2)) continue;
      return mac2;
    }
    for (i = 0; i < list.length; i++) {
      var mac3 = slotMacOf(list[i]);
      if (mac3) return mac3;
    }
    return "";
  }

  /** Resume mid-insert after refresh — FastFi check_coin_lock. */
  function tryResumeCoinLock() {
    ensureDeviceIds();
    var mac = getDeviceMAC();
    if (!mac || !cgi().checkCoinLock) return Promise.resolve(null);
    return cgi().checkCoinLock(mac).then(function (data) {
      if (!data || !data.locked) return null;
      var slot = data.slot_mac || "";
      if (!slot) return null;
      ff.slotMac = slot;
      ff.coinWindow = true;
      ff.currentCoin = parseInt(data.coin, 10) || 0;
      ff.lastCoin = ff.currentCoin;
      var remaining = Number(data.remaining_timer);
      if (!(remaining > 0)) remaining = Number(data.insert_timer) || INSERT_TIMEOUT;
      ff.coinStartedAt = Date.now() - Math.max(0, (INSERT_TIMEOUT - remaining) * 1000);
      computeTotalsFromCoin(ff.currentCoin);
      return normalizeSession(sessionFromFastFi({}, {}));
    }).catch(function () { return null; });
  }

  function refreshIdentityFromNetwork() {
    ensureDeviceIds();
    return cgi().getMac().then(function (data) {
      if (data && (data.mac || data.ip)) setDomIdentity(data.mac || "", data.ip || "");
      return data || {};
    }).catch(function () { return {}; });
  }

  function normalizeSession(raw) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;

    var coinActive = raw.coinSessionActive;
    if (coinActive === undefined) coinActive = raw.coin_session_active;
    if (coinActive === undefined) coinActive = raw.coinWindowActive;
    if (coinActive === undefined) coinActive = raw.coin_window_active;

    var coinCountdown = raw.coinCountdown;
    if (coinCountdown === undefined) coinCountdown = raw.coin_countdown;
    if (coinCountdown === undefined) coinCountdown = raw.coinWindowRemaining;
    if (coinCountdown === undefined) coinCountdown = raw.coin_window_remaining;

    var stateStr = raw.sessionState || raw.session_state || "";
    var source = raw.source || raw.session_source || "portal";
    var secondsLeft = Number(raw.secondsLeft || raw.seconds_left) || 0;
    var paused = Boolean(raw.paused);

    return {
      secondsLeft:       secondsLeft,
      // Firmware-declared: is the countdown advancing right now? Older builds
      // that omit the flag fall back to the equivalent state test.
      timerRunning:      raw.timerRunning !== undefined
                            ? Boolean(raw.timerRunning)
                            : (stateStr === "active" && !paused && secondsLeft > 0),
      credits:           Number(raw.credits)                                    || 0,
      paused:            paused,
      connected:         Boolean(raw.connected),
      coinSessionActive: Boolean(coinActive),
      // Allow 0 (window expired). `Number(0) || INSERT_TIMEOUT` wrongly resets to 60.
      coinCountdown:     (coinCountdown === undefined || coinCountdown === null)
                            ? INSERT_TIMEOUT
                            : Math.max(0, Number(coinCountdown) || 0),
      insertedAmount:    Number(raw.insertedAmount   || raw.inserted_amount)    || 0,
      purchasedMinutes:  Number(raw.purchasedMinutes || raw.purchased_minutes)  || 0,
      sessionState:      stateStr,
      activationError:   Boolean(raw.activationError || raw.activation_error),
      activationErrorReason: raw.activationErrorReason ||
                             raw.activation_error_reason || "",
      pausesUsed:        raw.pausesUsed !== undefined
                            ? Number(raw.pausesUsed)
                            : (raw.pauses_used !== undefined
                                ? Number(raw.pauses_used)
                                : undefined),
      pausesRemaining:   (function () {
        if (raw.pausesRemaining !== undefined) return Number(raw.pausesRemaining);
        if (raw.pauses_remaining !== undefined) return Number(raw.pauses_remaining);
        var used = raw.pausesUsed !== undefined ? Number(raw.pausesUsed)
                 : (raw.pauses_used !== undefined ? Number(raw.pauses_used) : undefined);
        var limit = Number(raw.pauseLimit || raw.pause_limit) || 0;
        if (used !== undefined && limit > 0) return Math.max(0, limit - used);
        return null;
      })(),
      pauseLimit:        Number(raw.pauseLimit || raw.pause_limit) || 0,
      source:             source,
      voucherCode:        raw.voucherCode || raw.voucher_code || "",
      voucherStatus:      raw.voucherStatus || raw.voucher_status || "",
      voucherExpiresAt:   raw.voucherExpiresAt || raw.voucher_expires_at || "",
      canInsertCoin:      raw.canInsertCoin !== undefined
                            ? Boolean(raw.canInsertCoin)
                            : source !== "voucher",
      canPause:           raw.canPause !== undefined
                            ? Boolean(raw.canPause)
                            : source !== "voucher",
      canResume:          raw.canResume !== undefined
                            ? Boolean(raw.canResume)
                            : source !== "voucher",
      canTerminate:       raw.canTerminate !== undefined
                            ? Boolean(raw.canTerminate)
                            : source !== "voucher",
      canReconnect:       raw.canReconnect !== undefined
                            ? Boolean(raw.canReconnect)
                            : source === "voucher",
      sessionGeneration:  Number(raw.sessionGeneration || raw.session_generation) || 0,
      grantedSeconds:     Number(raw.grantedSeconds || raw.granted_seconds) || 0,
      authorizedAtMs:     Number(raw.authorizedAtMs || raw.authorized_at_ms) || 0,
      expiresAtMs:        Number(raw.expiresAtMs || raw.expires_at_ms) || 0,
      serverNowMs:        Number(raw.serverNowMs || raw.server_now_ms) || 0,
      sessionNotice:      raw.sessionNotice || raw.session_notice || "",
      ownerDisconnectNotice: Boolean(
        raw.ownerDisconnectNotice || raw.owner_disconnect_notice
      )
    };
  }

  // Issue 5: richer promo normalizer — passes through speedProfile, deviceLimit, enabled.
  function normalizeRatesPayload(rawData) {
    // FastFi: { status:"ok", data:[{ price, minutes, download_mb, … }] }
    // Legacy: array / { rates: […] } with coin|peso
    var promos = Array.isArray(rawData)
      ? rawData
      : (rawData && (Array.isArray(rawData.data) ? rawData.data : rawData.rates));
    if (!Array.isArray(promos)) return null;

    var rates = promos.filter(function (p) {
      if (p.enabled === false || p.enabled === "false") return false;
      var peso = Number(
        p.price != null ? p.price : (p.coin != null ? p.coin : p.peso)
      ) || 0;
      var minutes = Number(p.minutes);
      if (!(minutes > 0) && Number(p.time) > 0) minutes = Math.floor(Number(p.time) / 60);
      return peso > 0 && minutes > 0;
    }).map(function (p) {
      var peso = Number(
        p.price != null ? p.price : (p.coin != null ? p.coin : p.peso)
      ) || 0;
      var minutes = Number(p.minutes);
      if (!(minutes > 0) && Number(p.time) > 0) minutes = Math.floor(Number(p.time) / 60);
      return {
        peso:         peso,
        minutes:      minutes,
        speedProfile: p.speedProfile || p.speed_profile || "",
        deviceLimit:  Number(p.deviceLimit || p.device_limit) || 0,
        enabled:      p.enabled !== false && p.enabled !== "false"
      };
    });

    rates.sort(function (a, b) { return a.peso - b.peso; });
    return { rates: rates };
  }

  // ── localStorage (UI cache only) ───────────────────────────────────────────
  var storageKey = STORAGE_PREFIX + ":device";

  function defaultState() {
    return {
      credits:            0,
      secondsLeft:        0,
      paused:             false,
      connected:          false,
      coinCountdown:      INSERT_TIMEOUT,
      coinSessionActive:  false,
      insertedAmount:     0,
      purchasedMinutes:   0,
      sessionState:       "idle",
      timerRunning:       false,
      activationError:    false,
      activationErrorReason: "",
      pausesRemaining:    null,
      pauseLimit:         0,
      source:             "portal",
      voucherCode:        "",
      voucherStatus:      "",
      voucherExpiresAt:   "",
      canInsertCoin:      true,
      canPause:           false,
      canResume:          false,
      canTerminate:       false,
      canReconnect:       false,
      sessionGeneration:  0,
      grantedSeconds:     0,
      // Per-session coin modal accumulators — always reset to zero when modal opens
      coinAmount:         0,
      coinMinutes:        0,
      coinVoucherMinutes: 0,
      coinPulseCount:     0,
      coinBaseCredits:    0
    };
  }

  function loadCachedState() {
    try {
      var saved = JSON.parse(localStorage.getItem(storageKey) || "{}");
      return {
        credits:            Number(saved.credits)           || 0,
        secondsLeft:        Number(saved.secondsLeft)       || 0,
        // Never resume ticking from cache — the countdown stays frozen on the
        // last known value until the firmware confirms timerRunning.
        timerRunning:       false,
        paused:             Boolean(saved.paused),
        connected:          Boolean(saved.connected),
        coinCountdown:      Number(saved.coinCountdown)     || INSERT_TIMEOUT,
        coinSessionActive:  Boolean(saved.coinSessionActive),
        insertedAmount:     Number(saved.insertedAmount)    || 0,
        purchasedMinutes:   Number(saved.purchasedMinutes)  || 0,
        sessionState:       saved.sessionState              || "idle",
        activationError:    Boolean(saved.activationError),
        activationErrorReason: saved.activationErrorReason || "",
        pausesRemaining:    saved.pausesRemaining != null
                              ? Number(saved.pausesRemaining)
                              : null,
        pauseLimit:         Number(saved.pauseLimit) || 0,
        source:             saved.source                    || "portal",
        voucherCode:        saved.voucherCode               || "",
        voucherStatus:      saved.voucherStatus             || "",
        voucherExpiresAt:   saved.voucherExpiresAt          || "",
        canInsertCoin:      saved.canInsertCoin !== false,
        canPause:           saved.canPause === true,
        canResume:          saved.canResume === true,
        canTerminate:       saved.canTerminate === true,
        canReconnect:       Boolean(saved.canReconnect),
        sessionGeneration:  Number(saved.sessionGeneration) || 0,
        grantedSeconds:     Number(saved.grantedSeconds) || 0,
        coinAmount:         0,
        coinMinutes:        0,
        coinVoucherMinutes: 0,
        coinPulseCount:     0,
        coinBaseCredits:    0
      };
    } catch (e) {
      return defaultState();
    }
  }

  function saveStateCache() {
    localStorage.setItem(storageKey, JSON.stringify(state));
  }

  var state = defaultState();
  var sessionHydrated = false;

  // ── countdown derivation ───────────────────────────────────────────────────
  // Presentation only. Remaining is derived from the firmware expiry
  // snapshot. The browser never becomes the authority for entitlement,
  // Internet authorization, or session generation.

  function serverRemainingOf(session) {
    var left = Math.max(0, Number(session.secondsLeft) || 0);
    var expiresAt = Number(session.expiresAtMs) || 0;
    var serverNow = Number(session.serverNowMs) || 0;
    if (expiresAt > 0 && serverNow > 0) {
      var fromClock = Math.max(0, Math.floor((expiresAt - serverNow) / 1000));
      if (left <= 0 || fromClock <= left) return fromClock;
    }
    return left;
  }

  function applySessionClock(session, previousGen, previousGranted, forceRebase) {
    var incomingLeft = serverRemainingOf(session);
    var incomingGen = Number(session.sessionGeneration) || 0;
    var incomingGranted = Number(session.grantedSeconds) || 0;
    var running = Boolean(session.timerRunning) && incomingLeft > 0 &&
                  Boolean(session.connected) && !session.paused;

    if (!running) {
      sessionTimerRunning  = false;
      sessionFrozenSeconds = incomingLeft;
      sessionExpiryAt      = 0;
      return incomingLeft;
    }

    var legitimateIncrease =
      (incomingGen > 0 && incomingGen > (Number(previousGen) || 0)) ||
      (incomingGranted > 0 && incomingGranted > (Number(previousGranted) || 0));

    var candidate = Date.now() + incomingLeft * 1000;
    // forceRebase: activation_error->active / trustFully must adopt ESP/MikroTik
    // remaining immediately (never keep a frozen localStorage/UI ahead of Active).
    if (forceRebase || !sessionTimerRunning || sessionExpiryAt === 0) {
      sessionExpiryAt = candidate;
    } else if (legitimateIncrease) {
      sessionExpiryAt = candidate;
    } else if (candidate < sessionExpiryAt) {
      sessionExpiryAt = candidate;
    }

    sessionTimerRunning  = true;
    sessionFrozenSeconds = incomingLeft;
    return incomingLeft;
  }

  function anchorSession(seconds, running) {
    applySessionClock({
      secondsLeft: seconds,
      timerRunning: running,
      connected: running,
      paused: false,
      sessionGeneration: state.sessionGeneration,
      grantedSeconds: state.grantedSeconds,
      expiresAtMs: 0,
      serverNowMs: 0
    }, state.sessionGeneration, state.grantedSeconds);
  }

  function displaySeconds() {
    if (!sessionTimerRunning) return sessionFrozenSeconds;
    return Math.max(0, Math.ceil((sessionExpiryAt - Date.now()) / 1000));
  }

  function anchorCoinWindow(seconds) {
    coinAnchorSeconds = Math.max(0, Number(seconds) || 0);
    coinAnchorAt      = Date.now();
  }

  function derivedCoinSeconds() {
    if (!state.coinSessionActive) return INSERT_TIMEOUT;
    var elapsed = Math.floor((Date.now() - coinAnchorAt) / 1000);
    return Math.max(0, coinAnchorSeconds - Math.max(0, elapsed));
  }

  function applyNormalizedSession(session, trustFully) {
    if (!session) return;

    var incomingGen = Number(session.sessionGeneration) || 0;
    var currentGen = Number(state.sessionGeneration) || 0;
    if (!trustFully && incomingGen > 0 && currentGen > 0 && incomingGen < currentGen) {
      return;
    }

    // Credits, pause, coin state are always authoritative from server
    var hadCoinSession = state.coinSessionActive;
    var previousCredits = state.credits;
    var previousInserted = state.insertedAmount;
    var previousSeconds = state.secondsLeft;
    var previousSessionState = state.sessionState;
    var previousGen = currentGen;
    var previousGranted = Number(state.grantedSeconds) || 0;
    state.credits           = session.credits;
    state.paused            = session.paused;
    state.connected         = session.connected;
    state.coinSessionActive = session.coinSessionActive;
    state.insertedAmount    = session.insertedAmount;
    state.purchasedMinutes  = session.purchasedMinutes || 0;
    state.sessionState      = session.sessionState || state.sessionState;
    state.activationError   = Boolean(session.activationError);
    state.activationErrorReason = session.activationErrorReason || "";
    if (session.pausesRemaining !== null && session.pausesRemaining !== undefined) {
      state.pausesRemaining = session.pausesRemaining;
    } else if (session.pausesUsed !== null && session.pausesUsed !== undefined &&
               state.pauseLimit > 0) {
      state.pausesRemaining = Math.max(0, state.pauseLimit - session.pausesUsed);
    }
    if (session.pauseLimit) state.pauseLimit = session.pauseLimit;
    state.source            = session.source || "portal";
    state.voucherCode       = session.voucherCode || "";
    state.voucherStatus     = session.voucherStatus || "";
    state.voucherExpiresAt  = session.voucherExpiresAt || "";
    state.canInsertCoin     = session.canInsertCoin;
    state.canPause          = session.canPause;
    state.canResume         = session.canResume;
    state.canTerminate      = session.canTerminate;
    state.canReconnect      = session.canReconnect;
    if (incomingGen > 0) state.sessionGeneration = incomingGen;
    if (session.grantedSeconds !== undefined && session.grantedSeconds !== null) {
      state.grantedSeconds = Number(session.grantedSeconds) || 0;
    }

    // Server closed the insert window — update UI only; never mutate server state.
    if (hadCoinSession && !session.coinSessionActive &&
        dom.coinModal && !dom.coinModal.hidden) {
      stopCoinSessionUI();
      closeModal(dom.coinModal, true);
    }

    // Prefer server window amount; fall back to credit delta when unavailable.
    if (state.coinSessionActive) {
      var windowAmt = Number(session.insertedAmount) || 0;
      if (windowAmt > 0 || session.insertedAmount === 0) {
        if (windowAmt > lastWindowInserted) playCoinSound();
        lastWindowInserted = windowAmt;
        state.coinAmount = windowAmt;
      } else {
        state.coinAmount = Math.max(0, session.credits - (state.coinBaseCredits || 0));
      }
      state.coinVoucherMinutes = Number(session.purchasedMinutes) || 0;

      // ESP32 owns coinWindowRemaining. Presentation uses a monotonic deadline so
      // a ~2s poll with a slightly older snapshot cannot rewind 55 → 56.
      // Legitimate resets: new coin (credits/insertedAmount up) or trustFully.
      var serverRem = Math.max(0, Number(session.coinCountdown) || 0);
      var presentRem = hadCoinSession ? derivedCoinSeconds() : serverRem;
      var newCoin = session.credits > previousCredits ||
                    windowAmt > previousInserted;
      var openedNow = !hadCoinSession && session.coinSessionActive;
      if (serverRem <= 0) {
        state.coinCountdown = 0;
        anchorCoinWindow(0);
      } else if (trustFully || newCoin || openedNow) {
        state.coinCountdown = serverRem;
        anchorCoinWindow(serverRem);
      } else {
        // Monotonic: never climb. Only re-anchor when the server is *earlier*
        // than the local clock. Re-anchoring to presentRem on every poll would
        // reset elapsed to 0 under COIN_POLL_MS (500) and freeze the UI at 60.
        var adopt = Math.min(presentRem, serverRem);
        state.coinCountdown = adopt;
        if (adopt < presentRem) {
          anchorCoinWindow(adopt);
        }
      }
    } else {
      state.coinCountdown = session.coinCountdown;
    }

    // Presentation clock: never increase remaining unless generation or
    // grantedSeconds increased. Force rebase on trustFully or Active transition
    // so post-recovery Connected matches MikroTik Active (shorten-only path).
    state.timerRunning  = session.timerRunning;
    var becameActive =
      previousSessionState !== "active" && state.sessionState === "active";
    var forceRebase = Boolean(trustFully) || becameActive;
    state.secondsLeft   = applySessionClock(
      session, previousGen, previousGranted, forceRebase);

    var timeIncreased = state.secondsLeft > previousSeconds;
    if (becameActive || timeIncreased) {
      if (state.secondsLeft > 30) warnedAt30Seconds = false;
      if (state.secondsLeft > 15) warnedAt15Seconds = false;
      hideSessionNotice();
    }
    if (state.sessionState !== "active" || !state.connected ||
        state.secondsLeft <= 0 || state.paused) {
      if (!session.ownerDisconnectNotice) hideSessionNotice();
    } else {
      updateSessionNotice(previousSeconds, state.secondsLeft);
    }

    if (session.sessionNotice) {
      showSessionNotice(session.sessionNotice, false);
      if (session.ownerDisconnectNotice) {
        sessionNoticeTicks = 600;
      }
    }

    saveStateCache();
    sessionHydrated = true;

    // Expiring briefly hides canInsertCoin; stay live until recycle → idle.
    if (state.sessionState === "expiring" || state.sessionState === "expired") {
      beginExpireSettle("server-expiring");
    } else if (sessionAwaitingPaymentUi() &&
               (previousSessionState === "expiring" ||
                previousSessionState === "expired" ||
                previousSessionState === "active" ||
                previousSessionState === "activating") &&
               state.secondsLeft <= 0 && !state.connected) {
      clearExpireSettle();
    }

    render();
    updateIdleSyncPolicy();
  }

  function applySessionData(raw, trustFully) {
    applyNormalizedSession(normalizeSession(raw), trustFully);
  }

  // ── DOM refs ───────────────────────────────────────────────────────────────
  var dom = {};

  function cacheDom() {
    dom.insertCoinBtn      = document.getElementById("insertCoinBtn") ||
                             document.getElementById("insertCoinButton");
    dom.insertCoinLabel    = dom.insertCoinBtn &&
                             dom.insertCoinBtn.querySelector(".action-label");
    dom.pauseButton        = document.getElementById("pauseButton");
    dom.pauseButtonText    = document.getElementById("pauseButtonText");
    dom.terminateBtn       = document.getElementById("terminateBtn");
    dom.viewRatesBtn       = document.getElementById("viewRatesBtn") ||
                             document.getElementById("viewRatesButton");
    dom.coinModal          = document.getElementById("coinModal");
    dom.ratesModal         = document.getElementById("ratesModal");
    dom.terminateModal     = document.getElementById("terminateModal");
    dom.mainTimerEl        = document.getElementById("mainTimer");
    dom.creditsEl          = document.getElementById("credits");
    dom.currentDateEl      = document.getElementById("currentDate");
    dom.statusEl           = document.getElementById("connectionStatus");
    dom.coinCountdownEl    = document.getElementById("coinCountdown");
    dom.coinProgressBar    = document.getElementById("coinProgressBar");
    dom.coinTimeEl         = document.getElementById("coinTime");
    dom.coinVoucherTime    = document.getElementById("coinVoucherTime");
    dom.insertedAmountEl   = document.getElementById("insertedAmount");
    dom.coinNoteEl         = document.getElementById("coinNote");
    dom.donePayingBtn      = document.getElementById("donePayingBtn");
    dom.bgMusic            = document.getElementById("bgMusic");
    dom.coinSound          = document.getElementById("coinSound");
    dom.successSound       = document.getElementById("successSound");
    dom.ratesList          = document.querySelector("#ratesModal .rates-list");
    dom.serviceNotice      = document.getElementById("serviceNotice");
    dom.sessionNotice      = document.getElementById("sessionNotice");
    dom.voucherForm        = document.getElementById("voucherForm");
    dom.voucherCode        = document.getElementById("voucherCode");
    dom.voucherSubmitBtn   = document.getElementById("voucherSubmitBtn");
    dom.voucherHelp        = document.getElementById("voucherHelp");
    dom.voucherCard        = document.querySelector(".voucher-card");
    dom.terminateRemaining = document.getElementById("terminateRemaining");
    dom.terminateCredits   = document.getElementById("terminateCredits");
    dom.terminateStatus    = document.getElementById("terminateStatus");
    dom.confirmTerminateBtn = document.getElementById("confirmTerminateBtn");
    dom.cancelTerminateBtn  = document.getElementById("cancelTerminateBtn");
  }

  // ── HTTP helpers ───────────────────────────────────────────────────────────
  var brandingRevision    = 0;
  var brandingEventSource = null;

  // Every PortalSessionManager event that ships a full session payload. Each
  // one lets the portal re-render without an HTTP round trip; polling below
  // stays in place unchanged as the fallback.
  var SESSION_PUSH_EVENTS = [
    "portal.coin.started",
    "portal.coin.credit",
    "portal.coin.window_closed",
    "portal.session.updated",
    "portal.session.connected",
    "portal.session.paused",
    "portal.session.pause_failed",
    "portal.session.resumed",
    "portal.session.activation_failed",
    "portal.session.expired",
    "portal.session.terminated"
  ];

  function defaultBannerSrc() {
    var bannerEl = document.getElementById("portalBanner");
    return bannerEl
      ? (bannerEl.getAttribute("data-default-src") || "/image/Default-Banner.png")
      : "/image/Default-Banner.png";
  }

  function brandingIsVideo(data) {
    if (!data || !data.hasCustomBanner) return false;
    if (data.bannerIsVideo === true || data.banner_is_video === true) return true;
    var mime = String(data.bannerMime || data.banner_mime || "");
    if (mime.indexOf("video/") === 0) return true;
    var url = String(data.bannerUrl || data.banner_url || "");
    return /\.mp4(\?|$)/i.test(url);
  }

  function deactivateBannerMedia(bannerEl, videoEl) {
    if (bannerEl) {
      bannerEl.classList.remove("banner-active");
      bannerEl.removeAttribute("src");
    }
    if (videoEl) {
      videoEl.classList.remove("banner-active");
      videoEl.removeAttribute("src");
      try { videoEl.load(); } catch (e) {}
    }
  }

  function revealPortalHero() {
    var hero = document.getElementById("portalHero");
    if (hero) hero.classList.remove("branding-pending");
  }

  function waitForBannerMedia(el, isVideo, timeoutMs, cb) {
    if (!el) {
      cb(false);
      return;
    }
    var finished = false;
    function done(ok) {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      cb(ok !== false);
    }
    var timer = setTimeout(function () { done(true); }, timeoutMs || 10000);
    if (isVideo) {
      el.oncanplay = function () { done(true); };
      el.onloadeddata = function () { done(true); };
    } else {
      el.onload = function () { done(true); };
      if (el.complete && el.naturalWidth > 0) done(true);
    }
    el.onerror = function () { done(false); };
  }

  function applyBranding(data) {
    if (!data) {
      revealPortalHero();
      return;
    }
    var bannerEl = document.getElementById("portalBanner");
    var videoEl = document.getElementById("portalBannerVideo");
    var fallback = defaultBannerSrc();
    var useCustom = Boolean(data.hasCustomBanner && data.bannerUrl);
    var isVideo = useCustom && brandingIsVideo(data);

    deactivateBannerMedia(bannerEl, videoEl);

    function showImageBanner(src, afterLoad) {
      if (!bannerEl) {
        revealPortalHero();
        return;
      }
      bannerEl.src = src;
      waitForBannerMedia(bannerEl, false, useCustom ? 12000 : 4000, function (ok) {
        if (!ok && useCustom) {
          deactivateBannerMedia(bannerEl, videoEl);
          bannerEl.src = fallback;
          waitForBannerMedia(bannerEl, false, 4000, function () {
            bannerEl.classList.add("banner-active");
            revealPortalHero();
            if (afterLoad) afterLoad();
          });
          return;
        }
        bannerEl.classList.add("banner-active");
        revealPortalHero();
        if (afterLoad) afterLoad();
      });
    }

    function showVideoBanner(src, afterLoad) {
      if (!videoEl) {
        showImageBanner(fallback, afterLoad);
        return;
      }
      videoEl.controls = false;
      videoEl.muted = true;
      videoEl.defaultMuted = true;
      videoEl.loop = true;
      videoEl.autoplay = true;
      videoEl.playsInline = true;
      videoEl.setAttribute("playsinline", "");
      videoEl.setAttribute("webkit-playsinline", "");
      videoEl.setAttribute("controlslist", "nodownload nofullscreen noremoteplayback");
      try { videoEl.disablePictureInPicture = true; } catch (e) {}
      try { videoEl.disableRemotePlayback = true; } catch (e) {}
      videoEl.src = src;
      try { videoEl.load(); } catch (e) {}
      waitForBannerMedia(videoEl, true, 12000, function (ok) {
        if (!ok) {
          showImageBanner(fallback, afterLoad);
          return;
        }
        videoEl.classList.add("banner-active");
        revealPortalHero();
        try { videoEl.play(); } catch (e) {}
        if (afterLoad) afterLoad();
      });
    }

    if (isVideo) {
      showVideoBanner(data.bannerUrl);
    } else if (useCustom) {
      showImageBanner(data.bannerUrl);
    } else {
      showImageBanner(fallback);
    }

    if (dom.bgMusic) {
      var musicSrc = data.musicUrl || "bg_music.mp3";
      var current  = dom.bgMusic.getAttribute("src") || dom.bgMusic.currentSrc || "";
      var musicBase = String(musicSrc).split("?")[0];
      if (current.indexOf(musicBase) === -1) {
        dom.bgMusic.src = musicSrc;
        dom.bgMusic.load();
      }
    }
    brandingRevision = Number(data.revision) || 0;
  }

  function loadBranding() {
    // FastFi/KonekSik: admin Captive Portal uploads → /image/banner.jpg + /audio/*.
    // No custom upload → Default-Banner.png (and local audio fallbacks).
    var fallback = {
      hasCustomBanner: false,
      hasCustomMusic: false,
      bannerUrl: defaultBannerSrc(),
      musicUrl: "bg_music.mp3",
      brandName: "KonekSik-fi"
    };

    if (!window.FastFiCgi || typeof window.FastFiCgi.getPortalMedia !== "function") {
      applyBranding(fallback);
      return Promise.resolve(fallback);
    }

    return cgi().getPortalMedia().then(function (data) {
      if (!data || data.status === "error") {
        applyBranding(fallback);
        return fallback;
      }
      var customBanner = Number(data.has_custom_banner) === 1;
      var mapped = {
        hasCustomBanner: customBanner,
        bannerUrl: data.banner_url || data.default_banner_url || defaultBannerSrc(),
        hasCustomMusic: true,
        musicUrl: data.music_url || data.bg_music_url || "bg_music.mp3",
        coinUrl: data.coin_url || "coin.mp3",
        successUrl: data.success_url || "success.mp3",
        brandName: data.brand_name || data.shop_name || "KonekSik-fi",
        bannerText: data.banner_text || "",
        defaultBannerUrl: data.default_banner_url || defaultBannerSrc()
      };
      applyBranding(mapped);
      // Keep scroll text / title in sync when present
      var scroll = document.getElementById("bannerText") || document.querySelector(".scroll-text");
      if (scroll && mapped.bannerText) scroll.textContent = mapped.bannerText;
      if (dom.coinSound && mapped.coinUrl) {
        try { dom.coinSound.src = mapped.coinUrl; } catch (e) {}
      }
      if (dom.successSound && mapped.successUrl) {
        try { dom.successSound.src = mapped.successUrl; } catch (e) {}
      }
      return mapped;
    }).catch(function () {
      // Probe FastFi static paths directly if CGI unavailable (demo / partial deploy).
      return probeStaticBranding(fallback);
    });
  }

  function probeStaticBranding(fallback) {
    var customUrl = "/image/banner.jpg?t=" + Date.now();
    var defaultUrl = "/image/Default-Banner.png";
    return fetch(customUrl, { method: "HEAD", cache: "no-store" }).then(function (res) {
      if (res.ok) {
        applyBranding({
          hasCustomBanner: true,
          bannerUrl: customUrl,
          hasCustomMusic: true,
          musicUrl: "/audio/insert.mp3",
          brandName: "KonekSik-fi"
        });
        return;
      }
      return fetch(defaultUrl, { method: "HEAD", cache: "no-store" }).then(function (r2) {
        applyBranding({
          hasCustomBanner: false,
          bannerUrl: r2.ok ? defaultUrl : defaultBannerSrc(),
          hasCustomMusic: true,
          musicUrl: "/audio/insert.mp3",
          brandName: "KonekSik-fi"
        });
      });
    }).catch(function () {
      applyBranding(fallback);
    });
  }

  // FastFi baseline has no EventSource /api/events — coin credit is polled via
  // fetchcoin (see startCoinSessionPoll → syncSessionFromServer).
  function connectPortalEvents() {
    /* no-op: FastFi CGI baseline */
  }

  function disconnectPortalEvents() {
    if (!brandingEventSource) return;
    try { brandingEventSource.close(); } catch (e) {}
    brandingEventSource = null;
  }

  // Firmware emits portal.session.expired once on Expiring (canInsertCoin=false)
  // and again after recycle → idle. Standby must not drop SSE between those two.
  var postExpireSettleUntil = 0;
  var expireSettleTimer = null;

  function sessionAwaitingPaymentUi() {
    var st = state.sessionState || "";
    return st === "idle" || st === "waiting_coin" || st === "";
  }

  function awaitingExpireSettle() {
    if (state.sessionState === "expiring" || state.sessionState === "expired") {
      return true;
    }
    return postExpireSettleUntil > Date.now();
  }

  function clearExpireSettle() {
    postExpireSettleUntil = 0;
    if (expireSettleTimer) {
      clearInterval(expireSettleTimer);
      expireSettleTimer = null;
    }
  }

  function beginExpireSettle(reason) {
    var alreadySettling = expireSettleTimer !== null;
    postExpireSettleUntil = Date.now() + EXPIRE_SETTLE_MS;
    if (!alreadySettling) {
      expireSettleTimer = setInterval(function () {
        if (sessionAwaitingPaymentUi() || !awaitingExpireSettle()) {
          clearExpireSettle();
          updateIdleSyncPolicy();
          return;
        }
        syncSessionFromServer()
          .catch(function () {})
          .finally(function () { updateIdleSyncPolicy(); });
      }, EXPIRE_SETTLE_POLL_MS);
      updateIdleSyncPolicy();
      syncSessionFromServer()
        .catch(function () {})
        .finally(function () { updateIdleSyncPolicy(); });
    } else {
      updateIdleSyncPolicy();
    }
    void reason;
  }

  function needsPortalLiveChannel() {
    if (document.hidden) return false;
    if (state.coinSessionActive || coinModalVisible) return true;
    if (awaitingExpireSettle()) return true;
    if (state.connected && displaySeconds() > 0 && !state.paused) return true;
    return false;
  }

  function needsActiveSessionSync() {
    if (document.hidden) return false;
    if (state.coinSessionActive || coinModalVisible) return false; // coin poll owns this
    // Expire settle uses its own burst poll — do not also run the 60s loop.
    if (awaitingExpireSettle()) return false;
    // Active internet grant — rare sync to re-anchor local countdown.
    if (state.connected && displaySeconds() > 0 && !state.paused) return true;
    // Activating — keep short-lived sync until settled (waitForActivation also polls).
    if (state.sessionState === "activating") return true;
    return false;
  }

  // Standby when idle: no heartbeat, no SSE. Wake on coin / active session only.
  // Exception: keep the live channel through Expiring → idle so INSERT COIN returns.
  function updateIdleSyncPolicy() {
    if (needsPortalLiveChannel()) {
      connectPortalEvents();
    } else {
      disconnectPortalEvents();
    }
    if (needsActiveSessionSync()) {
      startActiveSessionSync();
    } else {
      stopActiveSessionSync();
    }
  }

  // A pushed payload is only applied when it belongs to this device — the
  // stream is shared by every connected customer.
  function handleSessionPush(event, isCoinCredit) {
    var payload;
    try {
      payload = JSON.parse(event && event.data ? event.data : "null");
    } catch (err) {
      payload = null;
    }
    if (!payload) return;

    var mine = String(payload.macAddress || payload.mac || "").toLowerCase();
    var self = String(getDeviceMAC() || "").toLowerCase();
    if (!self || !mine || mine !== self) return;

    var session = normalizeSession(payload);
    if (!session) return;
    noteApplianceSuccess();
    applyNormalizedSession(session, isCoinCredit);
    if (isCoinCredit) {
      renderCoinModal();
    } else {
      render();
    }
  }

  // ── Portal API (FastFi /cgi-bin/api — exact bootstrap actions) ─────────────
  function fetchSession() {
    var gen = ++sessionSyncGen;
    ensureDeviceIds();
    var mac = getDeviceMAC();

    var coinPoll = Promise.resolve(null);
    if (ff.coinWindow && ff.slotMac) {
      coinPoll = cgi().fetchCoin(ff.slotMac).then(function (data) {
        var coin = parseInt(data && data.coin, 10) || 0;
        if (coin < ff.lastCoin) coin = ff.lastCoin;
        if (coin > ff.lastCoin) {
          ff.currentCoin = coin;
          ff.lastCoin = coin;
          computeTotalsFromCoin(ff.currentCoin);
        } else {
          ff.currentCoin = coin;
        }
        return data;
      }).catch(function () { return null; });
    }

    return coinPoll.then(function () {
      var visitor = ff.deviceId;
      return Promise.all([
        cgi().checkDevice(visitor, mac, ff.deviceId).catch(function () { return {}; }),
        cgi().sessionStatus(mac, ff.deviceId).catch(function () { return {}; })
      ]).then(function (pair) {
        var device = pair[0] || {};
        var status = pair[1] || {};
        if (device.mac || device.ip) setDomIdentity(device.mac || mac, device.ip || getDeviceIP());
        var raw = sessionFromFastFi(device, status);
        return { gen: gen, session: normalizeSession(raw) };
      });
    });
  }

  function applyFetchedSession(result, trustFully) {
    if (!result || !result.session) return null;
    if (result.gen !== sessionSyncGen) return null;
    applyNormalizedSession(result.session, trustFully);
    return result.session;
  }

  function syncSessionFromServer() {
    return fetchSession().then(function (result) {
      noteApplianceSuccess();
      return applyFetchedSession(result, false);
    }, function (err) {
      noteApplianceFailure();
      throw err;
    });
  }

  function startCoinSessionAPI() {
    ensureDeviceIds();
    var mac = getDeviceMAC();
    if (!mac) return Promise.reject(apiFail("Device MAC unavailable", "MISSING_MAC"));

    return loadRatesCache()
      .catch(function () { return ff.ratesList; })
      .then(function () { return cgi().listEspDevices(); })
      .then(function (payload) {
        var slot = pickEspSlot(payload);
        if (!slot) throw apiFail("No coin slot available", "COIN_DISABLED");
        ff.slotMac = slot;
        return cgi().lockCoin(slot, mac);
      })
      .then(function (data) {
        if (data && data.status && data.status !== "ok" && data.status !== "success") {
          throw apiFail(data.message || "Coin slot busy", "SESSION_ERROR");
        }
        if (data && data.blocked) {
          throw apiFail(data.message || "Rate limited", "SESSION_ERROR");
        }
        ff.coinWindow = true;
        ff.coinStartedAt = Date.now();
        ff.currentCoin = 0;
        ff.lastCoin = 0;
        ff.totalSeconds = 0;
        sessionSyncGen += 1;
        return normalizeSession(sessionFromFastFi({}, {}));
      });
  }

  function donePayingAPI() {
    ensureDeviceIds();
    var mac = getDeviceMAC();
    var slot = ff.slotMac;
    if (ff.currentCoin <= 0) {
      var unlockEmpty = slot ? cgi().unlockCoin(slot) : Promise.resolve();
      return unlockEmpty.then(function () {
        ff.coinWindow = false;
        ff.slotMac = "";
        throw apiFail("No coins inserted", "NO_CREDITS");
      });
    }
    computeTotalsFromCoin(ff.currentCoin);
    return cgi().updateDevice({
      time: ff.totalSeconds,
      mac: mac,
      coin: ff.currentCoin,
      download: ff.totalDownload,
      upload: ff.totalUpload,
      paused: ff.totalPausedLimit,
      data_limit_mb: ff.totalDataLimit,
      validity_minutes: ff.totalValidityMinutes,
      device_id: ff.deviceId,
      client_id: ff.clientId,
      slot_mac: slot
    }).then(function (data) {
      if (data && data.status === "error") {
        throw apiFail(data.message || "Activation failed", "SESSION_ERROR");
      }
      // Match bootstrap Done path: unlockcoin (+ clearcredit after success).
      var unlock = slot ? cgi().unlockCoin(slot) : Promise.resolve();
      return unlock
        .then(function () { return cgi().clearCredit().catch(function () { return null; }); })
        .then(function () {
          ff.coinWindow = false;
          ff.slotMac = "";
          ff.lastCoin = 0;
          ff.currentCoin = 0;
          return fetchSession().then(function (result) {
            return result && result.session;
          });
        });
    });
  }

  function pauseSessionAPI() {
    ensureDeviceIds();
    return cgi().internet(0, ff.deviceId, getDeviceMAC()).then(function (data) {
      if (data && data.status === "error") {
        throw apiFail(data.message || "Pause failed", "SESSION_ERROR");
      }
      return fetchSession().then(function (r) { return r && r.session; });
    });
  }

  function resumeSessionAPI() {
    ensureDeviceIds();
    return cgi().internet(1, ff.deviceId, getDeviceMAC()).then(function (data) {
      if (data && data.status === "error") {
        throw apiFail(data.message || "Resume failed", "SESSION_ERROR");
      }
      return fetchSession().then(function (r) { return r && r.session; });
    });
  }

  function cancelCoinModalAPI() {
    var slot = ff.slotMac;
    return cgi().clearCredit().catch(function () { return null; }).then(function () {
      return slot ? cgi().unlockCoin(slot).catch(function () { return null; }) : null;
    }).then(function () {
      ff.coinWindow = false;
      ff.slotMac = "";
      ff.currentCoin = 0;
      ff.lastCoin = 0;
      ff.totalSeconds = 0;
      return fetchSession().then(function (r) { return r && r.session; });
    });
  }

  function heartbeatAPI() {
    ensureDeviceIds();
    return cgi().checkDevice(ff.deviceId, getDeviceMAC(), ff.deviceId);
  }

  function fetchRatesAPI() {
    return loadRatesCache().then(function () {
      return normalizeRatesPayload({
        data: ff.ratesList.map(function (r) {
          return {
            price: r.price,
            minutes: r.minutes || Math.floor((r.time || 0) / 60),
            download_mb: r.download_mb,
            upload_mb: r.upload_mb,
            pause_limit: r.paused_limit,
            validity_minutes: r.validity_minutes,
            data_mb: r.data_limit_mb
          };
        })
      });
    });
  }

  function redeemVoucherAPI(code) {
    ensureDeviceIds();
    var trimmed = String(code || "").trim().toUpperCase();
    return cgi().voucher(trimmed, getDeviceMAC(), ff.deviceId).then(function (data) {
      if (data && (data.status === "error" || data.success === false)) {
        throw apiFail(data.message || data.error || "Invalid voucher", "VOUCHER_INVALID");
      }
      return fetchSession().then(function (r) { return r && r.session; });
    });
  }

  function reconnectVoucherAPI() {
    return fetchSession().then(function (r) { return r && r.session; });
  }

  function terminateSessionAPI() {
    ensureDeviceIds();
    var mac = getDeviceMAC();
    if (!mac) return Promise.reject(apiFail("Device MAC unavailable", "MISSING_MAC"));
    return cgi().terminate(mac, ff.deviceId).then(function (data) {
      if (!data || data.status === "error") {
        throw apiFail((data && data.message) || "Terminate failed", (data && data.code) || "SESSION_ERROR");
      }
      ff.coinWindow = false;
      ff.slotMac = "";
      ff.currentCoin = 0;
      ff.lastCoin = 0;
      ff.totalSeconds = 0;
      sessionSyncGen += 1;
      return normalizeSession({
        secondsLeft: 0,
        timerRunning: false,
        credits: 0,
        paused: false,
        connected: false,
        coinSessionActive: false,
        coinCountdown: INSERT_TIMEOUT,
        insertedAmount: 0,
        purchasedMinutes: 0,
        sessionState: "idle",
        pausesUsed: 0,
        pauseLimit: ff.pauseLimit || 0,
        source: "portal",
        canTerminate: false,
        serverNowMs: Date.now()
      });
    });
  }

  // ── audio ──────────────────────────────────────────────────────────────────
  function playMusic() {
    if (!dom.bgMusic) return;
    dom.bgMusic.currentTime = 0;
    dom.bgMusic.play().catch(function () {
      document.addEventListener("click", function tryPlay() {
        dom.bgMusic.play().catch(function () {});
        document.removeEventListener("click", tryPlay);
      }, { once: true });
    });
  }

  function stopMusic() {
    if (!dom.bgMusic) return;
    dom.bgMusic.pause();
    dom.bgMusic.currentTime = 0;
  }

  function playCoinSound() {
    if (!dom.coinSound) return;
    dom.coinSound.currentTime = 0;
    dom.coinSound.play().catch(function () {});
  }

  function playSuccessSound() {
    if (!dom.successSound) return;
    dom.successSound.currentTime = 0;
    dom.successSound.play().catch(function () {});
  }

  // ── modal helpers ──────────────────────────────────────────────────────────
  function openModal(modal) {
    if (!modal) return;
    modal.hidden = false;
    document.body.style.overflow = "hidden";
  }

  function closeModal(modal, skipApiCancel) {
    if (!modal) return;
    // Don't let a backdrop tap or Escape dismiss the dialog mid-request; the
    // customer must see whether their session actually ended.
    if (modal === dom.terminateModal && terminateInFlight) return;
    modal.hidden = true;
    if (!document.querySelector(".modal:not([hidden])")) {
      document.body.style.overflow = "";
    }
    if (modal === dom.coinModal) {
      coinModalVisible = false;
      stopCoinSessionUI();
      if (!skipApiCancel && !coinCancelInFlight && !donePayingInFlight) {
        requestCancelCoinModal();
      }
    }
  }

  function requestCancelCoinModal() {
    if (coinCancelInFlight) return;
    coinCancelInFlight = true;
    cancelCoinModalAPI()
      .catch(function () {})
      .finally(function () { coinCancelInFlight = false; });
  }

  function handleCoinTimeout() {
    if (coinTimeoutHandled || !state.coinSessionActive) return;
    coinTimeoutHandled = true;
    stopCoinSessionUI();
    closeModal(dom.coinModal, true);
    requestCancelCoinModal();
  }

  function startCoinSessionPoll() {
    clearInterval(coinPollTimer);
    coinPollTimer = setInterval(function () {
      syncSessionFromServer().catch(function () {});
    }, COIN_POLL_MS);
    syncSessionFromServer().catch(function () {});
  }

  function stopCoinSessionPoll() {
    clearInterval(coinPollTimer);
    coinPollTimer = null;
  }

  function startCoinSessionUI(serverCountdown, isRestore) {
    if (coinModalVisible) {
      state.coinCountdown = Number(serverCountdown) || state.coinCountdown || INSERT_TIMEOUT;
      anchorCoinWindow(state.coinCountdown);
      renderCoinModal();
      updateIdleSyncPolicy();
      return;
    }

    state.coinSessionActive  = true;
    state.coinCountdown      = Number(serverCountdown) || INSERT_TIMEOUT;
    coinTimeoutHandled       = false;

    if (isRestore) {
      state.coinAmount = Number(state.insertedAmount) || state.coinAmount || 0;
      state.coinBaseCredits = Math.max(0, state.credits - state.coinAmount);
      lastWindowInserted = state.coinAmount;
    } else {
      state.coinBaseCredits    = state.credits;
      state.coinAmount         = Number(state.insertedAmount) || 0;
      state.coinMinutes        = 0;
      state.coinVoucherMinutes = 0;
      state.coinPulseCount     = 0;
      lastWindowInserted       = state.coinAmount;
    }

    coinModalVisible = true;
    anchorCoinWindow(state.coinCountdown);
    openModal(dom.coinModal);
    playMusic();
    renderCoinModal();
    startCoinSessionPoll();
    updateIdleSyncPolicy();

    // Repaint only — the window deadline is the ESP32's coinWindowRemaining,
    // re-anchored on every payload, so the modal cannot outlive the firmware
    // window or close early.
    clearInterval(coinTimer);
    coinTimer = setInterval(function () {
      if (!state.coinSessionActive) return;
      if (derivedCoinSeconds() <= 0) {
        handleCoinTimeout();
        return;
      }
      renderCoinModal();
    }, 1000);
  }

  function restoreCoinSessionUI() {
    if (!state.coinSessionActive || coinModalVisible) return;
    startCoinSessionUI(state.coinCountdown, true);
  }

  function stopCoinSessionUI() {
    clearInterval(coinTimer);
    coinTimer = null;
    stopCoinSessionPoll();
    state.coinSessionActive  = false;
    state.coinCountdown      = INSERT_TIMEOUT;
    state.coinAmount         = 0;
    state.coinMinutes        = 0;
    state.coinVoucherMinutes = 0;
    state.coinPulseCount     = 0;
    state.coinBaseCredits    = 0;
    lastWindowInserted       = 0;
    stopMusic();
    saveStateCache();
    updateIdleSyncPolicy();
  }

  function showPortalError(message) {
    if (dom.statusEl) {
      dom.statusEl.textContent = message;
      dom.statusEl.classList.add("disconnected");
    }
  }

  function showSessionNotice(message) {
    if (!dom.sessionNotice) return;
    dom.sessionNotice.textContent = message;
    dom.sessionNotice.hidden = false;
    sessionNoticeTicks = 5;
  }

  function hideSessionNotice() {
    sessionNoticeTicks = 0;
    if (!dom.sessionNotice) return;
    dom.sessionNotice.hidden = true;
    dom.sessionNotice.textContent = "";
  }

  function updateSessionNotice(previousSeconds, currentSeconds) {
    if (state.sessionState !== "active" || !state.connected || state.paused) {
      hideSessionNotice();
      return;
    }
    if (!warnedAt15Seconds && currentSeconds > 0 && currentSeconds <= 15 &&
        (previousSeconds > 15 || currentSeconds === 15)) {
      warnedAt15Seconds = true;
      showSessionNotice(
        "15 seconds remaining. Your Internet connection will end soon."
      );
    } else if (!warnedAt30Seconds && currentSeconds > 15 &&
               currentSeconds <= 30 &&
               (previousSeconds > 30 || currentSeconds === 30)) {
      warnedAt30Seconds = true;
      showSessionNotice(
        "30 seconds remaining. Insert more coins to continue your session."
      );
    }
    if (currentSeconds <= 0) hideSessionNotice();
  }

  // ── appliance reachability notice ──────────────────────────────────────────
  // Purely a visibility layer over the existing background request failures
  // (heartbeat / session sync / initial load). Never touches cached credits
  // or session state, never calls MikroTik login, and clears itself as soon
  // as the appliance answers again — safe to leave running indefinitely.
  var applianceFailureCount = 0;

  function showServiceNotice() {
    if (dom.serviceNotice) dom.serviceNotice.hidden = false;
  }

  function hideServiceNotice() {
    if (dom.serviceNotice) dom.serviceNotice.hidden = true;
  }

  function noteApplianceFailure() {
    applianceFailureCount += 1;
    if (applianceFailureCount >= SERVICE_UNAVAILABLE_THRESHOLD) {
      showServiceNotice();
    }
  }

  function noteApplianceSuccess() {
    applianceFailureCount = 0;
    hideServiceNotice();
  }

  // ── button handlers ────────────────────────────────────────────────────────
  function handleInsertCoin() {
    if (!getDeviceMAC()) { showPortalError("Device MAC unavailable"); return; }
    if (dom.insertCoinBtn && dom.insertCoinBtn.disabled) return;
    if (dom.insertCoinBtn) dom.insertCoinBtn.disabled = true;

    startCoinSessionAPI()
      .then(function (session) {
        noteApplianceSuccess();
        if (!session) throw new Error("Invalid session response");
        applyNormalizedSession(session, true);
        startCoinSessionUI(session.coinCountdown, false);
      })
      .catch(function (err) {
        var code = (err && err.code) || "";
        var msg = (err && err.message) ? err.message : "Could not start a coin session.";
        // Appliance answered with a business error — do not treat as outage.
        if (code === "COIN_DISABLED" || code === "SESSION_ERROR" ||
            code === "MISSING_MAC" || code === "INVALID_SESSION" ||
            code === "VOUCHER_SESSION") {
          noteApplianceSuccess();
        } else {
          noteApplianceFailure();
          showServiceNotice();
        }
        if (code && msg.indexOf(code) === -1) {
          msg = msg + " (" + code + ")";
        }
        showPortalError(msg);
        showSessionNotice(msg);
      })
      .finally(function () {
        if (dom.insertCoinBtn) dom.insertCoinBtn.disabled = false;
      });
  }

  // State-driven wait. Firmware activating must never become a browser
  // timeout failure. Only activation_error is a terminal failure.
  function waitForActivation() {
    var lastHttpAt = 0;
    var HTTP_FALLBACK_MS = 2000;
    var LOCAL_TICK_MS = 250;
    var connectingNoticeAt = 0;

    function settled() {
      if (state.sessionState === "active" && state.connected) {
        return { done: true };
      }
      if (state.sessionState === "activation_error") {
        throw new Error(state.activationErrorReason ||
          "Activation failed — purchased time preserved");
      }
      return null;
    }

    function poll() {
      if (settled()) {
        if (window.console) {
          console.log("[activate-latency] T12_connected t=" + Date.now());
        }
        return Promise.resolve();
      }
      if (state.sessionState === "activating" ||
          (state.secondsLeft > 0 && !state.connected &&
           state.sessionState !== "activation_error")) {
        if (Date.now() - connectingNoticeAt >= 15000) {
          connectingNoticeAt = Date.now();
          if (dom.statusEl) {
            dom.statusEl.textContent = "Still connecting to the router…";
            dom.statusEl.classList.remove("disconnected");
          }
        }
      }
      var now = Date.now();
      var needHttp = lastHttpAt === 0 || (now - lastHttpAt) >= HTTP_FALLBACK_MS;
      function tick() {
        return new Promise(function (resolve) {
          setTimeout(resolve, LOCAL_TICK_MS);
        }).then(poll);
      }
      if (!needHttp) return tick();
      lastHttpAt = now;
      return fetchSession().then(function (result) {
        applyFetchedSession(result, false);
        if (settled()) {
          if (window.console) {
            console.log("[activate-latency] T12_connected t=" + Date.now());
          }
          return;
        }
        return tick();
      });
    }
    if (window.console) {
      console.log("[activate-latency] T11_wait_start t=" + Date.now());
    }
    return poll();
  }

  function handleDonePaying() {
    if (donePayingInFlight) return;
    donePayingInFlight = true;
    var activationErrorMessage = "";

    stopCoinSessionUI();
    closeModal(dom.coinModal, true);
    if (dom.statusEl) {
      dom.statusEl.textContent = "Activating…";
      dom.statusEl.classList.remove("disconnected");
    }

    donePayingAPI()
      .then(function (session) {
        noteApplianceSuccess();
        sessionSyncGen += 1;
        if (session) applyNormalizedSession(session, true);
        var st = (session && session.sessionState) || "";
        if (st === "activating" || (session && session.secondsLeft > 0 && !session.connected)) {
          return waitForActivation();
        }
      })
      .then(function () {
        if (state.sessionState === "active" && state.connected &&
            state.secondsLeft > 0) {
          playSuccessSound();
        }
        startMainTimer();
        renderStatus();
        renderInsertBtn();
        renderTerminateBtn();
      })
      .catch(function (err) {
        activationErrorMessage =
          err && err.message ? err.message : "Activation failed";
        var code = (err && err.code) || "";
        if (code === "ACTIVATION_QUEUE_FULL" || code === "NO_CREDITS" ||
            code === "NO_MINUTES" || code === "VOUCHER_SESSION") {
          noteApplianceSuccess();
        } else if (state.sessionState === "activation_error") {
          noteApplianceSuccess();
        } else if (state.sessionState === "activating") {
          noteApplianceSuccess();
          activationErrorMessage = "";
        } else {
          noteApplianceFailure();
          showServiceNotice();
        }
        return syncSessionFromServer().catch(function () {});
      })
      .finally(function () {
        donePayingInFlight = false;
        render();
        if (activationErrorMessage &&
            state.sessionState === "activation_error") {
          showPortalError(activationErrorMessage);
        }
      });
  }

  function handleTogglePause() {
    if (!dom.pauseButton || dom.pauseButton.disabled) return;
    dom.pauseButton.disabled = true;

    // canResume covers paused sessions and activation_error retry (firmware
    // resume() re-queues hotspot authorization without consuming credits).
    var resuming = state.canResume && !state.canPause;
    var apiCall = resuming ? resumeSessionAPI : pauseSessionAPI;
    if (resuming && state.sessionState === "activation_error" && dom.statusEl) {
      dom.statusEl.textContent = "Activating…";
      dom.statusEl.classList.remove("disconnected");
    }
    apiCall()
      .then(function (session) {
        noteApplianceSuccess();
        if (session) applyNormalizedSession(session, false);
        // Pause/resume authorization happens on the router worker; re-read the
        // session so the button and countdown reflect the settled state rather
        // than an optimistic guess.
        return syncSessionFromServer();
      })
      .then(function () {
        if (resuming &&
            (state.sessionState === "activating" ||
             (state.secondsLeft > 0 && !state.connected))) {
          return waitForActivation();
        }
      })
      .then(function () {
        if (resuming && state.secondsLeft > 0 && state.connected) {
          playSuccessSound();
          startMainTimer();
        }
      })
      .catch(function (err) {
        var code = (err && err.code) || "";
        if (code === "PAUSE_LIMIT_REACHED") {
          // A refused pause is a rule, not an outage — don't scare the customer
          // with the service-unavailable banner.
          showSessionNotice(
            "You have used all " + (state.pauseLimit || 3) +
            " pauses for this session."
          );
          return syncSessionFromServer().catch(function () {});
        }
        noteApplianceFailure();
        var msg = err && err.message ? err.message : "";
        if (resuming && msg) {
          showPortalError(msg);
        } else {
          showSessionNotice(resuming
            ? "Could not resume yet. Retrying automatically…"
            : "Could not pause right now. Please try again.");
        }
        return syncSessionFromServer().catch(function () {});
      })
      .finally(function () {
        if (dom.pauseButton) dom.pauseButton.disabled = false;
        render();
      });
  }

  function handleViewRates() {
    fetchRatesAPI()
      .then(function (viewModel) {
        renderRatesModal(viewModel);
        openModal(dom.ratesModal);
      })
      .catch(function (err) {
        if (dom.ratesList) {
          var msg = (err && err.message) ? err.message : "Unable to load rates from appliance";
          dom.ratesList.innerHTML =
            '<p class="rates-loading">' + escapeHtml(msg) + '</p>';
        }
        openModal(dom.ratesModal);
      });
  }

  // ── terminate session ──────────────────────────────────────────────────────
  var terminateInFlight = false;

  function setTerminateStatus(message, isError) {
    if (!dom.terminateStatus) return;
    dom.terminateStatus.textContent = message || "";
    dom.terminateStatus.hidden = !message;
    dom.terminateStatus.classList.toggle("error", Boolean(isError));
  }

  function setTerminateBusy(busy) {
    if (dom.confirmTerminateBtn) {
      dom.confirmTerminateBtn.disabled = busy;
      dom.confirmTerminateBtn.textContent = busy ? "Terminating…" : "Terminate now";
    }
    if (dom.cancelTerminateBtn) dom.cancelTerminateBtn.disabled = busy;
  }

  function openTerminateModal() {
    if (!state.canTerminate) return;
    setTerminateStatus("", false);
    setTerminateBusy(false);
    renderTerminateModal();
    openModal(dom.terminateModal);
  }

  // Shows exactly what the customer forfeits, so the confirmation is informed
  // rather than a bare yes/no.
  function renderTerminateModal() {
    if (dom.terminateRemaining) {
      dom.terminateRemaining.textContent = formatTime(displaySeconds());
    }
    if (dom.terminateCredits) {
      dom.terminateCredits.textContent = "\u20B1" + (state.credits || 0).toFixed(2);
    }
  }

  function handleTerminateConfirm() {
    if (terminateInFlight) return;
    terminateInFlight = true;
    setTerminateBusy(true);
    setTerminateStatus("Ending your session…", false);

    terminateSessionAPI()
      .then(function (session) {
        noteApplianceSuccess();
        // The firmware reply is the post-terminate session; apply it verbatim
        // instead of guessing a cleared state locally.
        if (session) applyNormalizedSession(session, true);
        // Release the dismissal guard before closing — it exists to block the
        // customer's taps during the request, not this success path.
        terminateInFlight = false;
        closeModal(dom.terminateModal, true);
        setTerminateStatus("", false);
        render();
        // Confirm the router-side deauthorize landed rather than trusting the
        // acknowledgement alone.
        return syncSessionFromServer().catch(function () {});
      })
      .catch(function (err) {
        noteApplianceFailure();
        setTerminateStatus(
          (err && err.message)
            ? err.message + " — your session was not changed."
            : "Could not end the session. Please try again.",
          true
        );
      })
      .finally(function () {
        terminateInFlight = false;
        setTerminateBusy(false);
      });
  }

  function setVoucherBusy(busy, message, isError) {
    if (dom.voucherSubmitBtn) dom.voucherSubmitBtn.disabled = Boolean(busy);
    if (dom.voucherCode) dom.voucherCode.disabled = Boolean(busy);
    if (dom.voucherCard) dom.voucherCard.classList.toggle("is-busy", Boolean(busy));
    if (dom.voucherHelp) {
      dom.voucherHelp.textContent =
        message || (busy ? "Validating voucher…" : "Voucher is case-insensitive");
      dom.voucherHelp.classList.toggle("error", Boolean(isError));
      dom.voucherHelp.classList.toggle("success", Boolean(message) && !isError);
    }
  }

  function handleVoucherSubmit(event) {
    event.preventDefault();
    if (!dom.voucherCode || !dom.voucherSubmitBtn ||
        dom.voucherSubmitBtn.disabled) return;
    var code = String(dom.voucherCode.value || "").trim().toUpperCase();
    if (!code) {
      setVoucherBusy(false, "Enter a voucher code.", true);
      return;
    }

    setVoucherBusy(true, "Validating voucher…", false);
    redeemVoucherAPI(code)
      .then(function (session) {
        if (session) applyNormalizedSession(session, true);
        setVoucherBusy(true, "Voucher accepted. Activating Internet…", false);
        return waitForActivation();
      })
      .then(function () {
        noteApplianceSuccess();
        playSuccessSound();
        setVoucherBusy(false, "Voucher active on this device.", false);
      })
      .catch(function (err) {
        var code = (err && err.code) || "";
        // Known voucher/API reasons are not "appliance dead" — avoid the
        // generic Payment service banner for CLOCK_NOT_READY / not-found.
        if (code !== "CLOCK_NOT_READY" && code !== "VOUCHER_NOT_FOUND" &&
            code !== "VOUCHER_BOUND_TO_ANOTHER_DEVICE" &&
            code !== "VOUCHER_EXPIRED" && code !== "VOUCHER_UNAVAILABLE" &&
            code !== "COIN_SESSION_ACTIVE") {
          noteApplianceFailure();
        }
        setVoucherBusy(false, err && err.message ? err.message :
          "Voucher activation failed.", true);
      });
  }

  function maybeReconnectVoucher(session) {
    if (!session || session.source !== "voucher" || !session.canReconnect ||
        session.sessionState === "expired" || session.voucherStatus === "expired" ||
        session.sessionState === "expiring") {
      return Promise.resolve(session);
    }
    setVoucherBusy(true, "Restoring voucher Internet access…", false);
    return reconnectVoucherAPI()
      .then(function (updated) {
        if (updated) applyNormalizedSession(updated, true);
        return waitForActivation();
      })
      .then(function (active) {
        setVoucherBusy(false, "Voucher active on this device.", false);
        return active;
      })
      .catch(function (err) {
        setVoucherBusy(false, err && err.message ? err.message :
          "Unable to restore voucher access.", true);
        return session;
      });
  }

  // ── event bindings ─────────────────────────────────────────────────────────
  function bindEvents() {
    if (dom.insertCoinBtn) dom.insertCoinBtn.addEventListener("click", handleInsertCoin);
    if (dom.pauseButton)   dom.pauseButton.addEventListener("click", handleTogglePause);
    if (dom.viewRatesBtn)  dom.viewRatesBtn.addEventListener("click", handleViewRates);
    if (dom.donePayingBtn) dom.donePayingBtn.addEventListener("click", handleDonePaying);
    if (dom.voucherForm) dom.voucherForm.addEventListener("submit", handleVoucherSubmit);

    if (dom.terminateBtn) {
      dom.terminateBtn.addEventListener("click", openTerminateModal);
    }
    if (dom.confirmTerminateBtn) {
      dom.confirmTerminateBtn.addEventListener("click", handleTerminateConfirm);
    }
    if (dom.cancelTerminateBtn) {
      dom.cancelTerminateBtn.addEventListener("click", function () {
        closeModal(dom.terminateModal, true);
      });
    }

    document.addEventListener("click", function (e) {
      if (e.target.closest("[data-close-modal]")) {
        closeModal(e.target.closest(".modal"));
      } else if (e.target.classList && e.target.classList.contains("modal")) {
        closeModal(e.target);
      }
    });

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        document.querySelectorAll(".modal").forEach(function (m) { closeModal(m); });
      }
    });
  }

  // Repaint loop only. It owns no value: every tick re-reads the deadline the
  // firmware established, so the display can never disagree with the ESP32 by
  // more than the transport delay of the last payload.
  var lastPaintedSeconds = null;

  function startMainTimer() {
    clearInterval(mainTimer);
    mainTimer = setInterval(function () {
      if (sessionNoticeTicks > 0) {
        sessionNoticeTicks -= 1;
        if (sessionNoticeTicks === 0) hideSessionNotice();
      }
      var shown = displaySeconds();
      if (lastPaintedSeconds !== null && shown !== lastPaintedSeconds) {
        updateSessionNotice(lastPaintedSeconds, shown);
      }
      // Local grant ended before/without the Expiring SSE — keep live until
      // firmware recycles to idle so INSERT COIN reappears without a reload.
      if (lastPaintedSeconds !== null && lastPaintedSeconds > 0 && shown <= 0 &&
          state.source !== "voucher" && !state.paused &&
          (state.sessionState === "active" || state.sessionState === "activating" ||
           state.sessionState === "expiring" || state.connected)) {
        beginExpireSettle("local-timer-zero");
      }
      lastPaintedSeconds = shown;
      renderStatus();
      renderMainTimer();
      renderInsertBtn();
      renderCoinModal();
      if (dom.terminateModal && !dom.terminateModal.hidden) renderTerminateModal();
    }, 1000);
  }

  function activeSessionSyncTick() {
    heartbeatAPI()
      .then(function () {
        return syncSessionFromServer().catch(function () {});
      })
      .catch(function () { noteApplianceFailure(); })
      .finally(function () {
        updateIdleSyncPolicy();
      });
  }

  function startActiveSessionSync() {
    if (heartbeatTimer) return;
    heartbeatTimer = setInterval(activeSessionSyncTick, ACTIVE_SYNC_MS);
  }

  function stopActiveSessionSync() {
    clearInterval(heartbeatTimer);
    heartbeatTimer = null;
  }

  // ── render ─────────────────────────────────────────────────────────────────
  function render() {
    renderStatus();
    renderCredits();
    renderMainTimer();
    renderInsertBtn();
    renderPause();
    renderTerminateBtn();
    renderVoucherControls();
    renderCoinModal();
    if (dom.terminateModal && !dom.terminateModal.hidden) renderTerminateModal();
    renderDate();
  }

  function renderStatus() {
    if (!dom.statusEl) return;
    var st = state.sessionState || "";
    var label = "Disconnected";
    var disconnected = true;
    if (!sessionHydrated && state.secondsLeft > 0) {
      label = "Connecting…";
      disconnected = false;
    } else if (st === "activating") {
      label = "Activating…";
      disconnected = false;
    } else if (st === "waiting_coin") {
      label = "Waiting for Payment";
    } else if (st === "activation_error") {
      // Exact firmware reason is the status of record — never hide it behind a
      // generic "Activation failed" label (title-only was invisible on mobile).
      label = state.activationErrorReason
        ? state.activationErrorReason
        : "Activation failed — purchased time preserved";
    } else if (st === "expiring" || st === "expired") {
      label = "Disconnecting…";
    } else if (st === "paused" || state.paused) {
      label = "Paused";
      disconnected = true;
    } else if (state.connected && displaySeconds() > 0 && st === "active") {
      label = "Connected";
      disconnected = false;
    } else if (st === "idle" || st === "waiting_coin" || displaySeconds() <= 0) {
      label = "Disconnected";
      disconnected = true;
    }
    dom.statusEl.textContent = label;
    dom.statusEl.classList.toggle("disconnected", disconnected);
    dom.statusEl.title = st === "activation_error" && state.activationErrorReason
      ? state.activationErrorReason
      : "";
  }

  function renderMainTimer() {
    if (dom.mainTimerEl) dom.mainTimerEl.textContent = formatTime(displaySeconds());
  }

  function renderCredits() {
    if (dom.creditsEl) {
      dom.creditsEl.textContent = "\u20B1" + (state.credits || 0).toFixed(2);
    }
  }

  // Issue 4: rename INSERT COIN → ADD ADDITIONAL TIME when session is active
  function renderInsertBtn() {
    var liveLeft = displaySeconds();
    var hasPaidTime = liveLeft > 0 ||
      (state.secondsLeft > 0 &&
       (state.sessionState === "active" || state.sessionState === "paused" ||
        state.sessionState === "activating" ||
        state.sessionState === "activation_error"));
    // During Expiring, firmware sets canInsertCoin=false for cleanup. Keep the
    // button visible (disabled) so the action row never goes blank; enable again
    // as soon as idle / waiting_payment recycles.
    var showInsert = state.source === "voucher"
      ? false
      : (state.canInsertCoin ||
         state.sessionState === "expiring" ||
         state.sessionState === "expired" ||
         (!hasPaidTime && sessionHydrated));
    if (dom.insertCoinBtn) {
      dom.insertCoinBtn.hidden = !showInsert;
      var cleanupHold = !state.canInsertCoin &&
        (state.sessionState === "expiring" || state.sessionState === "expired");
      if (cleanupHold) {
        dom.insertCoinBtn.disabled = true;
      } else if (!state.coinSessionActive) {
        // Re-enable after settle; handleInsertCoin also toggles during requests.
        dom.insertCoinBtn.disabled = false;
      }
    }
    if (dom.insertCoinLabel) {
      dom.insertCoinLabel.textContent =
        hasPaidTime ? "ADD ADDITIONAL TIME" : "INSERT COIN";
    }
  }

  function renderPause() {
    var remaining = state.pausesRemaining;
    if (dom.pauseButtonText) {
      var label;
      if (state.sessionState === "activation_error" && state.canResume) {
        label = "RETRY INTERNET";
      } else {
        label = state.paused ? "RESUME" : "PAUSE";
        if (!state.paused && remaining !== null && remaining !== undefined) {
          label += " (" + remaining + " left)";
        }
      }
      dom.pauseButtonText.textContent = label;
    }
    if (dom.pauseButton) {
      dom.pauseButton.hidden = !sessionHydrated ||
        (!state.canPause && !state.canResume);
      dom.pauseButton.setAttribute("aria-pressed", state.paused ? "true" : "false");
      if (state.sessionState === "activation_error") {
        dom.pauseButton.title = state.activationErrorReason ||
          "Retry hotspot authorization — purchased time is preserved";
      } else {
        dom.pauseButton.title = !state.paused && remaining === 0
          ? "Pause limit reached for this session"
          : "";
      }
    }
  }

  // Issue 4: show/hide terminate button only when session is active
  function renderTerminateBtn() {
    if (!dom.terminateBtn) return;
    var hasSession = state.secondsLeft > 0 || state.paused;
    dom.terminateBtn.hidden = !sessionHydrated || !hasSession || !state.canTerminate;
  }

  function renderVoucherControls() {
    if (!dom.voucherCard) return;
    var activeVoucher = state.source === "voucher" &&
      state.sessionState !== "expired" && state.secondsLeft > 0;
    dom.voucherCard.hidden = activeVoucher;
  }

  function renderCoinModal() {
    var secs      = state.coinSessionActive ? derivedCoinSeconds() : INSERT_TIMEOUT;
    // Always use coinAmount — resets to 0 when modal opens, grows with new pulses only.
    var coinAmt   = state.coinAmount || 0;
    // Purchased time is ESP32/PromoManager authoritative (purchasedMinutes).
    var purchased = Number(state.purchasedMinutes) || 0;
    if (state.coinSessionActive && coinAmt > 0 && purchased <= 0) {
      // Keep last known server value; never invent a hardcoded minutes fallback in the browser.
      purchased = Number(state.coinVoucherMinutes) || 0;
    }
    state.coinVoucherMinutes = purchased;

    if (dom.coinCountdownEl)  dom.coinCountdownEl.textContent  = String(secs);
    if (dom.coinProgressBar) {
      dom.coinProgressBar.style.width = (secs / INSERT_TIMEOUT * 100) + "%";
    }
    if (dom.coinTimeEl) {
      dom.coinTimeEl.textContent = purchased > 0 ? purchased + "m" : "0m";
    }
    // #coinVoucherTime removed from customer UI (was duplicate of Time).
    if (dom.insertedAmountEl) {
      dom.insertedAmountEl.textContent = coinAmt.toFixed(2);
    }
    if (dom.coinNoteEl) {
      dom.coinNoteEl.textContent = state.coinSessionActive
        ? "Waiting for coin pulses from this device."
        : "Coin insert session is idle. Credits stay on this device.";
    }
  }

  // Issue 5: richer rate card rendering with speed profile and device limit
  function renderRatesModal(viewModel) {
    if (!dom.ratesList || !viewModel || !Array.isArray(viewModel.rates)) return;
    dom.ratesList.innerHTML = viewModel.rates.map(function (r) {
      var extras = "";
      if (r.speedProfile) {
        extras += '<span class="rate-meta">&#x1F4F6; ' + escapeHtml(r.speedProfile) + '</span>';
      }
      if (r.deviceLimit > 0) {
        extras += '<span class="rate-meta">&#x1F4BB; Max ' + r.deviceLimit + ' device' +
                  (r.deviceLimit > 1 ? "s" : "") + '</span>';
      }
      return '<div class="rate-card">' +
               '<span>&#8369;' + r.peso + '</span>' +
               '<strong>' + r.minutes + ' mins</strong>' +
               (extras ? '<div class="rate-extras">' + extras + '</div>' : '') +
             '</div>';
    }).join("");
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function renderDate() {
    if (dom.currentDateEl) {
      dom.currentDateEl.textContent = new Date().toLocaleString("en-PH", {
        weekday: "short", month: "short", day: "numeric",
        hour: "numeric", minute: "2-digit"
      });
    }
  }

  function pad(n) { return String(n).padStart(2, "0"); }

  function formatTime(sec) {
    var s = Math.max(0, (sec | 0));
    return pad(Math.floor(s / 3600)) + ":" +
           pad(Math.floor((s % 3600) / 60)) + ":" +
           pad(s % 60);
  }

  // ── init ───────────────────────────────────────────────────────────────────
  function init() {
    cacheDom();
    ensureDeviceIds();

    storageKey = STORAGE_PREFIX + ":" + getDeviceKey();
    state = loadCachedState();
    anchorSession(state.secondsLeft, false);
    render();

    refreshIdentityFromNetwork()
      .catch(function () {})
      .then(function () {
        storageKey = STORAGE_PREFIX + ":" + getDeviceKey();
        return loadRatesCache().catch(function () { return null; });
      })
      .then(function () { return tryResumeCoinLock(); })
      .then(function () { return loadBranding(); })
      .finally(function () {
        fetchSession()
          .then(function (result) {
            noteApplianceSuccess();
            var session = applyFetchedSession(result, true);
            if (session) {
              if (session.coinSessionActive || ff.coinWindow) restoreCoinSessionUI();
              return maybeReconnectVoucher(session).then(function () {
                startMainTimer();
                updateIdleSyncPolicy();
              });
            }
            startMainTimer();
            updateIdleSyncPolicy();
          })
          .catch(function () {
            noteApplianceFailure();
            if (state.secondsLeft > 0) {
              showServiceNotice();
            }
            startMainTimer();
            render();
            updateIdleSyncPolicy();
          });

        bindEvents();
        setInterval(renderDate, 1000);
        updateIdleSyncPolicy();
        document.addEventListener("visibilitychange", function () {
          if (document.hidden) {
            stopActiveSessionSync();
            disconnectPortalEvents();
            return;
          }
          syncSessionFromServer()
            .catch(function () {})
            .finally(function () { updateIdleSyncPolicy(); });
        });
      });

    window.RenzFiPortalCoinDetected = function (amount) {
      syncSessionFromServer().catch(function () {
        var peso = Math.max(1, Number(amount) || 1);
        state.credits = (state.credits || 0) + peso;
        saveStateCache();
        renderCoinModal();
        renderCredits();
      });
    };

    document.addEventListener("renzfi:coin", function (e) {
      window.RenzFiPortalCoinDetected(e.detail && e.detail.amount);
    });

    window.RenzFiPortalReady = true;
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
}());
