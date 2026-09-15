/**
 * KonekSik-Fi Admin — local UI preview (no router / no real config).
 * Mocks /cgi-bin/api and unlocks the dashboard for browsing only.
 */
(function () {
  window.FASTFI_UI_PREVIEW = true;
  localStorage.setItem("fastfi_admin_logged", "yes");

  function jsonResponse(obj, status) {
    return new Response(JSON.stringify(obj), {
      status: status || 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  function getAction(url, opts) {
    try {
      var u = typeof url === "string" ? url : url && url.url ? url.url : "";
      var m = u.match(/[?&]action=([^&]+)/);
      if (m) return decodeURIComponent(m[1]);
      if (opts && opts.body) {
        var body = opts.body;
        if (typeof body === "string") {
          try {
            var j = JSON.parse(body);
            if (j && j.action) return j.action;
          } catch (e) {}
          var m2 = body.match(/(?:^|&)action=([^&]+)/);
          if (m2) return decodeURIComponent(m2[1]);
        }
      }
    } catch (e) {}
    return "";
  }

  var SAMPLE_SESSIONS = [
    {
      mac: "AA:BB:CC:11:22:33",
      ip: "192.168.1.50",
      hostname: "Preview-Phone",
      time_left: 1800,
      remaining: 1800,
      total_paid: 10,
      speed: "5 Mbps",
      status: "active",
    },
    {
      mac: "DE:AD:BE:EF:00:01",
      ip: "192.168.1.51",
      hostname: "Preview-Laptop",
      time_left: 3600,
      remaining: 3600,
      total_paid: 20,
      speed: "10 Mbps",
      status: "active",
    },
  ];

  var SAMPLE_RATES = [
    { coins: 1, minutes: 5, label: "₱1 / 5 min" },
    { coins: 5, minutes: 30, label: "₱5 / 30 min" },
    { coins: 10, minutes: 60, label: "₱10 / 1 hour" },
  ];

  var SAMPLE_PROFILES = [
    { id: 1, name: "Basic", down_kbps: 5120, up_kbps: 2048, enabled: 1, band: "auto" },
    { id: 2, name: "Standard", down_kbps: 10240, up_kbps: 5120, enabled: 1, band: "2.4" },
    { id: 3, name: "VIP", down_kbps: 20480, up_kbps: 10240, enabled: 1, band: "5" },
  ];
  var SAMPLE_PLANS = [
    { id: 1, name: "Day Pass", price: 50, duration_min: 1440, data_mb: 0, profile_id: 2, profile_name: "Standard", pause_limit: 3, enabled: 1 },
    { id: 2, name: "Weekly", price: 250, duration_min: 10080, data_mb: 0, profile_id: 2, profile_name: "Standard", pause_limit: 5, enabled: 1 },
    { id: 3, name: "Monthly", price: 800, duration_min: 43200, data_mb: 0, profile_id: 3, profile_name: "VIP", pause_limit: 10, enabled: 1 },
  ];
  var SAMPLE_CLIENTS = [
    { id: 1, name: "Juan dela Cruz", contact: "09xx", plan_id: 2, plan_name: "Weekly", notes: "", status: "active",
      devices: [{ id: 1, mac: "AA:BB:CC:11:22:33", hostname: "Galaxy" }] },
  ];
  var SAMPLE_DEVICES = [
    { mac: "AA:BB:CC:11:22:33", hostname: "Preview-Phone", ip: "192.168.1.50", status: "online", auth: "authenticated", radio: "wlan0", signal: "-52 dBm", blocked: false },
    { mac: "DE:AD:BE:EF:00:01", hostname: "Preview-Laptop", ip: "192.168.1.51", status: "online", auth: "authenticated", radio: "wlan1", signal: "-48 dBm", blocked: false },
    { mac: "11:22:33:44:55:66", hostname: "guest-phone", ip: "192.168.1.88", status: "online", auth: "unauthenticated", radio: "wlan0", signal: "-60 dBm", blocked: false },
  ];
  var SAMPLE_BLOCKS = [];
  var SAMPLE_USERS = [
    { id: 1, username: "admin", role: "owner", created_at: 0 },
    { id: 2, username: "staff1", role: "staff", created_at: 0 },
  ];
  var SAMPLE_APS = [
    {
      id: 1, name: "Built-in AP 2.4GHz", kind: "builtin", iface: "radio0", mac: "", ip: "",
      location: "Ruijie onboard", status: "online", enabled: 1, notes: "",
      esp: [{ id: 1, name: "Counter ESP", mac: "AA:11:22:33:44:55", status: "online", license_status: "licensed", last_seen: 0 }]
    },
    {
      id: 2, name: "Built-in AP 5GHz", kind: "builtin", iface: "radio1", mac: "", ip: "",
      location: "Ruijie onboard", status: "online", enabled: 1, notes: "", esp: []
    },
    {
      id: 3, name: "Hallway LAN AP", kind: "lan", iface: "", mac: "B8:27:EB:11:22:33", ip: "192.168.1.20",
      location: "2nd floor hallway", status: "online", enabled: 1, notes: "Bridged AP on LAN port",
      esp: [{ id: 2, name: "Hall ESP", mac: "CC:DD:EE:11:22:33", status: "online", license_status: "licensed", last_seen: 0 }]
    }
  ];
  var SAMPLE_ESP = [
    { id: 1, slot_name: "Counter ESP", slot_mac: "AA:11:22:33:44:55", status: "online", ap_id: 1 },
    { id: 2, slot_name: "Hall ESP", slot_mac: "CC:DD:EE:11:22:33", status: "online", ap_id: 3 },
  ];

  function mockFor(action, opts) {
    var body = {};
    try {
      if (opts && typeof opts.body === "string") body = JSON.parse(opts.body);
    } catch (e) {}

    switch (action) {
      case "admin_login": {
        var u = String(body.username || "admin").trim();
        var p = String(body.password || "");
        // Preview accepts admin/admin or admin/admin123
        if (u === "admin" && (p === "admin" || p === "admin123")) {
          return { status: "ok", message: "UI preview login", username: "admin", role: "owner", must_change_password: false };
        }
        return { status: "error", message: "Invalid username or password." };
      }
      case "admin_logout":
        return { status: "ok", message: "Logged out" };
      case "session_info":
        return { status: "ok", username: "admin", role: "owner" };
      case "system_status":
        return {
          status: "ok",
          uptime: 86400,
          sales_today: 350,
          sales_month: 12450,
          connected: SAMPLE_SESSIONS.length,
          current_clients: SAMPLE_SESSIONS.length,
          total_clients: SAMPLE_SESSIONS.length,
          cpu: 12,
          mem: 48,
          wan: "online",
        };
      case "dashboard_overview":
        return {
          status: "ok",
          kpis: { sales_today: 350, sales_week: 2100, sales_month: 12450, connected: 4, sessions: 3, waiting: 1 },
          per_ap_esp: [
            { ap_id: 1, ap_name: "Built-in AP 2.4GHz", ap_kind: "builtin", esp_id: 1, esp_name: "Counter ESP", connected: 2, waiting: 1, sessions: 2, sales: 200 },
            { ap_id: 3, ap_name: "Hallway LAN AP", ap_kind: "lan", esp_id: 2, esp_name: "Hall ESP", connected: 2, waiting: 0, sessions: 1, sales: 150 },
          ],
          totals: { connected: 4, waiting: 1, sessions: 3, sales: 350 },
          network_status: {
            internet: "online",
            ruijie: "online",
            wifi: "online",
            access_points: "3/3 online",
            latency_ms: 18,
            packet_loss: 0
          },
          ruijie: {
            model: "RG-EW1200G Pro",
            firmware: "OpenWrt 24.10.7",
            fastfi_version: "2.5.1",
            uptime: 86400,
            connection: "connected",
            cpu: 12,
            memory: 48,
            storageTotalMb: 128,
            storageLive: true,
            temperature: null,
            storageSlices: [
              { label: "Admin & portal", mb: 18, color: "#7F2D37" },
              { label: "Data / DBs", mb: 22, color: "#2563eb" },
              { label: "System / other", mb: 35, color: "#64748b" }
            ]
          },
          recent_sessions: [
            { mac: "AA:BB:CC:11:22:33", remaining: 1800, status: "active", sub_vendo_id: 1 },
            { mac: "DE:AD:BE:EF:00:01", remaining: 3600, status: "active", sub_vendo_id: 2 },
            { mac: "11:22:33:44:55:66", remaining: 0, status: "expired", sub_vendo_id: 0 }
          ],
          connected_users: SAMPLE_DEVICES.filter(function (d) { return d.auth === "authenticated"; }).map(function (d) {
            return Object.assign({}, d, { session: { remaining: d.remaining || 1800 } });
          }),
          access_points: SAMPLE_APS
        };
      case "list_access_points":
        return { status: "ok", data: SAMPLE_APS };
      case "save_access_point":
      case "delete_access_point":
      case "bind_esp_to_ap":
        return { status: "ok" };
      case "list_esp_devices":
        return {
          status: "ok",
          router_license_status: "active",
          total_esp_slots: SAMPLE_ESP.length,
          available_licenses: 0,
          used_licenses: 1,
          licensed_esp_count: 1,
          esp_devices: SAMPLE_ESP.map(function (e) {
            return {
              id: e.id,
              slot_name: e.slot_name || e.name || "ESP32",
              slot_mac: e.slot_mac || e.mac,
              status: e.status || "online",
              license_status: e.license_status || "licensed",
              license_key: e.license_key || "KSK-PREVIEW001",
              license_id: e.license_id || "KSK-PREVIEW001",
              last_seen: Math.floor(Date.now() / 1000),
              ap_id: e.ap_id || 0,
            };
          }),
        };
      case "esp_license_list":
        return {
          status: "ok",
          data: [
            {
              id: 1,
              license_id: "KSK-PREVIEW001",
              license_key: "KSK-PREVIEW001",
              status: "used",
              live_mac: "AA:11:22:33:44:55",
              grace_used: 0,
              grace_max: 3,
              used_at: "2026-09-15",
            },
          ],
        };
      case "esp_license_add":
        return { status: "ok", message: "ESP32 license registered (preview)" };
      case "esp_detect":
        return {
          status: "ok",
          message: "ESP32 detected and licensed — Insert Coin active (preview)",
          license_id: "KSK-PREVIEW001",
          live_mac: "AA:11:22:33:44:55",
          grace_used: 0,
          grace_max: 3,
          licensed: true,
        };
      case "live_sessions":
      case "client_list":
        return { status: "ok", data: SAMPLE_SESSIONS };
      case "client_list_unauth":
      case "waiting_queue":
        return { status: "ok", data: SAMPLE_DEVICES.filter(function (d) { return d.auth === "unauthenticated"; }) };
      case "license_status":
        return {
          status: "active",
          device_id: "PREVIEWDEVICE01",
          license_key: "STD-PREVIEW-ONLY-UI-MODE",
          expires: "2099-12-31",
        };
      case "pause_limit":
        return { status: "ok", pause_limit: 3, enabled: 1 };
      case "rates":
        return { status: "ok", data: SAMPLE_RATES, rates: SAMPLE_RATES };
      case "sales_data": {
        // filter is not passed into mockFor; default week series (client still charts)
        return {
          status: "ok",
          labels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
          data: [120, 200, 150, 280, 90, 310, 350],
          today: 350,
          month: 12450,
          total: 58200,
        };
      }
      case "sales_totals":
        return { status: "ok", daily: 350, weekly: 2100, monthly: 12450, total: 58200 };
      case "sales_history": {
        const now = Math.floor(Date.now() / 1000);
        // row indices used by admin.js: [1]=mac [2]=amount [3]=coins [4]=ts [5]=device [6]=end [7]=dl [8]=ul [9]=pause
        return {
          status: "success",
          range_total: 95,
          data: [
            [0, "AA:BB:CC:DD:EE:01", 25, 5, now - 3600, "iPhone 14", now + 7200, 10, 5, 3],
            [0, "AA:BB:CC:DD:EE:02", 50, 10, now - 7200, "Android", now - 60, 5, 2, 3],
            [0, "AA:BB:CC:DD:EE:03", 20, 4, now - 10800, "Laptop", now + 3600, 20, 10, 3],
          ],
        };
      }
      case "list_vouchers":
        return { status: "ok", data: [] };
      case "get_ssid":
        return { status: "ok", ssid: "KonekSik-Fi", ssid_5g: "KonekSik-Fi-5G" };
      case "get_esp_wifi":
        return { status: "ok", ssid: "ESP-Preview", enabled: 0 };
      case "wan_status":
        return { status: "ok", wan: "up", ip: "203.0.113.10", proto: "dhcp" };
      case "remote_access":
      case "tailscale_status":
        return {
          status: "ok",
          provider: "tailscale",
          installed: 0,
          daemon_running: 0,
          connected: 0,
          ip: "",
          admin_url: "",
          message: "Preview: Tailscale not installed (sample). On a real router use Install → paste auth key → Start.",
        };
      case "tailscale_install":
        return { status: "ok", provider: "tailscale", installed: 1, message: "Preview mock — install skipped" };
      case "tailscale_up":
      case "remote_access_connect":
      case "remote_access_enroll":
        return {
          status: "ok",
          provider: "tailscale",
          connected: 1,
          daemon_running: 1,
          installed: 1,
          ip: "100.64.0.10",
          admin_url: "http://100.64.0.10/admin.html",
          message: "Preview mock — Tailscale connected",
        };
      case "tailscale_down":
      case "remote_access_disconnect":
        return { status: "ok", provider: "tailscale", connected: 0, daemon_running: 0, message: "Preview mock — stopped" };
      case "check_update":
        return { status: "ok", update_available: false, current: "2.5.1" };
      case "autopause_config":
        return { status: "ok", enabled: 0 };
      case "firewall_status":
      case "shield_status":
        return { status: "ok", enabled: false };
      case "dhcp_leases":
        return { status: "ok", data: [] };
      case "database_stats":
        return { status: "ok", size_mb: 1.2, tables: 8 };
      case "gcash_config_get":
      case "gcash_public_config":
        return { status: "ok", enabled: false };
      case "list_profiles":
        return { status: "ok", data: SAMPLE_PROFILES };
      case "save_profile": {
        var pid = body && body.id != null && body.id !== "" ? Number(body.id) : 0;
        var band = String((body && body.band) || "auto").toLowerCase();
        if (band !== "2.4" && band !== "5") band = "auto";
        if (pid) {
          SAMPLE_PROFILES = SAMPLE_PROFILES.map(function (p) {
            if (p.id !== pid) return p;
            return {
              id: p.id,
              name: (body && body.name) || p.name,
              down_kbps: Number((body && body.down_kbps) != null ? body.down_kbps : p.down_kbps),
              up_kbps: Number((body && body.up_kbps) != null ? body.up_kbps : p.up_kbps),
              enabled: Number((body && body.enabled) != null ? body.enabled : p.enabled),
              band: band,
            };
          });
        } else {
          var nid = SAMPLE_PROFILES.reduce(function (m, p) { return Math.max(m, p.id); }, 0) + 1;
          SAMPLE_PROFILES.push({
            id: nid,
            name: (body && body.name) || "Profile",
            down_kbps: Number((body && body.down_kbps) || 10240),
            up_kbps: Number((body && body.up_kbps) || 5120),
            enabled: Number((body && body.enabled) != null ? body.enabled : 1),
            band: band,
          });
          pid = nid;
        }
        return { status: "ok", id: pid, message: "Preview mock OK" };
      }
      case "delete_profile":
        if (body && body.id) {
          SAMPLE_PROFILES = SAMPLE_PROFILES.filter(function (p) { return p.id !== Number(body.id); });
        }
        return { status: "ok", message: "Preview mock OK" };
      case "save_plan":
      case "delete_plan":
      case "save_plan_client":
      case "delete_plan_client":
      case "attach_plan_device":
      case "detach_plan_device":
      case "activate_plan":
      case "block_mac":
      case "unblock_mac":
      case "create_admin_user":
      case "delete_admin_user":
      case "set_branding":
      case "upload_logo":
      case "clear_logo":
      case "radio_restart":
      case "sms_test":
        return { status: "ok", message: "Preview mock OK" };
      case "list_plans":
        return { status: "ok", data: SAMPLE_PLANS };
      case "list_plan_clients":
        return { status: "ok", data: SAMPLE_CLIENTS };
      case "list_devices":
        return { status: "ok", data: SAMPLE_DEVICES };
      case "list_mac_blocks":
        return { status: "ok", data: SAMPLE_BLOCKS };
      case "list_admin_users":
        return { status: "ok", data: SAMPLE_USERS };
      case "get_role_permissions":
        return {
          status: "ok",
          data: window.__ffPreviewRolePerms || {
            view_dashboard: { owner: true, admin: true, staff: true, viewer: true },
            manage_sessions: { owner: true, admin: true, staff: true, viewer: false },
            edit_rates: { owner: true, admin: true, staff: true, viewer: false },
            network: { owner: true, admin: true, staff: false, viewer: false },
            operators: { owner: true, admin: false, staff: false, viewer: false },
            ota: { owner: true, admin: true, staff: false, viewer: false },
            branding: { owner: true, admin: true, staff: false, viewer: false },
          },
        };
      case "set_role_permissions":
        if (body && body.permissions) window.__ffPreviewRolePerms = body.permissions;
        return { status: "ok", data: window.__ffPreviewRolePerms || body.permissions || {}, message: "Preview mock OK" };
      case "activity_feed":
        return { status: "ok", data: [
          { id: 1, ts: Date.now()/1000|0, type: "info", title: "Preview mode", body: "Sample activity" },
          { id: 2, ts: Date.now()/1000|0, type: "success", title: "Plan activated", body: "Day Pass → AA:BB:CC:11:22:33" },
        ]};
      case "audit_feed":
        return { status: "ok", data: [
          { id: 1, ts: Date.now()/1000|0, username: "admin", action: "login", detail: "OK" },
        ]};
      case "get_branding":
        return { status: "ok", login_logo: "./image/CEBJ.png", nav_logo: "./image/CEBJ.png", portal_logo: "", shop_name: "CEBJ.NET", voucher_template_note: "Thank you!", backup_schedule_enabled: 0, sms_enabled: 0, sms_provider: "none", sms_endpoint: "" };
      case "get_portal_media":
        return {
          status: "ok",
          has_custom_banner: window.__ffPreviewCustomBanner ? 1 : 0,
          banner_url: window.__ffPreviewCustomBanner
            ? "./image/banner.jpg?t=" + Date.now()
            : "./image/Default-Banner.png?t=" + Date.now(),
          default_banner_url: "./image/Default-Banner.png",
          music_url: "./audio/insert.mp3",
          bg_music_url: "./audio/insert.mp3",
          coin_url: "./audio/coin.mp3",
          success_url: "./audio/success.mp3",
          banner_text: "Insert coin or enter voucher to start",
          brand_name: "CEBJ.NET",
          shop_name: "CEBJ.NET",
        };
      case "restore_default_banner":
        window.__ffPreviewCustomBanner = false;
        return { status: "ok", message: "Restored Default-Banner.png", custom: 0, default_banner_url: "./image/Default-Banner.png" };
      case "upload_banner":
        window.__ffPreviewCustomBanner = true;
        return { status: "ok", message: "Banner uploaded successfully!", custom: 1 };
      case "upload_audio":
        return { status: "ok", message: "Audio uploaded successfully!" };
      case "radio_status":
        return { status: "ok", data: [
          { iface: "wlan0", ssid: "KonekSik-Fi", band: "2.4 GHz", channel: "6", clients: 2, txpower: "20" },
          { iface: "wlan1", ssid: "KonekSik-Fi-5G", band: "5 GHz", channel: "36", clients: 1, txpower: "23" },
        ]};
      case "sales_by_vendo":
        return { status: "ok", data: [ { sub_vendo_id: 0, amount: 200, count: 12, coins: 40 }, { sub_vendo_id: 1, amount: 150, count: 8, coins: 30 } ] };
      case "reports_summary":
        return { status: "ok", period: "day", sales_total: 350, sales_count: 20, active_sessions: 2, generated_at: Date.now()/1000|0 };
      case "upload_firmware":
        return { status: "ok", message: "Firmware staged (preview)", path: "/tmp/preview.bin", size: 12000000, size_mb: 11.4 };
      case "flash_firmware":
        return { status: "ok", message: "Preview mode — flash not executed" };
      case "pricing_hub":
        return { status: "ok", rates: SAMPLE_RATES, plans: SAMPLE_PLANS, profiles: SAMPLE_PROFILES };
      default:
        return { status: "ok", message: "UI preview mock", data: [], action: action || "unknown" };
    }
  }

  var realFetch = window.fetch.bind(window);
  window.fetch = function (url, opts) {
    var u = typeof url === "string" ? url : url && url.url ? String(url.url) : "";
    if (u.indexOf("/cgi-bin/api") !== -1) {
      var action = getAction(u, opts);
      return Promise.resolve(jsonResponse(mockFor(action, opts)));
    }
    return realFetch(url, opts);
  };

  function ensurePreviewBanner() {
    var banner = document.getElementById("uiPreviewBanner");
    if (!banner) {
      banner = document.createElement("div");
      banner.id = "uiPreviewBanner";
      banner.textContent = "UI PREVIEW — sample data only (no router config) · CEBJ.NET · login: admin / admin";
      banner.style.cssText =
        "position:fixed;top:0;left:0;right:0;z-index:99999;background:#7c3aed;color:#fff;" +
        "font:12px/1.4 system-ui,sans-serif;text-align:center;padding:6px 10px;box-sizing:border-box;height:28px;";
      document.body.appendChild(banner);
      document.body.classList.add("ui-preview-mode");
      var shell = document.querySelector(".app-shell");
      if (shell) {
        shell.style.height = "calc(100vh - 28px)";
        shell.style.maxHeight = "calc(100vh - 28px)";
        shell.style.marginTop = "28px";
      }
    }
  }

  function showPreviewApp() {
    var loginEl = document.getElementById("loginSection");
    var panelEl = document.getElementById("adminPanel");
    if (loginEl) loginEl.classList.add("hidden");
    if (panelEl) panelEl.classList.remove("hidden");
    try {
      if (typeof initDashboard === "function") initDashboard();
    } catch (e) {}
  }

  function showPreviewLogin() {
    var loginEl = document.getElementById("loginSection");
    var panelEl = document.getElementById("adminPanel");
    if (loginEl) loginEl.classList.remove("hidden");
    if (panelEl) panelEl.classList.add("hidden");
    var overlay = document.getElementById("success-overlay");
    if (overlay) overlay.classList.remove("show");
  }

  function unlockUi() {
    ensurePreviewBanner();
    // Honor session: do not force auto-login so Logout/Login work in preview
    if (localStorage.getItem("fastfi_admin_logged") === "yes") {
      showPreviewApp();
    } else {
      showPreviewLogin();
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      setTimeout(unlockUi, 50);
    });
  } else {
    setTimeout(unlockUi, 50);
  }
  window.addEventListener("load", function () {
    setTimeout(unlockUi, 100);
  });
})();
