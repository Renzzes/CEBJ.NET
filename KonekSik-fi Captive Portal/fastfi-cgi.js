/**
 * FastFi / OpenWrt captive-portal CGI client
 * Baseline: EXTRACTED-OPENWRT-FASTFI-V2.5.1/rootfs/www/bootstrap.js
 *
 * All portal traffic goes to: /cgi-bin/api?action=<name>&...
 * Do NOT change the FastFi firmware tree — this client mirrors it.
 */
(function (global) {
  "use strict";

  var CGI = "/cgi-bin/api";

  /**
   * Exact public portal actions referenced by FastFi bootstrap.js
   * (action=<name> and URLSearchParams action:"…").
   */
  var BASELINE_ACTIONS = [
    "checkDevice",
    "check_coin_lock",
    "clearcredit",
    "fetchcoin",
    "gcash_freewindow",
    "gcash_order",
    "gcash_public_config",
    "getMac",
    "internet",
    "list_esp_devices",
    "lockcoin",
    "rates",
    "session_status",
    "unlockcoin",
    "updateDevice",
    "voucher"
  ];

  /** KonekSik public extensions (in firmware overlay, not original FastFi bootstrap). */
  var KONEKSIK_EXTENSIONS = [
    "terminate",
    "get_portal_media",
    "restore_default_banner"
  ];

  /** Core coin / session flow required for Captive Portal parity. */
  var REQUIRED_CORE_ACTIONS = [
    "getMac",
    "checkDevice",
    "session_status",
    "rates",
    "list_esp_devices",
    "lockcoin",
    "fetchcoin",
    "unlockcoin",
    "updateDevice",
    "clearcredit",
    "internet",
    "voucher",
    "terminate"
  ];

  function buildUrl(action, params) {
    var q = ["action=" + encodeURIComponent(action)];
    if (params) {
      Object.keys(params).forEach(function (k) {
        var v = params[k];
        if (v === undefined || v === null || v === "") return;
        q.push(encodeURIComponent(k) + "=" + encodeURIComponent(String(v)));
      });
    }
    return CGI + "?" + q.join("&");
  }

  function cgiGet(action, params) {
    return fetch(buildUrl(action, params), { cache: "no-store" }).then(function (res) {
      if (!res.ok) throw new Error("HTTP " + res.status);
      return res.json();
    });
  }

  var FastFiCgi = {
    CGI: CGI,
    BASELINE_ACTIONS: BASELINE_ACTIONS,
    KONEKSIK_EXTENSIONS: KONEKSIK_EXTENSIONS,
    REQUIRED_CORE_ACTIONS: REQUIRED_CORE_ACTIONS,
    buildUrl: buildUrl,
    cgiGet: cgiGet,

    getMac: function () {
      return cgiGet("getMac");
    },

    checkDevice: function (visitorId, mac, deviceId) {
      var p = {};
      if (visitorId) p.visitor_id = visitorId;
      if (mac) p.mac = mac;
      if (deviceId) p.device_id = deviceId;
      return cgiGet("checkDevice", p);
    },

    sessionStatus: function (mac, deviceId) {
      var p = {};
      if (mac) p.mac = mac;
      if (deviceId) p.device_id = deviceId;
      return cgiGet("session_status", p);
    },

    rates: function () {
      return cgiGet("rates");
    },

    listEspDevices: function () {
      return cgiGet("list_esp_devices");
    },

    lockCoin: function (slotMac, mac) {
      var p = { slot_mac: slotMac };
      if (mac) p.mac = mac;
      return cgiGet("lockcoin", p);
    },

    fetchCoin: function (slotMac) {
      var p = { ts: Date.now() };
      if (slotMac) p.slot_mac = slotMac;
      return cgiGet("fetchcoin", p);
    },

    unlockCoin: function (slotMac) {
      return cgiGet("unlockcoin", { slot_mac: slotMac });
    },

    clearCredit: function () {
      return cgiGet("clearcredit");
    },

    /**
     * Param names match bootstrap.js stopInsert() exactly:
     * time, mac, coin, download, upload, paused, data_limit_mb,
     * validity_minutes, device_id, client_id, slot_mac
     */
    updateDevice: function (opts) {
      opts = opts || {};
      return cgiGet("updateDevice", {
        time: opts.time || 0,
        mac: opts.mac || "",
        coin: opts.coin || 0,
        download: opts.download || 0,
        upload: opts.upload || 0,
        paused: opts.paused || 0,
        data_limit_mb: opts.data_limit_mb || 0,
        validity_minutes: opts.validity_minutes || 0,
        device_id: opts.device_id || "",
        client_id: opts.client_id || "",
        slot_mac: opts.slot_mac || ""
      });
    },

    /** status 0 = pause, 1 = resume (FastFi internet action) */
    internet: function (status, deviceId, mac) {
      var p = { status: status };
      if (deviceId) p.device_id = deviceId;
      if (mac) p.mac = mac;
      return cgiGet("internet", p);
    },

    voucher: function (code, mac, deviceId) {
      return cgiGet("voucher", {
        code: code,
        mac: mac || "",
        device_id: deviceId || ""
      });
    },

    gcashPublicConfig: function () {
      return cgiGet("gcash_public_config");
    },

    gcashOrder: function (price, mobile, mac) {
      return cgiGet("gcash_order", {
        price: price,
        mobile: mobile,
        mac: mac || ""
      });
    },

    gcashFreewindow: function () {
      return cgiGet("gcash_freewindow");
    },

    checkCoinLock: function (mac) {
      return cgiGet("check_coin_lock", { mac: mac || "" });
    },

    /** Captive-portal self-terminate (public). Admin kick uses client_deauth. */
    terminate: function (mac, deviceId) {
      var p = {};
      if (mac) p.mac = mac;
      if (deviceId) p.device_id = deviceId;
      return cgiGet("terminate", p);
    },

    /** Admin-only: kick/terminate any client by MAC. */
    clientDeauth: function (mac) {
      return cgiGet("client_deauth", { mac: mac || "" });
    },

    /** Banner + music paths (admin upload → portal). Public. */
    getPortalMedia: function () {
      return cgiGet("get_portal_media");
    },

    getBranding: function () {
      return cgiGet("get_branding");
    }
  };

  global.FastFiCgi = FastFiCgi;
})(typeof window !== "undefined" ? window : globalThis);
