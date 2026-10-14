/**
 * KonekSik-Fi Admin extensions — Plans, Devices, Operators, Reports, Branding, etc.
 */
(function () {
  const api = (action, opts) => {
    opts = opts || {};
    const method = opts.method || (opts.body ? "POST" : "GET");
    let url = "/cgi-bin/api?action=" + encodeURIComponent(action);
    if (opts.query) {
      Object.keys(opts.query).forEach((k) => {
        url += "&" + encodeURIComponent(k) + "=" + encodeURIComponent(opts.query[k]);
      });
    }
    const init = { credentials: "include", method, cache: "no-store" };
    if (opts.body) {
      init.headers = { "Content-Type": "application/json" };
      init.body = JSON.stringify(opts.body);
    }
    return fetch(url, init).then((r) => r.json());
  };

  const _ffApiFetch = window.fetch.bind(window);
  window.fetch = function (url, opts) {
    if (typeof url === "string" && /[?&]action=(sales_totals|sales_data|sales_history|delete_sales|sales_report)(&|$)/.test(url) && url.indexOf("vendo=") === -1) {
      const sel = document.getElementById("salesVendoFilter");
      url += "&vendo=" + encodeURIComponent((sel && sel.value) || "all");
    }
    return _ffApiFetch(url, opts);
  };

  const toast = (m, t) => {
    if (typeof showToast === "function") showToast(m, t || "info");
    else console.log(t, m);
  };

  const peso = (n) => "₱" + Number(n || 0).toLocaleString();
  // Lua json.encode used to emit {} for empty lists — never trust || [] alone.
  const asArr = (v) => (Array.isArray(v) ? v : []);

  // ---- Auth: KonekSik-style login + working logout ----
  function ffShowLoginScreen() {
    const loginEl = document.getElementById("loginSection");
    const panelEl = document.getElementById("adminPanel");
    const overlay = document.getElementById("success-overlay");
    const btn = document.getElementById("login-btn");
    const err = document.getElementById("login-error");
    if (overlay) overlay.classList.remove("show");
    if (loginEl) loginEl.classList.remove("hidden");
    if (panelEl) panelEl.classList.add("hidden");
    if (btn) {
      btn.disabled = false;
      btn.innerHTML = "Sign in";
    }
    if (err) {
      err.textContent = "";
      err.classList.remove("show");
    }
    document.querySelectorAll("#loginSection .field.invalid").forEach((n) => n.classList.remove("invalid"));
    const pass = document.getElementById("adminPass");
    if (pass) pass.value = "";
    setTimeout(() => document.getElementById("adminUser")?.focus(), 50);
    if (typeof hydrateIcons === "function") hydrateIcons();
  }

  function ffShowAdminAfterLogin() {
    const overlay = document.getElementById("success-overlay");
    if (overlay) overlay.classList.add("show");
    setTimeout(() => {
      document.getElementById("loginSection")?.classList.add("hidden");
      document.getElementById("adminPanel")?.classList.remove("hidden");
      if (overlay) overlay.classList.remove("show");
      if (typeof initDashboard === "function") initDashboard();
      if (typeof initAutoLogout === "function") initAutoLogout();
      ffLoadDashboardOverview();
      ffLoadBranding();
      if (typeof hydrateIcons === "function") hydrateIcons();
    }, 900);
  }

  function ffLoginFail(message) {
    const wrap = document.getElementById("login-wrap");
    const err = document.getElementById("login-error");
    const flash = document.getElementById("fail-flash");
    const btn = document.getElementById("login-btn");
    if (wrap) {
      wrap.classList.remove("shake");
      void wrap.offsetWidth;
      wrap.classList.add("shake");
    }
    document.getElementById("loginUserField")?.classList.add("invalid");
    document.getElementById("loginPassField")?.classList.add("invalid");
    if (err) {
      err.textContent = message || "Invalid username or password.";
      err.classList.add("show");
    }
    if (flash) {
      flash.classList.remove("show");
      void flash.offsetWidth;
      flash.classList.add("show");
    }
    if (btn) {
      btn.disabled = false;
      btn.innerHTML = "Sign in";
    }
  }

  window.login = function () {
    const password = document.getElementById("adminPass")?.value || "";
    const username = (document.getElementById("adminUser")?.value || "admin").trim();
    const btn = document.getElementById("login-btn");
    const err = document.getElementById("login-error");
    document.querySelectorAll("#loginSection .field.invalid").forEach((n) => n.classList.remove("invalid"));
    if (err) {
      err.textContent = "";
      err.classList.remove("show");
    }
    if (!username || !password) {
      ffLoginFail("Please enter username and password.");
      return;
    }
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner"></span> Signing in';
    }
    fetch("/cgi-bin/api?action=admin_login", {
      credentials: "include",
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password }),
    })
      .then((res) => res.json())
      .then((data) => {
        if (data.status === "ok") {
          localStorage.setItem("fastfi_admin_logged", "yes");
          localStorage.setItem("fastfi_admin_user", data.username || username);
          localStorage.setItem("fastfi_admin_role", data.role || "owner");
          ffShowAdminAfterLogin();
          if (data.must_change_password && typeof forcePasswordChange === "function") {
            setTimeout(() => forcePasswordChange(), 1000);
          }
        } else {
          ffLoginFail(data.message || "Invalid username or password.");
        }
      })
      .catch((e) => ffLoginFail("Login failed: " + e));
  };

  window.logout = function () {
    fetch("/cgi-bin/api?action=admin_logout", {
      credentials: "include",
      method: "POST",
    }).finally(() => {
      localStorage.removeItem("fastfi_admin_logged");
      localStorage.removeItem("fastfi_admin_user");
      localStorage.removeItem("fastfi_admin_role");
      if (typeof clearAutoLogoutTimer === "function") clearAutoLogoutTimer();
      // Preview / SPA: return to login without forced reload loop
      if (window.FASTFI_UI_PREVIEW) {
        ffShowLoginScreen();
        return;
      }
      location.reload();
    });
  };

  // Wrap hideAll to include new sections
  const _hideAll = window.hideAll;
  window.hideAll = function () {
    if (typeof _hideAll === "function") _hideAll();
    [
      
      "bandwidthSection",
      
      "devicesSection",
      "waitingSection",
      "radioSection",
      "accessPointsSection",
      "pricingHubSection",
      "operatorsSection",
      "reportsSection",
      "captivePortalSection",
    ].forEach((id) => document.getElementById(id)?.classList.add("hidden"));
  };

  function showSec(id, hash, loader) {
    if (typeof hideAll === "function") hideAll();
    document.getElementById(id)?.classList.remove("hidden");
    if (typeof setHash === "function") setHash(hash);
    if (typeof closeSidebarMobile === "function") closeSidebarMobile();
    if (loader) loader();
  }

  
  window.showBandwidth = () => showSec("bandwidthSection", "bandwidth", ffLoadProfiles);
  
  window.showDevices = () => showSec("devicesSection", "devices", () => {
    ffLoadDevices();
    ffLoadBlocks();
  });
  window.showWaitingQueue = () => showSec("waitingSection", "waiting", ffLoadWaiting);
  window.showRadioStatus = () => showSec("radioSection", "radio", ffLoadRadios);
  window.showPricingHub = function () {
    toast("Pricing Hub removed — use Coin Rates and Bandwidth instead", "info");
    showRates();
  };

  const PAGE_META = {
    dashboard: ["Dashboard", "Overview of your CEBJ.NET system"],
    sales: ["Sales", "Revenue and transaction history"],
    rates: ["Coin Rates", "Insert-coin pricing tiers"],
    bandwidth: ["Bandwidth", "Speed profiles and current traffic"],
    sessions: ["Sessions", "Active and paused internet sessions"],
    devices: ["Devices", "LAN / Wi‑Fi clients"],
    waiting: ["Waiting Queue", "Unauthenticated clients"],
    vouchers: ["Vouchers", "Generate and manage vouchers"],
    gcash: ["GCash", "Setup → mint pool → companion"],
    "captive-portal": ["Captive Portal", "Banner and portal audio"],
    network: ["Network", "WAN, DHCP, and Shield"],
    "access-points": ["Access Points", "Built-in radios and LAN APs"],
    wifi: ["WiFi SSID", "Public and private SSIDs"],
    radio: ["Radio Status", "Built-in Ruijie Wi‑Fi radios"],
    settings: ["Settings", "License, security, and branding"],
    operators: ["Operators", "RBAC users and audit log"],
    reports: ["Sales", "Revenue and transaction history"],
    "remote-access": ["Remote Access", "Tailscale (recommended) + WireGuard (test)"],
    "sub-vendo": ["Sub Vendo", "ESP32 coin stations"],
    update: ["OTA Update", "Firmware updates and stock restore"],
  };

  window.ffSetPageHeader = function (hash) {
    const meta = PAGE_META[hash] || ["CEBJ.NET", ""];
    const t = document.getElementById("appPageTitle");
    const c = document.getElementById("appPageCrumb");
    if (t) t.textContent = meta[0];
    if (c) c.textContent = meta[1];
  };

  const _setHash = window.setHash;
  window.setHash = function (page) {
    if (typeof _setHash === "function") _setHash(page);
    else if (location.hash !== "#" + page) history.replaceState(null, "", "#" + page);
    ffSetPageHeader(page);
    if (typeof highlightSidebar === "function") highlightSidebar(page);
  };
  window.showOperators = () => showSec("operatorsSection", "operators", () => {
    ffLoadRolePerms();
    ffLoadUsers();
    ffLoadAudit();
  });
  window.showReports = function () {
    if (typeof window.showSales === "function") window.showSales();
  };

  window.showCaptivePortal = function () {
    showSec("captivePortalSection", "captive-portal", () => {
      if (typeof loadAudioPreviews === "function") loadAudioPreviews();
      if (typeof loadPortalBannerPreviews === "function") loadPortalBannerPreviews();
      if (window.CaptivePortalLivePreview && typeof CaptivePortalLivePreview.init === "function") {
        CaptivePortalLivePreview.init();
      }
      if (typeof hydrateIcons === "function") hydrateIcons();
    });
  };

  window.loadPortalBannerPreviews = function () {
    const status = document.getElementById("currentBannerStatus");
    return api("get_portal_media").then((data) => {
      if (!data || data.status === "error") {
        if (status) status.textContent = "Using Default-Banner.png";
        if (window.CaptivePortalLivePreview) CaptivePortalLivePreview.setApplianceCustom(false);
        return data;
      }
      const custom = Number(data.has_custom_banner) === 1;
      if (status) {
        status.textContent = custom
          ? "Custom banner active on appliance (pick a file to preview it live)"
          : "Using Default-Banner.png (no custom upload)";
        status.className = "small mb-1 mt-2 fw-semibold " + (custom ? "text-success" : "text-muted");
      }
      if (window.CaptivePortalLivePreview) {
        CaptivePortalLivePreview.setApplianceCustom(custom);
        CaptivePortalLivePreview.scale();
      }
      return data;
    }).catch(() => {
      if (status) status.textContent = "Using Default-Banner.png";
      if (window.CaptivePortalLivePreview) CaptivePortalLivePreview.setApplianceCustom(false);
    });
  };

  window.restoreDefaultBanner = function () {
    if (!confirm("Restore Default-Banner.png on the captive portal? Custom upload will be removed.")) return;
    const resultSpan = document.getElementById("bannerResult");
    if (resultSpan) {
      resultSpan.innerText = "Restoring default…";
      resultSpan.className = "mt-1 mb-3 fw-semibold text-warning";
    }
    api("restore_default_banner").then((data) => {
      if (data && data.status === "ok") {
        if (resultSpan) {
          resultSpan.innerText = data.message || "Default banner restored";
          resultSpan.className = "mt-1 mb-3 fw-semibold text-success";
        }
        if (typeof showToast === "function") showToast("Default-Banner.png restored", "success");
        if (window.CaptivePortalLivePreview) CaptivePortalLivePreview.clearLocalPicks();
        loadPortalBannerPreviews();
      } else {
        const msg = (data && data.message) || "Restore failed";
        if (resultSpan) {
          resultSpan.innerText = msg;
          resultSpan.className = "mt-1 mb-3 fw-semibold text-danger";
        }
        if (typeof showToast === "function") showToast(msg, "error");
      }
    }).catch(() => {
      if (resultSpan) {
        resultSpan.innerText = "Restore failed";
        resultSpan.className = "mt-1 mb-3 fw-semibold text-danger";
      }
    });
  };

  // After stock uploadBanner succeeds, refresh status + clear pending pill.
  (function patchUploadBannerRefresh() {
    const prev = window.uploadBanner;
    if (typeof prev !== "function") return;
    window.uploadBanner = function () {
      const fileInput = document.getElementById("bannerFile");
      const hadFile = fileInput && fileInput.files && fileInput.files[0];
      prev.apply(this, arguments);
      if (!hadFile) return;
      let tries = 0;
      const timer = setInterval(() => {
        tries += 1;
        const result = document.getElementById("bannerResult");
        const text = (result && result.innerText) || "";
        if (/success/i.test(text) || tries >= 20) {
          clearInterval(timer);
          if (typeof loadPortalBannerPreviews === "function") loadPortalBannerPreviews();
          const pill = document.getElementById("cpSyncPill");
          if (pill) {
            pill.classList.remove("is-pending");
            pill.textContent = "Synced";
          }
        }
      }, 400);
    };
  })();


  window.showAccessPoints = () => showSec("accessPointsSection", "access-points", ffLoadAccessPoints);
function ffSetRemoteToggle(id, labelId, on, busy) {
    const t = document.getElementById(id);
    const lab = document.getElementById(labelId);
    if (t) {
      t._ffSyncing = true;
      t.checked = !!on;
      t.disabled = !!busy;
      t._ffSyncing = false;
    }
    if (lab) lab.textContent = on ? "Enabled" : "Disabled";
  }

  window.showRemoteAccess = () => showSec("remoteAccessSection", "remote-access", ffLoadZeroTier);

  window.ffLoadZeroTier = function () {
    api("zerotier_status").then((d) => {
      if (!d) return;
      const installed = Number(d.installed) === 1;
      const enabled = Number(d.enabled) === 1;
      const online = Number(d.online) === 1;
      const net = String(d.network_status || "");
      const inst = document.getElementById("ztInstalled");
      if (inst) inst.textContent = installed ? "Ready" : "Missing";
      const daemon = document.getElementById("ztDaemon");
      if (daemon) {
        daemon.className = "badge " + (enabled ? "bg-success" : "bg-secondary");
        daemon.textContent = enabled ? (online ? "Online" : "Starting") : "Off";
      }
      const ns = document.getElementById("ztNetStatus");
      if (ns) {
        if (net === "OK") {
          ns.className = "badge bg-success";
          ns.textContent = "Authorized";
        } else if (net === "ACCESS_DENIED" || net === "REQUESTING_CONFIGURATION") {
          ns.className = "badge bg-warning text-dark";
          ns.textContent = "Approve on website";
        } else {
          ns.className = "badge bg-secondary";
          ns.textContent = enabled ? "Waiting" : "—";
        }
      }
      const node = document.getElementById("ztNodeId");
      if (node) node.textContent = d.node_id || "—";
      const ip = document.getElementById("ztIP");
      if (ip) ip.textContent = d.ip || "—";
      const urlEl = document.getElementById("ztAdminURL");
      if (urlEl) {
        if (d.admin_url) {
          urlEl.href = d.admin_url;
          urlEl.textContent = d.admin_url;
        } else {
          urlEl.removeAttribute("href");
          urlEl.textContent = "—";
        }
      }
      const box = document.getElementById("ztNetworkId");
      if (box && document.activeElement !== box && d.network_id) box.value = d.network_id;
      const msg = document.getElementById("ztMessage");
      if (msg) msg.textContent = d.message || "";
      ffSetRemoteToggle("ztEnableToggle", "ztEnableToggleLabel", enabled, false);
    }).catch(() => {});
  };

  window.ffZeroTierToggle = function (el) {
    if (!el || el._ffSyncing) return;
    const box = document.getElementById("ztNetworkId");
    const networkId = ((box && box.value) || "").trim();
    if (el.checked) {
      if (!/^[0-9a-fA-F]{16}$/.test(networkId)) {
        el.checked = false;
        toast("Paste the 16-character Network ID from my.zerotier.com", "warning");
        return;
      }
      el.disabled = true;
      const lab = document.getElementById("ztEnableToggleLabel");
      if (lab) lab.textContent = "Starting…";
      api("zerotier_enable", { method: "POST", body: { network_id: networkId } })
        .then((d) => {
          toast((d && d.message) || (d && d.status === "ok" ? "ZeroTier started" : "Failed"), d && d.status === "ok" ? "success" : "error");
          if (!d || d.status !== "ok") el.checked = false;
          ffLoadZeroTier();
        })
        .catch(() => {
          el.checked = false;
          toast("ZeroTier failed to start", "error");
        })
        .finally(() => { el.disabled = false; });
    } else {
      el.disabled = true;
      const lab = document.getElementById("ztEnableToggleLabel");
      if (lab) lab.textContent = "Stopping…";
      api("zerotier_disable", { method: "POST", body: {} })
        .then((d) => {
          toast((d && d.message) || "ZeroTier stopped", d && d.status === "ok" ? "success" : "error");
          ffLoadZeroTier();
        })
        .catch(() => toast("Failed to stop ZeroTier", "error"))
        .finally(() => { el.disabled = false; });
    }
  };

  window.loadRemoteAccessStatus = function () { ffLoadZeroTier(); };
  window.toggleVPN = function () { ffLoadZeroTier(); };
  window.enrollRemoteAccess = function () { ffLoadZeroTier(); };

  // ---- Dashboard redesign (Per AP + ESP, Network, Ruijie, sessions/users) ----
  function fmtUptime(sec) {
    sec = Math.floor(Number(sec) || 0);
    const d = Math.floor(sec / 86400);
    const h = Math.floor((sec % 86400) / 3600);
    const m = Math.floor((sec % 3600) / 60);
    if (d > 0) return d + "d " + h + "h";
    if (h > 0) return h + "h " + m + "m";
    return m + "m";
  }
  function fmtRemain(sec) {
    sec = Math.max(0, Math.floor(Number(sec) || 0));
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    if (h > 0) return h + "h " + m + "m";
    return m + "m";
  }
  function statusBadge(s) {
    const v = String(s || "unknown").toLowerCase();
    const cls =
      v === "online" || v === "connected" || v === "active"
        ? "success"
        : v === "offline" || v === "blocked" || v === "expired"
          ? "secondary"
          : v === "paused" || v === "degraded"
            ? "warning"
            : "secondary";
    return `<span class="badge bg-${cls}">${esc(v)}</span>`;
  }

  window.ffLoadDashboardOverview = function () {
    api("dashboard_overview").then((data) => {
      const el = (id) => document.getElementById(id);
      if (!data || data.status !== "ok") {
        const tb = el("ffPerApEspTable");
        if (tb)
          tb.innerHTML =
            '<tr><td colspan="6" class="text-danger text-center py-3">Dashboard overview failed to load.</td></tr>';
        const rs = el("ffRecentSessions");
        if (rs)
          rs.innerHTML =
            '<tr><td colspan="4" class="text-danger text-center">Failed to load sessions</td></tr>';
        return;
      }
      const k = data.kpis || {};
      if (el("sysSalesToday")) el("sysSalesToday").innerText = peso(k.sales_today);
      if (el("sysSalesMonth")) el("sysSalesMonth").innerText = peso(k.sales_month);
      if (el("sysSalesWeek")) el("sysSalesWeek").innerText = peso(k.sales_week);
      if (el("connectedCount")) el("connectedCount").innerText = k.connected ?? 0;
      if (el("totalClients")) el("totalClients").innerText = k.sessions ?? 0;
      if (el("sysUptime") && data.ruijie) el("sysUptime").innerText = fmtUptime(data.ruijie.uptime);

      const tb = el("ffPerApEspTable");
      if (tb) {
        const rows = asArr(data.per_ap_esp);
        const tot = data.totals || {};
        if (!rows.length) {
          tb.innerHTML =
            '<tr><td colspan="6" class="text-muted text-center py-3">No Access Points yet. Add a LAN AP or wait for built-in radios to seed.</td></tr>';
        } else {
          tb.innerHTML =
            rows
              .map(
                (r) => `<tr>
              <td>${esc(r.ap_name)}${r.ap_kind === "builtin" ? ' <span class="badge bg-info">built-in</span>' : ""}</td>
              <td>${esc(r.esp_name)}</td>
              <td>${r.connected || 0}</td>
              <td>${r.waiting || 0}</td>
              <td>${r.sessions || 0}</td>
              <td>${peso(r.sales)}</td>
            </tr>`
              )
              .join("") +
            `<tr class="table-light fw-bold">
              <td colspan="2">Total</td>
              <td>${tot.connected || 0}</td>
              <td>${tot.waiting || 0}</td>
              <td>${tot.sessions || 0}</td>
              <td>${peso(tot.sales)}</td>
            </tr>`;
        }
      }

      const ns = data.network_status || {};
      const list = el("ffNetStatusList");
      if (list) {
        const items = [
          ["Internet", ns.internet],
          ["Ruijie Router", ns.ruijie],
          ["Wi‑Fi", ns.wifi],
          ["Access Points", ns.access_points],
        ];
        list.innerHTML = items
          .map(
            ([label, val]) =>
              `<div class="ff-status-row"><span>${esc(label)}</span>${statusBadge(val)}</div>`
          )
          .join("");
      }
      if (el("ffNetLatency"))
        el("ffNetLatency").textContent =
          ns.latency_ms != null ? ns.latency_ms + " ms" : "—";
      if (el("ffNetLoss"))
        el("ffNetLoss").textContent =
          ns.packet_loss != null ? ns.packet_loss + "%" : "—";

      const rj = data.ruijie || {};
      const badge = el("ffRjBadge");
      if (badge) {
        badge.textContent = rj.connection || "connected";
        badge.className =
          "badge " + (rj.connection === "connected" ? "bg-success" : "bg-secondary");
      }
      const mark = el("ffRjMark");
      if (mark) mark.className = "ff-rj-mark " + (rj.connection === "connected" ? "live" : "off");
      const facts = el("ffRjFacts");
      if (facts) {
        facts.innerHTML = [
          ["Model", rj.model || "RG-EW1200G Pro"],
          ["OpenWrt", rj.firmware || "—"],
          ["KonekSik-Fi", rj.fastfi_version || "—"],
          ["Uptime", fmtUptime(rj.uptime)],
          ["CPU", (rj.cpu ?? 0) + "%"],
          ["Memory", (rj.memory ?? 0) + "%"],
        ]
          .map((x) => `<div><span>${esc(x[0])}</span><strong>${esc(x[1])}</strong></div>`)
          .join("");
      }
      const sto = el("ffRjStorage");
      if (sto) {
        const slices = asArr(rj.storageSlices);
        const total = Number(rj.storageTotalMb) || 0;
        const used = slices.reduce((a, s) => a + (Number(s.mb) || 0), 0);
        const pct = total > 0 ? Math.min(100, Math.round((used / total) * 100)) : 0;
        sto.innerHTML = `
          <div class="d-flex justify-content-between small mb-1"><strong>Storage</strong><span>${used.toFixed(1)} / ${total.toFixed(1)} MB (${pct}%)</span></div>
          <div class="ff-sto-bar">${slices
            .map((s) => {
              const w = total > 0 ? Math.max(2, (Number(s.mb) / total) * 100) : 0;
              return `<span style="width:${w}%;background:${esc(s.color || "#64748b")}" title="${esc(s.label)}: ${Number(s.mb).toFixed(1)} MB"></span>`;
            })
            .join("")}</div>
          <div class="ff-sto-legend">${slices
            .map(
              (s) =>
                `<span><i style="background:${esc(s.color || "#64748b")}"></i>${esc(s.label)}</span>`
            )
            .join("")}</div>`;
      }

      const rs = el("ffRecentSessions");
      if (rs) {
        const recent = asArr(data.recent_sessions);
        rs.innerHTML = recent.length
          ? recent
              .map(
                (s) => `<tr>
              <td class="font-monospace small">${esc(s.mac)}</td>
              <td>${fmtRemain(s.remaining)}</td>
              <td>${statusBadge(s.status)}</td>
              <td>${s.sub_vendo_id || "—"}</td>
            </tr>`
              )
              .join("")
          : '<tr><td colspan="4" class="text-muted text-center">No sessions</td></tr>';
      }

      const cu = el("ffConnectedUsersDash");
      if (cu) {
        const users = asArr(data.connected_users);
        cu.innerHTML = users.length
          ? users
              .map((u) => {
                const rem = u.session ? fmtRemain(u.session.remaining) : "—";
                return `<tr>
              <td>${esc(u.hostname || "Device")}</td>
              <td class="font-monospace small">${esc(u.ip || "—")}</td>
              <td class="font-monospace small">${esc(u.mac)}</td>
              <td>${rem}</td>
              <td>${statusBadge(u.status)}</td>
              <td class="text-nowrap">
                <button class="btn btn-link btn-sm p-0" onclick="showDevices()">View</button>
              </td>
            </tr>`;
              })
              .join("")
          : '<tr><td colspan="6" class="text-muted text-center">No authenticated users online</td></tr>';
      }

      if (typeof hydrateIcons === "function") hydrateIcons();
    }).catch((err) => {
      const tb = document.getElementById("ffPerApEspTable");
      if (tb)
        tb.innerHTML =
          '<tr><td colspan="6" class="text-danger text-center py-3">Dashboard overview error: ' +
          esc(err && err.message ? err.message : err) +
          "</td></tr>";
    });
  };

  const _loadSystemStatus = window.loadSystemStatus;
  window.loadSystemStatus = function () {
    if (typeof _loadSystemStatus === "function") _loadSystemStatus();
    ffLoadDashboardOverview();
  };

  const _showDashboard = window.showDashboard;
  window.showDashboard = function () {
    if (typeof _showDashboard === "function") _showDashboard();
    ffLoadDashboardOverview();
  };

  // ---- Access Points ----
  let _ffApCache = [];
  let _ffEspCache = [];

  window.ffLoadAccessPoints = function () {
    Promise.all([api("list_access_points"), api("list_esp_devices")])
      .then(([apData, espData]) => {
        _ffApCache = apData.data || [];
        _ffEspCache = espData.esp_devices || espData.data || espData.devices || [];
        const tb = document.getElementById("ffApTable");
        if (tb) {
          if (!_ffApCache.length) {
            tb.innerHTML = '<tr><td colspan="7" class="text-muted text-center">No APs</td></tr>';
          } else {
            tb.innerHTML = _ffApCache
              .map((a) => {
                const espNames = asArr(a.esp).map((e) => e.name).join(", ") || "—";
                const macIp = [a.mac, a.ip].filter(Boolean).join(" / ") || (a.iface || "—");
                const delBtn =
                  a.kind === "builtin"
                    ? ""
                    : `<button class="btn btn-sm btn-outline-danger" onclick="ffDeleteAp(${a.id})">Delete</button>`;
                return `<tr>
                  <td>${esc(a.name)}</td>
                  <td>${a.kind === "builtin" ? '<span class="badge bg-info">built-in</span>' : '<span class="badge bg-secondary">LAN</span>'}</td>
                  <td class="font-monospace small">${esc(macIp)}</td>
                  <td>${esc(a.location || "—")}</td>
                  <td>${statusBadge(a.status)}</td>
                  <td class="small">${esc(espNames)}</td>
                  <td class="text-nowrap">
                    <button class="btn btn-sm btn-outline-secondary" onclick='ffOpenApModal(${JSON.stringify(a).replace(/'/g, "&#39;")})'>Edit</button>
                    ${delBtn}
                  </td>
                </tr>`;
              })
              .join("");
          }
        }
        const espSel = document.getElementById("ffBindEsp");
        const apSel = document.getElementById("ffBindAp");
        if (espSel) {
          const esps = Array.isArray(_ffEspCache) ? _ffEspCache : [];
          espSel.innerHTML = esps.length
            ? esps
                .map((e) => {
                  const id = e.id ?? e.slot_id;
                  const name = e.slot_name || e.name || "ESP #" + id;
                  return `<option value="${id}">${esc(name)} (AP ${e.ap_id || 0})</option>`;
                })
                .join("")
            : '<option value="">No ESP devices</option>';
        }
        if (apSel) {
          apSel.innerHTML = _ffApCache
            .map((a) => `<option value="${a.id}">${esc(a.name)}</option>`)
            .join("");
        }
        ffRenderBindSuggestions();
      })
      .catch(() => toast("Failed to load Access Points", "error"));
  };

  function ffEspId(e) {
    return Number(e.id ?? e.slot_id ?? 0);
  }
  function ffEspName(e) {
    return e.slot_name || e.name || "ESP #" + ffEspId(e);
  }
  function ffApHasEsp(ap) {
    return Array.isArray(ap.esp) && ap.esp.length > 0;
  }

  /** Build optional pairing tips — never auto-binds. */
  window.ffComputeBindSuggestions = function () {
    const aps = (_ffApCache || []).slice().sort((a, b) => {
      // Prefer built-in first, then by id
      if (a.kind === "builtin" && b.kind !== "builtin") return -1;
      if (b.kind === "builtin" && a.kind !== "builtin") return 1;
      return (a.id || 0) - (b.id || 0);
    });
    const esps = (Array.isArray(_ffEspCache) ? _ffEspCache : []).slice();
    const unbound = esps.filter((e) => !Number(e.ap_id || 0));
    const needAp = aps.filter((a) => !ffApHasEsp(a));
    const suggestions = [];
    const n = Math.min(unbound.length, needAp.length);
    for (let i = 0; i < n; i++) {
      const esp = unbound[i];
      const ap = needAp[i];
      suggestions.push({
        esp_id: ffEspId(esp),
        esp_name: ffEspName(esp),
        ap_id: ap.id,
        ap_name: ap.name,
        reason:
          ap.kind === "builtin"
            ? "Main / built-in radio has no ESP yet — good default for the counter coinslot"
            : "This LAN AP has no ESP yet — typical for a remote location coinslot",
      });
    }
    return suggestions;
  };

  window.ffRenderBindSuggestions = function () {
    const host = document.getElementById("ffBindSuggestList");
    if (!host) return;
    const suggestions = ffComputeBindSuggestions();
    if (!suggestions.length) {
      const unbound = (Array.isArray(_ffEspCache) ? _ffEspCache : []).filter((e) => !Number(e.ap_id || 0));
      const needAp = (_ffApCache || []).filter((a) => !ffApHasEsp(a));
      if (!(_ffApCache || []).length || !(Array.isArray(_ffEspCache) && _ffEspCache.length)) {
        host.innerHTML = '<p class="text-muted mb-0">Add APs and ESP devices first — suggestions appear when both exist.</p>';
      } else if (!unbound.length && !needAp.length) {
        host.innerHTML = '<p class="text-success mb-0">No gaps detected — every AP that we checked already has an ESP, or every ESP is already bound. You can still change binds manually below.</p>';
      } else if (!unbound.length) {
        host.innerHTML = '<p class="text-muted mb-0">All ESPs are already bound. Unbind one below if you want to reassign, or ignore this panel.</p>';
      } else {
        host.innerHTML = '<p class="text-muted mb-0">Unbound ESPs exist, but every AP already has at least one ESP. Extra ESPs can stay unbound or you can bind manually below.</p>';
      }
      return;
    }
    host.innerHTML =
      '<ul class="list-unstyled mb-0">' +
      suggestions
        .map(
          (s, idx) => `<li class="d-flex flex-wrap align-items-start justify-content-between gap-2 py-2 ${idx ? "border-top" : ""}" style="border-color:var(--border-subtle)!important;">
          <div>
            <div><strong>${esc(s.esp_name)}</strong> → <strong>${esc(s.ap_name)}</strong></div>
            <div class="text-muted" style="font-size:12px;">${esc(s.reason)}</div>
          </div>
          <button type="button" class="btn btn-outline-primary btn-sm flex-shrink-0"
            onclick="ffUseBindSuggestion(${s.esp_id},${s.ap_id})"
            title="Only fills the dropdowns — does not bind until you click Bind">
            Use in form
          </button>
        </li>`
        )
        .join("") +
      "</ul>" +
      '<p class="text-muted mb-0 mt-2" style="font-size:11.5px;">“Use in form” only pre-selects the dropdowns. Nothing is saved until you click <strong>Bind</strong>.</p>';
  };

  /** Prefill bind dropdowns only — owner must still click Bind. */
  window.ffUseBindSuggestion = function (esp_id, ap_id) {
    const espSel = document.getElementById("ffBindEsp");
    const apSel = document.getElementById("ffBindAp");
    if (espSel) espSel.value = String(esp_id);
    if (apSel) apSel.value = String(ap_id);
    toast("Suggestion loaded into the form — click Bind if you agree", "info");
    // Scroll bind card into view
    document.getElementById("ffBindEsp")?.closest(".card")?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  };

  window.ffOpenApModal = function (ap) {
    const modal = document.getElementById("ffApModal");
    if (!modal) return;
    document.getElementById("ffApModalTitle").textContent = ap && ap.id ? "Edit Access Point" : "Add LAN AP";
    document.getElementById("ffApId").value = ap && ap.id ? ap.id : "";
    document.getElementById("ffApName").value = (ap && ap.name) || "";
    document.getElementById("ffApMac").value = (ap && ap.mac) || "";
    document.getElementById("ffApIp").value = (ap && ap.ip) || "";
    document.getElementById("ffApLoc").value = (ap && ap.location) || "";
    document.getElementById("ffApNotes").value = (ap && ap.notes) || "";
    modal.style.display = "flex";
    modal.classList.add("show");
  };
  window.ffCloseApModal = function () {
    const modal = document.getElementById("ffApModal");
    if (!modal) return;
    modal.style.display = "none";
    modal.classList.remove("show");
  };
  window.ffSaveAp = function () {
    const body = {
      id: document.getElementById("ffApId").value || undefined,
      name: document.getElementById("ffApName").value,
      mac: document.getElementById("ffApMac").value,
      ip: document.getElementById("ffApIp").value,
      location: document.getElementById("ffApLoc").value,
      notes: document.getElementById("ffApNotes").value,
      kind: "lan",
    };
    api("save_access_point", { method: "POST", body }).then((d) => {
      if (d.status === "ok") {
        toast("Access Point saved", "success");
        ffCloseApModal();
        ffLoadAccessPoints();
      } else toast(d.message || "Save failed", "error");
    });
  };
  window.ffDeleteAp = function (id) {
    ffConfirm("Delete this LAN Access Point?", {
      title: "Delete Access Point",
      okText: "Delete",
      onConfirm: function () {
        api("delete_access_point", { method: "POST", body: { id } }).then((d) => {
          if (d.status === "ok") {
            toast("Deleted", "success");
            ffLoadAccessPoints();
          } else toast(d.message || "Delete failed", "error");
        });
      },
    });
  };
  window.ffBindEspAp = function (forceUnbind) {
    const esp_id = Number(document.getElementById("ffBindEsp")?.value || 0);
    const ap_id = forceUnbind === 0 ? 0 : Number(document.getElementById("ffBindAp")?.value || 0);
    if (!esp_id) {
      toast("Select an ESP", "warning");
      return;
    }
    api("bind_esp_to_ap", { method: "POST", body: { esp_id, ap_id } }).then((d) => {
      if (d.status === "ok") {
        toast(ap_id ? "ESP bound" : "ESP unbound", "success");
        ffLoadAccessPoints();
      } else toast(d.message || "Bind failed", "error");
    });
  };

  // Settings should no longer own audio previews (moved to Captive Portal)
  const _showSettings = window.showSettings;
  window.showSettings = function () {
    if (typeof hideAll === "function") hideAll();
    document.getElementById("settingsSection")?.classList.remove("hidden");
    if (typeof loadLicenseStatus === "function") loadLicenseStatus();
    if (typeof loadPauseLimit === "function") loadPauseLimit();
    if (typeof loadAutopauseConfig === "function") loadAutopauseConfig();
    if (typeof loadTetheringConfig === "function") loadTetheringConfig();
    if (typeof loadValidityConfig === "function") loadValidityConfig();
    if (typeof loadDataAllocationConfig === "function") loadDataAllocationConfig();
    if (typeof loadHideInsertConfig === "function") loadHideInsertConfig();
    if (typeof loadBuyDataConfig === "function") loadBuyDataConfig();
    if (typeof loadWipassConfig === "function") loadWipassConfig();
    if (typeof loadCoinslotSettings === "function") loadCoinslotSettings();
    if (typeof setHash === "function") setHash("settings");
    if (typeof closeSidebarMobile === "function") closeSidebarMobile();
    ffLoadBranding();
  };

  // ---- Modern modal helpers (no native alert/confirm/prompt) ----
  function ffShowOverlay(id) {
    const modal = document.getElementById(id);
    if (!modal) return;
    modal.style.display = "flex";
    modal.classList.add("show");
  }
  function ffHideOverlay(id) {
    const modal = document.getElementById(id);
    if (!modal) return;
    modal.style.display = "none";
    modal.classList.remove("show");
  }
  let _ffAlertCb = null;
  window.ffCloseAlert = function () {
    const cb = _ffAlertCb;
    _ffAlertCb = null;
    ffHideOverlay("ffAlertModal");
    if (cb) cb();
  };
  window.ffAlert = function (message, opts) {
    opts = opts || {};
    document.getElementById("ffAlertTitle").textContent = opts.title || "Notice";
    document.getElementById("ffAlertMsg").textContent = message || "";
    const ok = document.getElementById("ffAlertOk");
    ok.textContent = opts.okText || "OK";
    ok.className = opts.okClass || "btn btn-primary btn-sm";
    _ffAlertCb = typeof opts.onOk === "function" ? opts.onOk : null;
    ffShowOverlay("ffAlertModal");
  };
  let _ffConfirmCb = null;
  window.ffCloseConfirm = function () {
    _ffConfirmCb = null;
    ffHideOverlay("ffConfirmModal");
  };
  window.ffConfirm = function (message, opts) {
    opts = opts || {};
    const title = opts.title || "Confirm";
    const okText = opts.okText || "Confirm";
    const okClass = opts.okClass || "btn btn-danger btn-sm";
    const cancelText = opts.cancelText || "Cancel";
    document.getElementById("ffConfirmTitle").textContent = title;
    document.getElementById("ffConfirmMsg").textContent = message || "";
    const cancel = document.getElementById("ffConfirmCancel");
    if (cancel) cancel.textContent = cancelText;
    const ok = document.getElementById("ffConfirmOk");
    ok.textContent = okText;
    ok.className = okClass;
    _ffConfirmCb = typeof opts.onConfirm === "function" ? opts.onConfirm : null;
    ok.onclick = function () {
      const cb = _ffConfirmCb;
      ffCloseConfirm();
      if (cb) cb();
    };
    ffShowOverlay("ffConfirmModal");
  };
  let _ffPromptCb = null;
  window.ffClosePrompt = function () {
    _ffPromptCb = null;
    ffHideOverlay("ffPromptModal");
  };
  window.ffPromptFields = function (cfg) {
    cfg = cfg || {};
    document.getElementById("ffPromptTitle").textContent = cfg.title || "Input";
    document.getElementById("ffPromptLabel1").textContent = cfg.label1 || "Value";
    const i1 = document.getElementById("ffPromptInput1");
    i1.value = cfg.value1 || "";
    i1.placeholder = cfg.placeholder1 || "";
    const row2 = document.getElementById("ffPromptRow2");
    const i2 = document.getElementById("ffPromptInput2");
    const row3 = document.getElementById("ffPromptRow3");
    const i3 = document.getElementById("ffPromptInput3");
    if (cfg.label2) {
      row2.style.display = "";
      document.getElementById("ffPromptLabel2").textContent = cfg.label2;
      i2.value = cfg.value2 || "";
      i2.placeholder = cfg.placeholder2 || "";
    } else {
      row2.style.display = "none";
      i2.value = "";
    }
    if (row3 && i3) {
      if (cfg.label3) {
        row3.style.display = "";
        document.getElementById("ffPromptLabel3").textContent = cfg.label3;
        i3.value = cfg.value3 || "";
        i3.placeholder = cfg.placeholder3 || "";
      } else {
        row3.style.display = "none";
        i3.value = "";
      }
    }
    _ffPromptCb = typeof cfg.onOk === "function" ? cfg.onOk : null;
    document.getElementById("ffPromptOk").onclick = function () {
      const v1 = i1.value.trim();
      const v2 = i2.value.trim();
      const v3 = i3 ? i3.value.trim() : "";
      const cb = _ffPromptCb;
      if (cfg.require1 !== false && !v1) {
        toast(cfg.emptyMsg || "Please fill in the required field", "warning");
        return;
      }
      if (cfg.require2 && !v2) {
        toast(cfg.emptyMsg2 || "Please fill in all required fields", "warning");
        return;
      }
      ffClosePrompt();
      if (cb) cb(v1, v2, v3);
    };
    ffShowOverlay("ffPromptModal");
    setTimeout(() => i1.focus(), 50);
  };

  // Block leftover native dialogs — always use modern popups
  window.alert = function (msg) {
    if (typeof window.ffAlert === "function") window.ffAlert(String(msg || ""), { title: "Notice" });
  };
  window.confirm = function (msg) {
    console.warn("[KonekSik-Fi] Native confirm blocked — use ffConfirm()", msg);
    if (typeof window.ffConfirm === "function") {
      window.ffConfirm(String(msg || ""), {
        title: "Confirm",
        okText: "OK",
        okClass: "btn btn-primary btn-sm",
        onConfirm: function () {},
      });
    }
    return false;
  };
  window.prompt = function (msg, def) {
    console.warn("[KonekSik-Fi] Native prompt blocked — use ffPromptFields()", msg);
    if (typeof window.ffPromptFields === "function") {
      window.ffPromptFields({
        title: "Input",
        label1: String(msg || "Value"),
        value1: def != null ? String(def) : "",
        onOk: function () {},
      });
    }
    return null;
  };

  // ---- Plans ----
  let _ffProfileCache = [];
  
  

  function ffFillProfileSelect(sel, selectedId) {
    if (!sel) return;
    const opts = ['<option value="0">None</option>'].concat(
      _ffProfileCache.map((p) => `<option value="${p.id}">${esc(p.name)}</option>`)
    );
    sel.innerHTML = opts.join("");
    sel.value = String(selectedId ?? 0);
  }
// ---- Profiles / Bandwidth (KonekSik-style cards) ----
  let _ffTrafficChart = null;
  function kbpsToMbps(k) {
    return Math.round(((Number(k) || 0) / 1024) * 10) / 10;
  }
  function ffBandLabel(band) {
    const b = String(band || "auto").toLowerCase();
    if (b === "2.4" || b === "2.4ghz") return "2.4 GHz";
    if (b === "5" || b === "5ghz") return "5 GHz";
    return "Auto";
  }
  function ffNormBand(band) {
    const b = String(band || "auto").toLowerCase().replace(/\s+/g, "");
    if (b === "2.4" || b === "2.4ghz" || b === "24" || b === "2g") return "2.4";
    if (b === "5" || b === "5ghz" || b === "5g") return "5";
    return "auto";
  }
  window.ffLoadProfiles = function () {
    api("list_profiles").then((data) => {
      const host = document.getElementById("ffBandwidthCards");
      const rows = data.profiles || data.data || [];
      _ffProfileCache = rows;
      if (host) {
        host.innerHTML = rows.length
          ? rows
              .map((p) => {
                const active = Number(p.enabled) !== 0;
                const band = ffNormBand(p.band);
                return `<div class="col-md-4"><div class="ff-bw-card">
              <div class="ff-bw-h"><h5>${esc(p.name)}</h5>
                <span class="badge ${active ? "bg-success" : "bg-secondary"}">${active ? "• Active" : "Disabled"}</span></div>
              <div class="ff-bw-metrics">
                <div><dt>Download</dt><dd>${kbpsToMbps(p.down_kbps)} Mbps</dd></div>
                <div><dt>Upload</dt><dd>${kbpsToMbps(p.up_kbps)} Mbps</dd></div>
                <div><dt>Band</dt><dd>${esc(ffBandLabel(band))}</dd></div>
              </div>
              <div class="d-flex gap-2 mt-3 flex-wrap">
                <button class="btn btn-sm btn-outline-secondary" onclick='ffOpenProfileModal(${JSON.stringify(p).replace(/'/g, "&#39;")})'>Edit</button>
                <button class="btn btn-sm btn-outline-secondary" onclick="ffToggleProfile(${p.id},${active ? 0 : 1},'${escAttr(p.name)}',${p.down_kbps},${p.up_kbps},'${band}')">${active ? "Disable" : "Enable"}</button>
                <button class="btn btn-sm btn-outline-danger" onclick="ffDeleteProfile(${p.id})">Delete</button>
              </div>
            </div></div>`;
              })
              .join("")
          : '<div class="col-12 text-muted">No profiles yet. Click Add Profile.</div>';
      }
      ffRenderTrafficChart();
    });
  };

  window.ffFillVoucherProfiles = function () {
    const sel = document.getElementById("voucherProfile");
    return api("list_profiles").then((data) => {
      const rows = (data.profiles || data.data || []).filter((p) => Number(p.enabled) !== 0);
      if (!sel) return rows;
      if (!rows.length) {
        sel.innerHTML = '<option value="">No profile plans yet</option>';
        return rows;
      }
      sel.innerHTML =
        '<option value="">Select a speed profile</option>' +
        rows
          .map((p) => {
            const dl = kbpsToMbps(p.down_kbps != null ? p.down_kbps : p.download_kbps);
            const ul = kbpsToMbps(p.up_kbps != null ? p.up_kbps : p.upload_kbps);
            return `<option value="${p.id}">${esc(p.name)} — ${dl} Mbps down / ${ul} Mbps up</option>`;
          })
          .join("");
      return rows;
    });
  };

  window.ffOpenGenerateVouchers = function () {
    const modal = document.getElementById("modalGenerateVouchers");
    if (modal) modal.classList.add("show");
    if (typeof updateVoucherDurationPreview === "function") updateVoucherDurationPreview();
    ffFillVoucherProfiles();
  };

  const _ffOrigGenerateVouchers = window.generateVouchers;
  window.generateVouchers = function () {
    const sel = document.getElementById("voucherProfile");
    const profileId = Number(sel && sel.value) || 0;
    if (!profileId) {
      ffConfirm("Generate a profile plan first.", {
        title: "Speed profile required",
        okText: "OK",
        okClass: "btn btn-primary btn-sm",
        cancelText: "Close",
      });
      return;
    }
    const origFetch = window.fetch;
    window.fetch = function (url, opts) {
      window.fetch = origFetch;
      if (typeof url === "string" && url.indexOf("action=generate_vouchers") !== -1 && url.indexOf("profile_id=") === -1) {
        url += "&profile_id=" + encodeURIComponent(String(profileId));
      }
      return origFetch.call(this, url, opts);
    };
    try {
      if (typeof _ffOrigGenerateVouchers === "function") return _ffOrigGenerateVouchers();
    } finally {
      window.fetch = origFetch;
    }
  };

  window.ffToggleProfile = function (id, enabled, name, down_kbps, up_kbps, band) {
    api("save_profile", {
      method: "POST",
      body: { id, name, down_kbps, up_kbps, enabled, band: ffNormBand(band) },
    }).then(() => ffLoadProfiles());
  };

  window.ffOpenProfileModal = function (existing) {
    document.getElementById("ffProfileModalTitle").textContent = existing?.id ? "Edit Profile" : "Add Profile";
    document.getElementById("ffProfileId").value = existing?.id || "";
    document.getElementById("ffProfileEnabled").value = existing?.enabled ?? 1;
    document.getElementById("ffProfileName").value = existing?.name || "";
    document.getElementById("ffProfileDown").value = existing ? kbpsToMbps(existing.down_kbps) : 10;
    document.getElementById("ffProfileUp").value = existing ? kbpsToMbps(existing.up_kbps) : 5;
    const bandEl = document.getElementById("ffProfileBand");
    if (bandEl) bandEl.value = ffNormBand(existing?.band);
    ffShowOverlay("ffProfileModal");
    setTimeout(() => document.getElementById("ffProfileName")?.focus(), 50);
  };
  window.ffCloseProfileModal = function () {
    ffHideOverlay("ffProfileModal");
  };
  window.ffSaveProfile = function () {
    const name = document.getElementById("ffProfileName").value.trim();
    if (!name) {
      toast("Profile name is required", "warning");
      return;
    }
    const down_mbps = Number(document.getElementById("ffProfileDown").value || 0);
    const up_mbps = Number(document.getElementById("ffProfileUp").value || 0);
    const band = ffNormBand(document.getElementById("ffProfileBand")?.value);
    api("save_profile", {
      method: "POST",
      body: {
        id: document.getElementById("ffProfileId").value || undefined,
        name,
        down_kbps: Math.round(down_mbps * 1024),
        up_kbps: Math.round(up_mbps * 1024),
        enabled: Number(document.getElementById("ffProfileEnabled").value || 1),
        band,
      },
    }).then((d) => {
      toast(d.status === "ok" ? "Saved" : d.message, d.status === "ok" ? "success" : "error");
      if (d.status === "ok") {
        ffCloseProfileModal();
        ffLoadProfiles();
      }
    });
  };

  window.ffDeleteProfile = function (id) {
    ffConfirm("Delete this bandwidth profile?", {
      title: "Delete Profile",
      okText: "Delete",
      onConfirm: function () {
        api("delete_profile", { method: "POST", body: { id } }).then(() => ffLoadProfiles());
      },
    });
  };

  function ffRenderTrafficChart() {
    const canvas = document.getElementById("ffTrafficChart");
    const label = document.getElementById("ffTrafficLiveLabel");
    if (!canvas || typeof Chart === "undefined") return;
    const down = [12, 28, 45, 62, 86, 71, 54, 66, 80, 74, 58, 42];
    const up = [4, 8, 11, 9, 13, 12, 10, 14, 12, 11, 9, 7];
    const lastD = down[down.length - 1];
    const lastU = up[up.length - 1];
    if (label) label.textContent = `Download ${lastD} Mbps · Upload ${lastU} Mbps`;
    if (_ffTrafficChart) {
      _ffTrafficChart.destroy();
      _ffTrafficChart = null;
    }
    _ffTrafficChart = new Chart(canvas.getContext("2d"), {
      type: "line",
      data: {
        labels: down.map((_, i) => i + 1),
        datasets: [
          { label: "Download", data: down, borderColor: "#2563eb", tension: 0.35, fill: false, pointRadius: 0 },
          { label: "Upload", data: up, borderColor: "#0ea5e9", tension: 0.35, fill: false, pointRadius: 0 },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { display: false } },
        scales: { x: { display: false }, y: { beginAtZero: true, ticks: { maxTicksLimit: 5 } } },
      },
    });
  }
// ---- Devices / blocks ----
  window.ffLoadDevices = function () {
    api("list_devices").then((data) => {
      const tb = document.getElementById("ffDevicesTable");
      if (!tb) return;
      const rows = data.data || [];
      tb.innerHTML = rows.length
        ? rows
            .map(
              (d) => `<tr>
          <td>${esc(d.hostname || "—")}</td><td class="font-monospace small">${esc(d.mac)}</td>
          <td>${esc(d.ip || "—")}</td><td>${esc(d.status)} / ${esc(d.auth)}</td>
          <td>${esc(d.radio || "—")} ${esc(d.signal || "")}</td>
          <td class="text-nowrap">
            ${d.blocked ? `<button class="btn btn-sm btn-success" onclick="ffUnblockMac('${d.mac}')">Unblock</button>` : `<button class="btn btn-sm btn-danger" onclick="ffBlockMac('${d.mac}')">Block</button>`}
          </td></tr>`
            )
            .join("")
        : '<tr><td colspan="6" class="text-muted">No devices</td></tr>';
    });
  };

  window.ffLoadBlocks = function () {
    api("list_mac_blocks").then((data) => {
      const tb = document.getElementById("ffBlockTable");
      if (!tb) return;
      tb.innerHTML = (data.data || [])
        .map(
          (b) =>
            `<tr><td class="font-monospace">${esc(b.mac)}</td><td>${esc(b.reason)}</td>
        <td><button class="btn btn-sm btn-outline-secondary" onclick="ffUnblockMac(${b.id})">Remove</button></td></tr>`
        )
        .join("");
    });
  };

  window.ffBlockMac = function (mac) {
    mac = mac || document.getElementById("ffBlockMac")?.value;
    if (!mac) return toast("MAC required", "warning");
    const reasonEl = document.getElementById("ffBlockReason");
    const doBlock = (reason) => {
      api("block_mac", { method: "POST", body: { mac, reason: reason || "Manual block" } }).then((d) => {
        toast(d.status === "ok" ? "Blocked" : d.message, d.status === "ok" ? "success" : "error");
        ffLoadDevices();
        ffLoadBlocks();
      });
    };
    if (reasonEl && reasonEl.value.trim()) return doBlock(reasonEl.value.trim());
    ffPromptFields({
      title: "Block MAC",
      label1: "Reason",
      value1: "Manual block",
      require1: false,
      onOk: function (reason) {
        doBlock(reason || "Manual block");
      },
    });
  };

  window.ffUnblockMac = function (idOrMac) {
    const body = typeof idOrMac === "number" ? { id: idOrMac } : { mac: idOrMac };
    api("unblock_mac", { method: "POST", body }).then(() => {
      ffLoadDevices();
      ffLoadBlocks();
    });
  };

  window.ffLoadWaiting = function () {
    api("waiting_queue").then((data) => {
      const tb = document.getElementById("ffWaitingTable");
      if (!tb) return;
      const rows = data.data || [];
      tb.innerHTML = rows.length
        ? rows
            .map(
              (d) =>
                `<tr><td>${esc(d.hostname || "—")}</td><td class="font-monospace">${esc(d.mac)}</td><td>${esc(d.ip || "")}</td><td>${esc(d.radio || "")}</td></tr>`
            )
            .join("")
        : '<tr><td colspan="4" class="text-muted">Queue empty</td></tr>';
    });
  };

  // ---- Radio (built-in Ruijie radios via iwinfo — not LAN APs) ----
  window.ffLoadRadios = function () {
    api("radio_status").then((data) => {
      const host = document.getElementById("ffRadioCards");
      const hero = document.getElementById("ffRadioHero");
      if (!host) return;
      const rows = data.data || [];
      if (!rows.length) {
        if (hero) hero.innerHTML = "";
        host.innerHTML =
          '<div class="col-12"><div class="ff-radio-note mb-0">No built-in radios detected. On a live Ruijie this uses <code>iwinfo</code>. LAN APs appear under Access Points.</div></div>';
        return;
      }
      const totalClients = rows.reduce((s, r) => s + (Number(r.clients) || 0), 0);
      const bands = Array.from(new Set(rows.map((r) => r.band).filter(Boolean)));
      if (hero) {
        hero.innerHTML = `
          <div class="ff-radio-hero-card">
            <p class="label">Radios</p>
            <p class="value">${rows.length}</p>
            <p class="hint">On this Ruijie</p>
          </div>
          <div class="ff-radio-hero-card">
            <p class="label">Clients</p>
            <p class="value">${totalClients}</p>
            <p class="hint">Associated now</p>
          </div>
          <div class="ff-radio-hero-card">
            <p class="label">Bands</p>
            <p class="value" style="font-size:1.05rem">${esc(bands.join(" · ") || "—")}</p>
            <p class="hint">Built-in Wi‑Fi</p>
          </div>`;
      }
      host.innerHTML = rows
        .map((r) => {
          const band = String(r.band || "");
          let badgeClass = "band-other";
          if (band.indexOf("2.4") !== -1) badgeClass = "band-24";
          else if (band.indexOf("5") !== -1) badgeClass = "band-5";
          const bandLabel = band || "Radio";
          return `<div class="col-md-6 col-xl-4">
            <div class="ff-radio-card">
              <div class="ff-radio-card-top">
                <div>
                  <p class="ff-radio-iface">${esc(r.iface)}</p>
                  <p class="ff-radio-ssid">${esc(r.ssid || "No SSID")}</p>
                </div>
                <span class="ff-radio-badge ${badgeClass}">${esc(bandLabel)}</span>
              </div>
              <dl class="ff-radio-metrics">
                <div class="ff-radio-metric"><dt>Channel</dt><dd>${esc(r.channel || "—")}</dd></div>
                <div class="ff-radio-metric"><dt>Clients</dt><dd>${Number(r.clients) || 0}</dd></div>
                <div class="ff-radio-metric"><dt>Tx power</dt><dd>${esc(r.txpower ? r.txpower + " dBm" : "—")}</dd></div>
              </dl>
              <div class="ff-radio-card-actions">
                <button type="button" class="btn btn-sm btn-warning" onclick="ffRestartRadio('${esc(r.iface)}')">Restart radio</button>
              </div>
            </div>
          </div>`;
        })
        .join("");
    });
  };

  window.ffRestartRadio = function (iface) {
    const label = iface ? " (" + iface + ")" : "";
    ffConfirm("Restart Wi‑Fi" + label + "?", {
      title: "Restart Wi‑Fi",
      okText: "Restart",
      okClass: "btn btn-warning btn-sm",
      onConfirm: function () {
        api("radio_restart", { method: "POST", body: { iface: iface || "" } }).then((d) =>
          toast(d.message || "Done", d.status === "ok" ? "success" : "error")
        );
      },
    });
  };

  // ---- Pricing hub ----
  window.ffLoadPricingHub = function () {
    api("pricing_hub").then((data) => {
      const host = document.getElementById("ffPricingHub");
      if (!host) return;
      const rates = (data.rates || [])
        .map((r) => `<li>${peso(r.price)} → ${r.minutes} min</li>`)
        .join("");
      const profiles = (data.profiles || [])
        .map((p) => `<li>${esc(p.name)} — ${p.down_kbps}/${p.up_kbps} Kbps · ${ffBandLabel(p.band)}</li>`)
        .join("");
      host.innerHTML = `
        <div class="col-md-6"><div class="card border-0 shadow-sm"><div class="card-body"><h5>Coin Rates</h5><ul>${rates || "<li class='text-muted'>None</li>"}</ul></div></div></div>
        <div class="col-md-6"><div class="card border-0 shadow-sm"><div class="card-body"><h5>Bandwidth</h5><ul>${profiles || "<li class='text-muted'>None</li>"}</ul></div></div></div>`;
    });
  };

  // ---- Operators ----
  const FF_ROLE_PERM_META = [
    { key: "view_dashboard", label: "View dashboard / sales" },
    { key: "manage_sessions", label: "Manage sessions / devices" },
    { key: "edit_rates", label: "Edit rates / vouchers" },
    { key: "network", label: "Network / Wi‑Fi / APs" },
    { key: "operators", label: "Operators & audit" },
    { key: "ota", label: "OTA / firmware / reboot" },
    { key: "branding", label: "Branding & license" },
  ];
  const FF_ROLE_PERM_DEFAULTS = {
    view_dashboard: { owner: true, admin: true, staff: true, viewer: true },
    manage_sessions: { owner: true, admin: true, staff: true, viewer: false },
    edit_rates: { owner: true, admin: true, staff: true, viewer: false },
    network: { owner: true, admin: true, staff: false, viewer: false },
    operators: { owner: true, admin: false, staff: false, viewer: false },
    ota: { owner: true, admin: true, staff: false, viewer: false },
    branding: { owner: true, admin: true, staff: false, viewer: false },
  };
  let _ffRolePerms = null;

  function ffRenderRolePerms(matrix) {
    const tb = document.getElementById("ffRolePermBody");
    if (!tb) return;
    _ffRolePerms = matrix || FF_ROLE_PERM_DEFAULTS;
    const roles = ["owner", "admin", "staff", "viewer"];
    tb.innerHTML = FF_ROLE_PERM_META.map((p) => {
      const row = _ffRolePerms[p.key] || FF_ROLE_PERM_DEFAULTS[p.key];
      const cells = roles
        .map((role) => {
          const checked = row[role] ? "checked" : "";
          const disabled = role === "owner" ? "disabled" : "";
          return `<td class="text-center"><input type="checkbox" class="form-check-input ff-role-perm" data-perm="${p.key}" data-role="${role}" ${checked} ${disabled}></td>`;
        })
        .join("");
      return `<tr><td>${esc(p.label)}</td>${cells}</tr>`;
    }).join("");
  }

  window.ffLoadRolePerms = function () {
    api("get_role_permissions").then((data) => {
      if (data.status === "ok" && data.data) ffRenderRolePerms(data.data);
      else ffRenderRolePerms(FF_ROLE_PERM_DEFAULTS);
    }).catch(() => ffRenderRolePerms(FF_ROLE_PERM_DEFAULTS));
  };

  window.ffCollectRolePerms = function () {
    const out = JSON.parse(JSON.stringify(FF_ROLE_PERM_DEFAULTS));
    document.querySelectorAll(".ff-role-perm").forEach((el) => {
      const perm = el.getAttribute("data-perm");
      const role = el.getAttribute("data-role");
      if (!out[perm]) out[perm] = { owner: true, admin: false, staff: false, viewer: false };
      out[perm][role] = !!el.checked;
      out[perm].owner = true;
    });
    return out;
  };

  window.ffSaveRolePerms = function () {
    const permissions = ffCollectRolePerms();
    api("set_role_permissions", { method: "POST", body: { permissions } }).then((d) => {
      if (d.status === "ok") {
        toast("Role permissions saved", "success");
        if (d.data) ffRenderRolePerms(d.data);
      } else toast(d.message || "Save failed", "error");
    });
  };

  window.ffResetRolePerms = function () {
    ffConfirm("Reset all role permissions to factory defaults?", {
      title: "Reset permissions",
      okText: "Reset",
      onConfirm: function () {
        ffRenderRolePerms(FF_ROLE_PERM_DEFAULTS);
        api("set_role_permissions", { method: "POST", body: { permissions: FF_ROLE_PERM_DEFAULTS } }).then((d) => {
          toast(d.status === "ok" ? "Defaults restored" : d.message || "Failed", d.status === "ok" ? "success" : "error");
        });
      },
    });
  };

  window.ffLoadUsers = function () {
    api("list_admin_users").then((data) => {
      const tb = document.getElementById("ffUsersTable");
      if (!tb) return;
      if (data.status !== "ok") {
        tb.innerHTML = `<tr><td colspan="3" class="text-muted">${esc(data.message || "Owner only")}</td></tr>`;
        return;
      }
      tb.innerHTML = (data.data || [])
        .map(
          (u) =>
            `<tr><td>${esc(u.username)}</td><td>${esc(u.role)}</td>
        <td><button class="btn btn-sm btn-outline-danger" onclick="ffDeleteUser(${u.id})">Delete</button></td></tr>`
        )
        .join("");
    });
  };

  window.ffCreateUser = function () {
    const username = document.getElementById("ffNewUser")?.value;
    const password = document.getElementById("ffNewPass")?.value;
    const role = document.getElementById("ffNewRole")?.value || "staff";
    api("create_admin_user", { method: "POST", body: { username, password, role } }).then((d) => {
      toast(d.status === "ok" ? "User created" : d.message, d.status === "ok" ? "success" : "error");
      ffLoadUsers();
    });
  };

  window.ffDeleteUser = function (id) {
    ffConfirm("Delete this operator user?", {
      title: "Delete User",
      okText: "Delete",
      onConfirm: function () {
        api("delete_admin_user", { method: "POST", body: { id } }).then(() => ffLoadUsers());
      },
    });
  };

  window.ffLoadAudit = function () {
    api("audit_feed", { query: { limit: 40 } }).then((data) => {
      const el = document.getElementById("ffAuditLog");
      if (!el) return;
      if (data.status !== "ok") {
        el.textContent = data.message || "Owner only";
        return;
      }
      el.textContent = (data.data || [])
        .map((a) => new Date((a.ts || 0) * 1000).toLocaleString() + "  " + a.username + "  " + a.action + "  " + (a.detail || ""))
        .join("\n");
    });
  };

  // ---- Reports / vendo sales ----
  window.ffLoadReport = function (period) {
    api("reports_summary", { query: { period } }).then((data) => {
      const el = document.getElementById("ffReportBody");
      if (!el) return;
      el.innerHTML = `<div class="row g-3">
        <div class="col-md-4"><div class="stat-mini"><div class="stat-mini-label">Period</div><div class="stat-mini-value">${esc(data.period)}</div></div></div>
        <div class="col-md-4"><div class="stat-mini"><div class="stat-mini-label">Sales</div><div class="stat-mini-value">${peso(data.sales_total)}</div></div></div>
        <div class="col-md-4"><div class="stat-mini"><div class="stat-mini-label">Transactions</div><div class="stat-mini-value">${data.sales_count || 0}</div></div></div>
        <div class="col-md-4"><div class="stat-mini"><div class="stat-mini-label">Active sessions</div><div class="stat-mini-value">${data.active_sessions || 0}</div></div></div>
      </div>`;
      window._ffLastReport = data;
    });
  };

  window.ffLoadVendoSales = function () {
    api("sales_by_vendo").then((data) => {
      const tb = document.getElementById("ffVendoSales");
      if (!tb) return;
      tb.innerHTML = (data.data || [])
        .map(
          (r) =>
            `<tr><td>${r.sub_vendo_id === 0 ? "Main / unset" : r.sub_vendo_id}</td><td>${peso(r.amount)}</td><td>${r.count}</td><td>${r.coins || 0}</td></tr>`
        )
        .join("") || '<tr><td colspan="4" class="text-muted">No sales</td></tr>';
    });
  };

  window.ffPrintReport = function () {
    const w = window.open("", "_blank");
    if (!w) return;
    const d = window._ffLastReport || {};
    w.document.write(`<html><head><title>KonekSik-Fi Report</title></head><body>
      <h1>KonekSik-Fi Report</h1><p>Period: ${d.period || ""}</p>
      <p>Sales: ${peso(d.sales_total)} (${d.sales_count || 0} tx)</p>
      <p>Active sessions: ${d.active_sessions || 0}</p>
      <p>Generated: ${new Date().toLocaleString()}</p>
      <script>window.print()<\/script></body></html>`);
    w.document.close();
  };

  // ---- Branding in settings (inject panel once) ----
  window.ffLoadBranding = function () {
    api("get_branding").then((data) => {
      const sideLogo = document.getElementById("ffSidebarLogo");
      const mark = document.getElementById("ffBrandMark");
      const wrap = document.getElementById("ffBrandLogoWrap");
      const cebjSrc = "./image/CEBJ.png";
      if (sideLogo) {
        sideLogo.onload = function () {
          sideLogo.style.display = "block";
          if (mark) mark.style.display = "none";
          if (wrap) wrap.classList.add("has-image");
        };
        sideLogo.onerror = function () {
          sideLogo.style.display = "none";
          if (mark) mark.style.display = "grid";
        };
        if (sideLogo.getAttribute("src") === cebjSrc) {
          sideLogo.dispatchEvent(new Event("load"));
        }
        sideLogo.src = cebjSrc;
      }

      // Never inject nav logo into the theme toggle / header button
      document.getElementById("ffNavLogo")?.remove();

      const loginLogo = document.getElementById("ffLoginLogo");
      if (loginLogo) {
        loginLogo.style.display = "";
        loginLogo.src = cebjSrc;
      }
      ffEnsureBrandingPanel(data);
    });
  };

  function ffEnsureBrandingPanel(data) {
    if (document.getElementById("ffBrandingPanel")) {
      const sn = document.getElementById("ffShopName");
      if (sn) sn.value = data.shop_name || "";
      return;
    }
    const settings = document.getElementById("settingsSection");
    if (!settings) return;
    const panel = document.createElement("div");
    panel.id = "ffBrandingPanel";
    panel.className = "card shadow-sm border-0 mb-4";
    panel.innerHTML = `<div class="card-header card-header-custom"><h5 class="card-header-title mb-0">Branding</h5></div>
      <div class="card-body">
        <p class="text-muted small">Shop name and voucher note. Logos are fixed to CEBJ branding.</p>
        <div class="row g-2 mb-2">
          <div class="col-md-4"><label class="form-label small">Shop name</label><input id="ffShopName" class="form-control form-control-sm" value="${escAttr(data.shop_name || "CEBJ.NET")}"></div>
          <div class="col-md-4"><label class="form-label small">Voucher note</label><input id="ffVoucherNote" class="form-control form-control-sm" value="${escAttr(data.voucher_template_note || "")}"></div>
          <div class="col-md-4 d-flex align-items-end"><button class="btn btn-primary btn-sm" onclick="ffSaveBranding()">Save branding</button></div>
        </div>
        <div class="form-check mb-2"><input class="form-check-input" type="checkbox" id="ffBackupSched" ${data.backup_schedule_enabled == 1 ? "checked" : ""}><label class="form-check-label" for="ffBackupSched">Enable backup schedule flag</label></div>
        <div class="form-check mb-2"><input class="form-check-input" type="checkbox" id="ffSmsEnabled" ${data.sms_enabled == 1 ? "checked" : ""}><label class="form-check-label" for="ffSmsEnabled">SMS receipts (stub)</label></div>
        <button class="btn btn-outline-secondary btn-sm" onclick="ffSmsTest()">Test SMS stub</button>
      </div>`;
    settings.insertBefore(panel, settings.firstChild);
  }

  async function ffParseApiResponse(r) {
    const ct = (r.headers.get("content-type") || "").toLowerCase();
    const text = await r.text();
    const trimmed = (text || "").trim();
    const looksJson =
      ct.includes("application/json") ||
      trimmed.startsWith("{") ||
      trimmed.startsWith("[");
    if (looksJson) {
      try {
        return { httpStatus: r.status, data: JSON.parse(trimmed) };
      } catch (e) {
        return {
          httpStatus: r.status,
          data: {
            status: "error",
            message: "Invalid JSON response (HTTP " + r.status + ")",
          },
        };
      }
    }
    const snippet = trimmed.replace(/\s+/g, " ").slice(0, 120);
    return {
      httpStatus: r.status,
      data: {
        status: "error",
        message:
          "Firmware upload failed: HTTP " +
          r.status +
          (snippet ? " — " + snippet : ""),
      },
    };
  }

  let ffFlashLockTimer = null;
  let ffFlashLockPoll = null;
  let ffFlashLockActive = false;
  let ffFlashLockFailCount = 0;
  let ffFlashLockStarted = 0;
  let ffFlashLockFloor = 8;

  function ffFlashLockUnload(ev) {
    if (!ffFlashLockActive) return;
    ev.preventDefault();
    ev.returnValue = "Firmware flash in progress. Do not leave this page.";
    return ev.returnValue;
  }

  function ffFlashLockKey(ev) {
    if (!ffFlashLockActive) return;
    const block = ev.key === "Escape" || ev.key === "F5" ||
      ((ev.ctrlKey || ev.metaKey) && String(ev.key).toLowerCase() === "r");
    if (block) {
      ev.preventDefault();
      ev.stopPropagation();
    }
  }

  function ffSetFlashLockProgress(pct, hint) {
    pct = Math.max(0, Math.min(99, Math.round(pct)));
    const bar = document.getElementById("ffFlashLockBar");
    const pctEl = document.getElementById("ffFlashLockPct");
    const hintEl = document.getElementById("ffFlashLockHint");
    if (bar) bar.style.width = pct + "%";
    if (pctEl) pctEl.textContent = pct + "%";
    if (hint && hintEl) hintEl.textContent = hint;
  }

  function ffStopFlashLockTimers() {
    if (ffFlashLockTimer) {
      clearInterval(ffFlashLockTimer);
      ffFlashLockTimer = null;
    }
    if (ffFlashLockPoll) {
      clearInterval(ffFlashLockPoll);
      ffFlashLockPoll = null;
    }
  }

  function ffEndFlashLock() {
    ffFlashLockActive = false;
    ffStopFlashLockTimers();
    window.removeEventListener("beforeunload", ffFlashLockUnload);
    window.removeEventListener("keydown", ffFlashLockKey, true);
    document.body.style.overflow = "";
    const el = document.getElementById("ffFlashLockOverlay");
    if (el) {
      el.style.display = "none";
      el.classList.remove("is-on");
    }
  }

  function ffMarkFlashAccepted(hint) {
    ffFlashLockFloor = Math.max(ffFlashLockFloor, 18);
    ffSetFlashLockProgress(Math.max(18, ffFlashLockFloor), hint || "Flash started. Do not interrupt.");
  }

  function ffBeginFlashLock(kind) {
    ffFlashLockActive = true;
    ffFlashLockFailCount = 0;
    ffFlashLockStarted = Date.now();
    ffFlashLockFloor = 8;
    const oem = kind === "oem";
    const ota = kind === "ota";
    const title = document.getElementById("ffFlashLockTitle");
    const msg = document.getElementById("ffFlashLockMsg");
    if (title) title.textContent = oem ? "Installing OEM ReyeeOS" : (ota ? "Applying firmware update" : "Flashing KonekSik Firmware");
    if (msg) msg.textContent = "Do not close this tab, refresh, click around, or unplug the router.";
    ffSetFlashLockProgress(8, "Starting flash…");
    const el = document.getElementById("ffFlashLockOverlay");
    if (el) {
      el.style.display = "flex";
      el.classList.add("is-on");
    }
    document.body.style.overflow = "hidden";
    window.addEventListener("beforeunload", ffFlashLockUnload);
    window.addEventListener("keydown", ffFlashLockKey, true);
    ffStopFlashLockTimers();
    ffFlashLockTimer = setInterval(function () {
      const t = (Date.now() - ffFlashLockStarted) / 1000;
      const creep = 8 + 72 * (1 - Math.exp(-t / 35));
      ffSetFlashLockProgress(Math.max(ffFlashLockFloor, Math.min(88, creep)));
    }, 400);
    ffFlashLockPoll = setInterval(function () {
      api("update_progress").then((d) => {
        ffFlashLockFailCount = 0;
        const rawLog = String((d && d.progress) || "");
        const log = rawLog.toLowerCase();
        const lines = rawLog.trim().split("\n");
        const last = (lines[lines.length - 1] || "").toLowerCase();
        if (last.indexOf("fatal:") !== -1 || last.indexOf("insufficient overlay") !== -1 || last.indexOf("insufficient space") !== -1) {
          ffEndFlashLock();
          const lines = rawLog.trim().split("\n");
          const last = lines[lines.length - 1] || "Update failed";
          toast(last, "error");
          const again = document.getElementById("btnOTA_Proceed");
          if (again) again.disabled = false;
          const fwBtn = document.getElementById("ffFwFlashBtn");
          if (fwBtn) fwBtn.disabled = false;
          return;
        }
        if (log.indexOf("reboot") !== -1 || log.indexOf("completed") !== -1) {
          ffFlashLockFloor = Math.max(ffFlashLockFloor, 86);
          ffSetFlashLockProgress(Math.max(86, ffFlashLockFloor), "Write finished. Router is rebooting…");
        } else if (
          log.indexOf("mtd write") !== -1 ||
          log.indexOf("sysupgrade") !== -1 ||
          log.indexOf("unlocking") !== -1 ||
          log.indexOf("writing") !== -1
        ) {
          ffFlashLockFloor = Math.max(ffFlashLockFloor, 42);
          ffSetFlashLockProgress(Math.max(42, ffFlashLockFloor), "Writing firmware to flash. Do not unplug.");
        } else if (log.indexOf("flash started") !== -1 || log.indexOf("pass") !== -1) {
          ffFlashLockFloor = Math.max(ffFlashLockFloor, 22);
          ffSetFlashLockProgress(Math.max(22, ffFlashLockFloor), "Flash accepted. Preparing write…");
        }
      }).catch(function () {
        ffFlashLockFailCount += 1;
        if (ffFlashLockFailCount >= 3) {
          ffFlashLockFloor = Math.max(ffFlashLockFloor, 92);
          ffSetFlashLockProgress(92, "Router is rebooting. Keep this tab open. Wait 2–5 minutes, then reconnect.");
          ffStopFlashLockTimers();
        }
      });
    }, 2000);
  }

  window.ffBeginFlashLock = ffBeginFlashLock;
  window.ffEndFlashLock = ffEndFlashLock;
  window.ffMarkFlashAccepted = ffMarkFlashAccepted;

  window._ffAuthOk = { koneksik: false, oem: false };
  // Signed token kept after the file input is cleared. Flash still sends it;
  // the router verifies the signature again. This is not a frontend bypass.
  window._ffAuthRaw = { koneksik: "", oem: "" };
  window._ffAuthBusy = { koneksik: false, oem: false };

  function ffAuthEls(kind) {
    if (kind === "oem") {
      return {
        file: "ffOemAuthFile",
        status: "ffOemAuthStatus",
        action: "oem_restore",
        flash: "ffOemFlashBtn",
      };
    }
    return {
      file: "ffFwAuthFile",
      status: "ffFwAuthStatus",
      action: "koneksik_manual_flash",
      flash: "ffFwFlashBtn",
    };
  }

  function ffClearAuthState(kind, message) {
    const ids = ffAuthEls(kind);
    window._ffAuthOk[kind] = false;
    window._ffAuthRaw[kind] = "";
    const file = document.getElementById(ids.file);
    if (file) file.value = "";
    const status = document.getElementById(ids.status);
    if (status) status.textContent = message || "Authorization status: Not verified";
    ffSyncFlashButton(kind);
  }

  window.ffOnFirmwareFilePicked = function (kind) {
    ffClearAuthState(kind, "Authorization status: Not verified — firmware selection changed.");
  };

  function ffSyncFlashButton(kind) {
    const ids = ffAuthEls(kind);
    const btn = document.getElementById(ids.flash);
    if (!btn) return;
    if (kind === "koneksik") {
      const staged = (document.getElementById("ffFwStatus")?.textContent || "").indexOf("Staged:") === 0;
      btn.disabled = !(staged && window._ffAuthOk.koneksik);
      return;
    }
    btn.disabled = !(window._ffAuthOk.oem && !!ffOemConfirmToken);
  }

  window.ffLoadFlashAuthFile = function (input, kind) {
    const file = input && input.files && input.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = function () {
      const ids = ffAuthEls(kind);
      window._ffAuthRaw[kind] = String(reader.result || "").trim();
      window._ffAuthOk[kind] = false;
      const status = document.getElementById(ids.status);
      if (status) status.textContent = "Authorization status: Not verified";
      ffSyncFlashButton(kind);
    };
    reader.readAsText(file);
  };

  window.ffVerifyFlashAuth = function (kind) {
    const ids = ffAuthEls(kind);
    const raw = String(window._ffAuthRaw[kind] || "").trim();
    const status = document.getElementById(ids.status);
    if (window._ffAuthBusy[kind]) return;
    window._ffAuthOk[kind] = false;
    ffSyncFlashButton(kind);
    if (!raw) {
      if (status) status.textContent = "Seller authorization required.";
      toast("Seller authorization required.", "warning");
      return;
    }
    window._ffAuthBusy[kind] = true;
    if (status) status.textContent = "Checking seller authorization…";
    api("flash_auth_verify", {
      method: "POST",
      body: { flash_auth: raw, action_name: ids.action },
    }).then((d) => {
      window._ffAuthBusy[kind] = false;
      if (d.status === "ok" && d.code === "VALID") {
        window._ffAuthOk[kind] = true;
        window._ffAuthRaw[kind] = raw;
        const file = document.getElementById(ids.file);
        if (file) file.value = "";
        if (status) status.textContent = "Authorization status: Verified. You can flash without choosing the file again.";
        toast(d.message || "Seller authorization verified.", "success");
      } else {
        window._ffAuthOk[kind] = false;
        if (status) status.textContent = d.message || "Invalid seller authorization.";
        toast(d.message || "Invalid seller authorization.", "error");
      }
      ffSyncFlashButton(kind);
    }).catch((e) => {
      window._ffAuthBusy[kind] = false;
      window._ffAuthOk[kind] = false;
      if (status) status.textContent = "Invalid seller authorization.";
      toast(String(e), "error");
      ffSyncFlashButton(kind);
    });
  };

  window.ffUploadFirmware = function () {
    const input = document.getElementById("ffFirmwareFile");
    const file = input && input.files && input.files[0];
    const status = document.getElementById("ffFwStatus");
    const flashBtn = document.getElementById("ffFwFlashBtn");
    if (!file) {
      toast("Choose a .bin file first", "warning");
      return;
    }
    if (status) status.textContent = "Uploading " + file.name + "…";
    fetch("/cgi-bin/api?action=upload_firmware", {
      method: "POST",
      credentials: "include",
      body: file,
    })
      .then((r) => ffParseApiResponse(r))
      .then(({ data: d }) => {
        if (d.status === "ok") {
          toast("Firmware staged (" + (d.size_mb || "?") + " MB)", "success");
          if (status) status.textContent = "Staged: " + file.name + " (" + (d.size_mb || "?") + " MB). Ready to flash.";
          ffSyncFlashButton("koneksik");
        } else {
          toast(d.message || "Upload failed", "error");
          if (status) status.textContent = d.message || "Upload failed";
        }
      })
      .catch((e) => {
        toast("Upload failed: " + e, "error");
        if (status) status.textContent = "Upload failed";
      });
  };

  window.ffFlashUploadedFirmware = function () {
    if (ffFlashLockActive || window._ffAuthBusy.koneksik) return;
    if (!document.getElementById("ffFwConfirmStock")?.checked) {
      toast("Confirm you understand the flash risk", "warning");
      return;
    }
    ffConfirm(
      "Flash staged KonekSik/OpenWrt firmware now? The router will reboot. This uses the standard sysupgrade path (not OEM ReyeeOS restore).",
      {
        title: "Flash KonekSik Firmware",
        okText: "Flash Now",
        okClass: "btn btn-warning btn-sm",
        onConfirm: function () {
          ffBeginFlashLock("koneksik");
          const auth = String(window._ffAuthRaw.koneksik || "").trim();
          api("flash_firmware", { method: "POST", body: { confirm_stock: "1", flash_auth: auth } }).then((d) => {
            const status = document.getElementById("ffFwStatus");
            if (status) status.textContent = d.message || "";
            if (d.status !== "ok") {
              ffEndFlashLock();
              toast(d.message || "Failed", "error");
              return;
            }
            ffMarkFlashAccepted(d.message || "Flash started. Do not interrupt.");
            if (/preview/i.test(d.message || "")) {
              setTimeout(function () {
                ffEndFlashLock();
                toast("Preview mode — flash not executed", "success");
              }, 3500);
            }
          }).catch((e) => {
            ffEndFlashLock();
            toast("Flash failed: " + e, "error");
          });
        },
      }
    );
  };

  let ffOemConfirmToken = "";
  let ffOemPollTimer = null;

  function ffStopOemPoll() {
    if (ffOemPollTimer) {
      clearInterval(ffOemPollTimer);
      ffOemPollTimer = null;
    }
  }

  function ffRenderOemReport(report) {
    const box = document.getElementById("ffOemReport");
    if (!box) return;
    if (!report) {
      box.style.display = "none";
      box.innerHTML = "";
      return;
    }
    const checks = report.checks || {};
    const rows = Object.keys(checks)
      .map((k) => `<div><strong>${k}:</strong> ${checks[k]}</div>`)
      .join("");
    box.style.display = "block";
    box.innerHTML = `
      <div class="mb-1"><strong>${report.pending ? "OEM Firmware Validating" : "OEM Firmware Detected"}</strong></div>
      <div>Type: ${report.package_type || "—"}</div>
      <div>Product ID: ${report.product_id || "—"}</div>
      <div>Hardware: ${report.hardware || "RG-EW1200G-PRO"}</div>
      <div>Version: ${report.version || "—"}</div>
      <div>Image size: ${report.image_size || "—"} bytes</div>
      <div>Firmware partition: ${report.firmware_mtd_size || "—"} bytes</div>
      <div>SHA256: <code style="font-size:10px">${report.sha256 || "—"}</code></div>
      <div>Flash target: <code>${report.flash_target || "firmware"}</code></div>
      <div>Ready: ${report.ready ? "YES" : (report.pending ? "VALIDATING" : "NO")}</div>
      <div class="mt-2">${rows}</div>`;
  }

  function ffApplyOemResult(d) {
    const status = document.getElementById("ffOemStatus");
    const flashBtn = document.getElementById("ffOemFlashBtn");
    const cancelBtn = document.getElementById("ffOemCancelBtn");
    if (d.status === "ok" && d.report && (d.pending || d.report.pending) && !d.report.ready) {
      ffOemConfirmToken = "";
      ffRenderOemReport(d.report);
      if (status) status.textContent = d.message || "Validating in background…";
      if (flashBtn) flashBtn.disabled = true;
      if (cancelBtn) cancelBtn.disabled = false;
      return "pending";
    }
    if (d.status === "ok" && d.report && d.report.ready) {
      ffStopOemPoll();
      ffOemConfirmToken = d.report.confirm_token || "";
      ffRenderOemReport(d.report);
      toast("OEM firmware validated", "success");
      if (status) status.textContent = "Validated. Review the report, then confirm to install.";
      ffSyncFlashButton("oem");
      if (cancelBtn) cancelBtn.disabled = false;
      return "ready";
    }
    ffStopOemPoll();
    ffOemConfirmToken = "";
    ffRenderOemReport(d.report || null);
    toast(d.message || "OEM validation failed", "error");
    if (status) status.textContent = d.message || "OEM validation failed";
    if (flashBtn) flashBtn.disabled = true;
    return "fail";
  }

  window.ffUploadOemFirmware = function () {
    const input = document.getElementById("ffOemFirmwareFile");
    const file = input && input.files && input.files[0];
    const status = document.getElementById("ffOemStatus");
    const flashBtn = document.getElementById("ffOemFlashBtn");
    const cancelBtn = document.getElementById("ffOemCancelBtn");
    ffStopOemPoll();
    ffOemConfirmToken = "";
    if (flashBtn) flashBtn.disabled = true;
    if (!file) {
      toast("Choose an official OEM package first", "warning");
      return;
    }
    ffClearAuthState("oem");
    if (status) status.textContent = "Uploading " + file.name + "…";
    fetch("/cgi-bin/api?action=upload_oem_firmware", {
      method: "POST",
      credentials: "include",
      body: file,
    })
      .then((r) => ffParseApiResponse(r))
      .then(({ data: d }) => {
        const st = ffApplyOemResult(d);
        if (st === "pending") {
          let n = 0;
          ffOemPollTimer = setInterval(function () {
            n += 1;
            if (n > 180) {
              ffStopOemPoll();
              if (status) status.textContent = "Validation timed out. Use rgos.bin or try again.";
              toast("OEM validation timed out", "error");
              return;
            }
            api("validate_oem_firmware").then((vd) => {
              const vs = ffApplyOemResult(vd);
              if (vs !== "pending") ffStopOemPoll();
            }).catch(() => {});
          }, 2000);
        }
      })
      .catch((e) => {
        toast("OEM upload failed: " + e, "error");
        if (status) status.textContent = "OEM upload failed";
      });
  };

  window.ffCancelOemFirmware = function () {
    api("cancel_oem_firmware", { method: "POST", body: {} }).then((d) => {
      ffStopOemPoll();
      ffOemConfirmToken = "";
      ffClearAuthState("oem");
      ffRenderOemReport(null);
      const flashBtn = document.getElementById("ffOemFlashBtn");
      const cancelBtn = document.getElementById("ffOemCancelBtn");
      if (flashBtn) flashBtn.disabled = true;
      if (cancelBtn) cancelBtn.disabled = true;
      const status = document.getElementById("ffOemStatus");
      if (status) status.textContent = "OEM staging cancelled.";
      toast(d.message || "Cancelled", d.status === "ok" ? "success" : "error");
    });
  };

  window.ffFlashOemFirmware = function () {
    if (ffFlashLockActive || window._ffAuthBusy.oem) return;
    if (!document.getElementById("ffOemConfirm")?.checked) {
      toast("Confirm OEM ReyeeOS installation risk", "warning");
      return;
    }
    if (!ffOemConfirmToken) {
      toast("Validate an OEM package before flashing", "warning");
      return;
    }
    ffConfirm(
      "Install official ReyeeOS now? This writes only the firmware MTD partition, replaces KonekSik, and reboots. U-Boot / factory / product_info are not modified by this feature.",
      {
        title: "Install OEM ReyeeOS",
        okText: "Install OEM Firmware",
        okClass: "btn btn-danger btn-sm",
        onConfirm: function () {
          ffBeginFlashLock("oem");
          api("flash_oem_firmware", {
            method: "POST",
            body: {
              confirm_oem: "1",
              confirm_token: ffOemConfirmToken,
              flash_auth: String(window._ffAuthRaw.oem || "").trim(),
            },
          }).then((d) => {
            const status = document.getElementById("ffOemStatus");
            if (status) status.textContent = d.message || "";
            if (d.status !== "ok") {
              ffEndFlashLock();
              toast(d.message || "Failed", "error");
              return;
            }
            ffMarkFlashAccepted(d.message || "OEM flash started. Do not interrupt.");
            if (/preview/i.test(d.message || "")) {
              setTimeout(function () {
                ffEndFlashLock();
                toast("Preview mode — OEM flash not executed", "success");
              }, 3500);
            }
          }).catch((e) => {
            ffEndFlashLock();
            toast("OEM flash failed: " + e, "error");
          });
        },
      }
    );
  };

  window.ffSaveBranding = function () {
    api("set_branding", {
      method: "POST",
      body: {
        shop_name: document.getElementById("ffShopName")?.value,
        voucher_template_note: document.getElementById("ffVoucherNote")?.value,
        backup_schedule_enabled: document.getElementById("ffBackupSched")?.checked ? 1 : 0,
        sms_enabled: document.getElementById("ffSmsEnabled")?.checked ? 1 : 0,
        sms_provider: "none",
        sms_endpoint: "",
      },
    }).then((d) => toast(d.status === "ok" ? "Saved" : d.message, d.status === "ok" ? "success" : "error"));
  };

  window.ffUploadLogo = function (ev, kind) {
    const file = ev.target.files && ev.target.files[0];
    if (!file) return;
    fetch("/cgi-bin/api?action=upload_logo&kind=" + encodeURIComponent(kind), {
      method: "POST",
      credentials: "include",
      body: file,
    })
      .then((r) => r.json())
      .then((d) => {
        toast(d.status === "ok" ? "Logo uploaded" : d.message, d.status === "ok" ? "success" : "error");
        ffLoadBranding();
      });
  };

  window.ffSmsTest = function () {
    api("sms_test", { method: "POST", body: {} }).then((d) => toast(d.message || "OK", "info"));
  };

  window.ffLoadActivityWidget = function () {
    api("activity_feed", { query: { limit: 8 } }).then((data) => {
      if (typeof addToActivityLog !== "function") return;
      (data.data || []).slice().reverse().forEach((e) => {
        try {
          addToActivityLog((e.title || "") + (e.body ? " — " + e.body : ""), e.type || "info");
        } catch (err) {}
      });
    });
  };

  function esc(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }
  function escAttr(s) {
    return esc(s).replace(/'/g, "&#39;");
  }

  // Hash routing for new pages
  const _nav = window.navigateToHash;
  window.navigateToHash = function () {
    const h = (location.hash || "").replace(/^#/, "");
    const map = {
      bandwidth: showBandwidth,
      devices: showDevices,
      waiting: showWaitingQueue,
      radio: showRadioStatus,
      pricing: showPricingHub,
      operators: showOperators,
      reports: showReports,
      "captive-portal": showCaptivePortal,
      "access-points": showAccessPoints,
      "remote-access": showRemoteAccess,
    };
    if (map[h]) {
      map[h]();
      return;
    }
    if (typeof _nav === "function") _nav();
  };

  // KonekSik-style sidebar active state (data-nav)
  window.highlightSidebar = function (page) {
    const items = document.querySelectorAll(".sidebar .nav-item[data-nav]");
    items.forEach((el) => {
      if (el.getAttribute("data-nav") === page) el.classList.add("active");
      else el.classList.remove("active");
    });
  };

  // ---- Sub Vendo: KSK offline license UI overrides ----
  function ffEscHtml(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  // Stock admin.js defines removeESPDevice; Del buttons call deleteESPDevice.
  // Licensed rows: one explicit Unbind-and-delete confirm, then force=1.
  // Soft delete without force returns REQUIRES_UNBIND and must not toast success.
  window.deleteESPDevice = function (espId, force, meta) {
    if (!espId) return;
    meta = meta || {};
    const lic = String(meta.license || "").trim();
    const looksBound = !!(lic && lic !== "—" && lic !== "-" && lic !== "null");
    const run = (withForce) => {
      const q =
        "/cgi-bin/api?action=delete_esp_device&slot_id=" +
        encodeURIComponent(espId) +
        (withForce ? "&force=1&confirm_unbind=1" : "");
      return fetch(q, { credentials: "include" })
        .then((r) => r.json())
        .then((d) => {
          if (d.code === "REQUIRES_UNBIND" || d.requires_unbind) {
            const ok = confirm(
              "Unbind and Delete ESP32?\n\nName: " +
                (d.slot_name || meta.name || "ESP32") +
                "\nMAC: " +
                (d.slot_mac || meta.mac || "—") +
                "\nLicense: " +
                (d.license_id || meta.license || "—") +
                "\n\nThis device is still bound to a KSK. Confirm to clear the live binding (signed .ksk kept), remove it from Registered ESP32 Devices, and refresh both tables.\n\nContinue?"
            );
            if (ok) return run(true);
            if (typeof showToast === "function") {
              showToast("Delete cancelled — Unbind required for bound devices", "warning");
            }
            return null;
          }
          if (d.status !== "ok") {
            if (typeof showToast === "function") {
              showToast(d.message || d.code || "Delete failed", "error");
            }
            return null;
          }
          if (typeof showToast === "function") {
            showToast(d.message || "Deleted", "success");
          }
          if (typeof loadESPDevices === "function") loadESPDevices();
          if (typeof loadLicensePool === "function") loadLicensePool();
        });
    };
    if (force) return run(true);
    if (looksBound) {
      const ok = confirm(
        "Unbind and Delete ESP32?\n\nName:\n" +
          (meta.name || "ESP32") +
          "\n\nMAC:\n" +
          (meta.mac || "—") +
          "\n\nLicense:\n" +
          (meta.license || "—") +
          "\n\nThis registered device is licensed. Delete will Unbind it first (clear live MAC, keep signed .ksk), then remove the Registered ESP32 Devices row. The license will show Unbound — not Active.\n\nOffline devices can still be cleaned up.\n\nContinue?"
      );
      if (!ok) return;
      return run(true).catch((e) => {
        if (typeof showToast === "function") showToast(String(e), "error");
      });
    }
    const ok = confirm(
      "Delete ESP32?\n\nName:\n" +
        (meta.name || "ESP32") +
        "\n\nMAC:\n" +
        (meta.mac || "—") +
        "\n\nRemoves this unlicensed row from Registered ESP32 Devices."
    );
    if (!ok) return;
    return run(false).catch((e) => {
      if (typeof showToast === "function") showToast(String(e), "error");
    });
  };

  window.removeESPDevice = function (espId) {
    return window.deleteESPDevice(espId, false, {});
  };

  function ffFillMacCandidates(cands, suggested) {
    const macEl = document.getElementById("detectEspMac");
    const out = document.getElementById("detectEspResult");
    if (!macEl) return;
    if (suggested) macEl.value = suggested;
    if (!out || !cands || !cands.length) return;
    out.replaceChildren();
    const label = document.createElement("div");
    label.className = "small";
    label.textContent = "Candidates — click to use:";
    out.appendChild(label);
    const row = document.createElement("div");
    row.className = "d-flex flex-wrap gap-1 mt-1";
    cands.slice(0, 8).forEach((c) => {
      const mac = String(c.mac || "");
      if (!mac) return;
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "btn btn-outline-secondary btn-sm font-monospace";
      btn.textContent = mac + (c.ip ? " · " + c.ip : "");
      btn.addEventListener("click", () => {
        macEl.value = mac;
      });
      row.appendChild(btn);
    });
    out.appendChild(row);
  }

  window.scanEspMac = function () {
    const out = document.getElementById("detectEspResult");
    if (out) out.textContent = "Scanning LAN for ESP…";
    fetch("/cgi-bin/api?action=esp_scan", { credentials: "include" })
      .then((r) => r.json())
      .then((d) => {
        if (d.status !== "ok") {
          if (out) out.textContent = d.message || "Scan failed";
          if (typeof showToast === "function") showToast(d.message || "Scan failed", "error");
          return;
        }
        if (d.suggested_mac) {
          const macEl = document.getElementById("detectEspMac");
          if (macEl) macEl.value = d.suggested_mac;
        }
        ffFillMacCandidates(d.candidates || [], d.suggested_mac || "");
        if (typeof showToast === "function") {
          showToast(d.message || "Scan done", d.suggested_mac ? "success" : "warning");
        }
      })
      .catch((e) => {
        if (out) out.textContent = String(e);
      });
  };

  // Load → Verify → Bind state (browser only; Bind always re-validates server-side).
  window._espKskState = {
    loaded: false,
    verified: false,
    verifyToken: "",
    parsed: null,
    verifyResult: null,
  };

  function ffUtf8ToB64(str) {
    const bytes = new TextEncoder().encode(str);
    let bin = "";
    bytes.forEach((b) => {
      bin += String.fromCharCode(b);
    });
    return btoa(bin);
  }

  function ffExtractSignedKsk(rawText) {
    const text = String(rawText || "").trim();
    if (!text) {
      return { error: "Load a signed .ksk license to continue." };
    }
    if (/^KSK-[A-Za-z0-9_-]+$/i.test(text) && text.indexOf("{") < 0) {
      return {
        error:
          "Invalid KSK input. Please load the signed .ksk license file (not only the License ID).",
      };
    }
    let obj;
    try {
      obj = JSON.parse(text);
    } catch (e) {
      return { error: "Invalid KSK license. Please load a valid signed .ksk file." };
    }
    if (!obj || typeof obj !== "object") {
      return { error: "Invalid KSK license. Please load a valid signed .ksk file." };
    }
    if (obj.type === "ksk_replacement_bundle" && obj.license && typeof obj.license === "object") {
      obj = obj.license;
    }
    if (!obj.sig_b64 || !obj.license_id || obj.type !== "esp_coinslot") {
      return {
        error: "Invalid KSK input. Please load the signed .ksk license file from the seller package.",
      };
    }
    return { license: obj, raw: JSON.stringify(obj) };
  }

  function ffExpiryLabel(expiresAt) {
    const n = Number(expiresAt || 0);
    if (!n) return "Never";
    try {
      return new Date(n * 1000).toISOString().slice(0, 10);
    } catch (e) {
      return String(n);
    }
  }

  function ffSetKskUiStates(loadedText, compatText, bindText) {
    const set = (id, val) => {
      const el = document.getElementById(id);
      if (el) el.textContent = val || "—";
    };
    set("detectKskLoadedState", loadedText);
    set("detectKskCompatState", compatText);
    set("detectKskBindState", bindText);
  }

  function ffUpdateDetectButtons() {
    const verifyBtn = document.getElementById("btnVerifyEspKsk");
    const bindBtn = document.getElementById("btnBindEspKsk");
    const st = window._espKskState || {};
    if (verifyBtn) verifyBtn.disabled = !st.loaded;
    if (bindBtn) {
      const canBind =
        !!st.verified &&
        !!st.verifyResult &&
        st.verifyResult.ready_to_bind &&
        !st.verifyResult.already_bound &&
        !window._espBindBusy;
      bindBtn.disabled = !canBind;
    }
  }

  function ffShowKskPreview(lic, statusText) {
    const box = document.getElementById("detectKskPreview");
    if (!box) return;
    box.style.display = "block";
    const set = (id, val) => {
      const el = document.getElementById(id);
      if (el) el.textContent = val || "—";
    };
    set("detectKskPreviewId", lic && lic.license_id);
    set("detectKskPreviewMac", lic && lic.mac);
    set("detectKskPreviewChip", lic && lic.chip_id);
    set("detectKskPreviewRouter", lic && lic.router_device_id);
    set("detectKskPreviewPlan", lic && lic.plan);
    set("detectKskPreviewExpiry", ffExpiryLabel(lic && lic.expires_at));
    const hid = document.getElementById("detectLicenseId");
    if (hid) hid.value = (lic && lic.license_id) || "";
    ffSetKskUiStates("✓ Loaded", statusText || "Not verified", "Not bound");
  }

  function ffShowVerifyPanel(html, ok) {
    const panel = document.getElementById("detectVerifyResult");
    if (!panel) return;
    panel.style.display = "block";
    panel.className = "small mb-2 " + (ok ? "text-success" : "text-danger");
    panel.innerHTML = html;
  }

  window.clearDetectKsk = function () {
    window._espKskState = {
      loaded: false,
      verified: false,
      verifyToken: "",
      parsed: null,
      verifyResult: null,
    };
    const file = document.getElementById("detectKskFile");
    if (file) file.value = "";
    const hid = document.getElementById("detectLicenseId");
    if (hid) hid.value = "";
    const box = document.getElementById("detectKskPreview");
    if (box) box.style.display = "none";
    const panel = document.getElementById("detectVerifyResult");
    if (panel) {
      panel.style.display = "none";
      panel.innerHTML = "";
    }
    const out = document.getElementById("detectEspResult");
    if (out) out.textContent = "Load a signed .ksk license to continue.";
    ffUpdateDetectButtons();
  };

  window.loadDetectKskFile = function (input) {
    const file = input && input.files && input.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      const text = String(reader.result || "");
      const parsed = ffExtractSignedKsk(text);
      const out = document.getElementById("detectEspResult");
      if (parsed.error) {
        window._espKskState.loaded = false;
        window._espKskState.verified = false;
        window._espKskState.parsed = null;
        ffUpdateDetectButtons();
        if (out) out.textContent = parsed.error;
        if (typeof showToast === "function") showToast(parsed.error, "error");
        return;
      }
      window._espKskState = {
        loaded: true,
        verified: false,
        verifyToken: "",
        parsed: parsed,
        verifyResult: null,
      };
      ffShowKskPreview(parsed.license, "Not verified");
      const macEl = document.getElementById("detectEspMac");
      if (macEl && !(macEl.value || "").trim() && parsed.license.mac) {
        macEl.value = String(parsed.license.mac);
      }
      const panel = document.getElementById("detectVerifyResult");
      if (panel) {
        panel.style.display = "none";
        panel.innerHTML = "";
      }
      if (out) out.textContent = "Signed KSK loaded. Verify ESP32 compatibility before binding.";
      if (typeof showToast === "function") showToast("Signed KSK loaded", "info");
      ffUpdateDetectButtons();
    };
    reader.onerror = () => {
      if (typeof showToast === "function") showToast("Could not read .ksk file", "error");
    };
    reader.readAsText(file);
  };

  function ffDetectErrorMessage(d) {
    const code = (d && d.code) || "";
    const msg = (d && d.message) || "";
    if (code === "MISSING_SIGNED_KSK" || /signed ksk|license id alone|load the signed/i.test(msg)) {
      return "Invalid KSK input. Please load the signed .ksk license file.";
    }
    if (code === "INVALID_FORMAT") {
      return "Invalid KSK license. Please load a valid signed .ksk file.";
    }
    if (code === "INVALID_SIGNATURE") {
      return "KSK signature verification failed.";
    }
    if (code === "INVALID_IDENTITY") {
      return "ESP identity does not match this KSK.";
    }
    if (code === "ROUTER_DEVICE_MISMATCH") {
      return "This KSK is bound to another Router Device ID.";
    }
    if (code === "MANUAL_KSK_REJECTED") {
      return "Signed KSK file required.";
    }
    if (code === "EXPIRED") {
      return "KSK license has expired.";
    }
    if (code === "GRACE_EXHAUSTED" || /grace|replacement limit/i.test(msg)) {
      return "KSK replacement limit reached.";
    }
    return msg || "Request failed";
  }

  function ffBuildKskBody(parsed, mac, name) {
    return {
      ksk: parsed.raw,
      ksk_b64: ffUtf8ToB64(parsed.raw),
      mac: mac || "",
      chip_id: parsed.license.chip_id || "",
      license_id: parsed.license.license_id || "",
      name: name || "",
    };
  }

  window.verifyEspKskCompatibility = function () {
    const macEl = document.getElementById("detectEspMac");
    let mac = (macEl?.value || "").trim();
    const name = (document.getElementById("detectEspName")?.value || "").trim();
    const out = document.getElementById("detectEspResult");
    const parsed = (window._espKskState && window._espKskState.parsed) || null;
    if (!parsed) {
      if (out) out.textContent = "Signed KSK file required.";
      if (typeof showToast === "function") showToast("Signed KSK file required.", "warning");
      return;
    }
    if (!mac && parsed.license.mac) {
      mac = String(parsed.license.mac);
      if (macEl) macEl.value = mac;
    }
    if (out) out.textContent = "Verifying ESP32 license compatibility…";

    const runVerify = (macToUse) => {
      const body = ffBuildKskBody(parsed, macToUse, name);
      return fetch("/cgi-bin/api?action=esp_license_verify", {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      })
        .then((r) => r.json())
        .then((d) => {
          if (d.status === "need_pick") {
            ffFillMacCandidates(d.candidates || [], d.suggested_mac || "");
            if (typeof showToast === "function") showToast(d.message || "Pick an ESP MAC", "warning");
            return;
          }
          if (d.status !== "ok") {
            window._espKskState.verified = false;
            window._espKskState.verifyResult = null;
            ffUpdateDetectButtons();
            const friendly = ffDetectErrorMessage(d);
            ffSetKskUiStates("✓ Loaded", "Failed", "Not bound");
            ffShowVerifyPanel(ffEscHtml(friendly), false);
            if (out) out.textContent = friendly;
            if (typeof showToast === "function") showToast(friendly, "error");
            return;
          }
          window._espKskState.verified = true;
          window._espKskState.verifyResult = d;
          window._espKskState.verifyToken = String(Date.now());
          if (d.mac && macEl) macEl.value = d.mac;
          let html =
            "<div class=\"fw-bold\">✓ ESP32 License Compatibility Verified</div>" +
            "<div>License: <span class=\"font-monospace\">" +
            ffEscHtml(d.license_id || "") +
            "</span></div>" +
            "<div>ESP MAC: <span class=\"font-monospace\">" +
            ffEscHtml(d.mac || "") +
            "</span></div>" +
            "<div>Signature: Valid · Identity: Matched · Expiry: " +
            ffEscHtml(d.expiry === "never" ? "Valid (never)" : "Valid") +
            "</div>";
          if (d.code === "ALREADY_BOUND_SAME") {
            html +=
              "<div class=\"mt-1\">License already exists and is already bound to this ESP.</div>";
            ffSetKskUiStates("✓ Loaded", "✓ Verified", "✓ Already bound");
          } else if (d.code === "ALREADY_BOUND_OTHER") {
            html +=
              "<div class=\"mt-1\">License already exists and is currently bound to another ESP.</div>" +
              "<div>Current Live ESP: <span class=\"font-monospace\">" +
              ffEscHtml(d.current_live_mac || "") +
              "</span></div>" +
              "<div>Detected ESP: <span class=\"font-monospace\">" +
              ffEscHtml(d.detected_mac || d.mac || "") +
              "</span></div>" +
              "<div class=\"mt-1\">A second ESP cannot inherit this license. Unbind the live device, or buy a new KSK for this board.</div>";
            ffSetKskUiStates("✓ Loaded", "✓ Verified", "Blocked (other ESP)");
          } else if (d.code === "EXISTS_UNBOUND" || d.code === "EXISTS_PLACEHOLDER") {
            html += "<div class=\"mt-1\">" + ffEscHtml(d.message || "License already exists.") + "</div>";
            ffSetKskUiStates("✓ Loaded", "✓ Verified", "Ready to Bind");
          } else {
            html += "<div class=\"mt-1\">Status: Ready to Bind</div>";
            ffSetKskUiStates("✓ Loaded", "✓ Verified", "Ready to Bind");
          }
          ffShowVerifyPanel(html, true);
          if (out) out.textContent = d.message || "Verified";
          if (typeof showToast === "function") showToast(d.message || "Verified", "success");
          ffUpdateDetectButtons();
        });
    };

    const start = !mac
      ? fetch("/cgi-bin/api?action=esp_scan", { credentials: "include" })
          .then((r) => r.json())
          .then((scan) => {
            if (scan.suggested_mac) {
              mac = scan.suggested_mac;
              if (macEl) macEl.value = mac;
            }
            if (scan.candidates && scan.candidates.length) {
              ffFillMacCandidates(scan.candidates, scan.suggested_mac || "");
            }
            if (!mac && parsed.license.mac) {
              mac = String(parsed.license.mac);
              if (macEl) macEl.value = mac;
            }
            if (!mac) {
              if (out) out.textContent = scan.message || "No ESP found on LAN — enter ESP MAC or Find MAC.";
              if (typeof showToast === "function") showToast(scan.message || "No ESP MAC found", "warning");
              return null;
            }
            return runVerify(mac);
          })
      : runVerify(mac);

    Promise.resolve(start).catch((e) => {
      if (out) out.textContent = String(e);
    });
  };

  window.bindEspKsk = function () {
    const st = window._espKskState || {};
    const out = document.getElementById("detectEspResult");
    if (!st.verified || !st.parsed || !st.verifyResult || !st.verifyResult.ready_to_bind) {
      if (out) out.textContent = "Verify ESP32 compatibility before binding.";
      if (typeof showToast === "function") showToast("Verify compatibility first", "warning");
      return;
    }
    if (st.verifyResult.already_bound) {
      if (out) out.textContent = "License already exists and is already bound to this ESP.";
      return;
    }
    if (window._espBindBusy) return;
    window._espBindBusy = true;
    ffUpdateDetectButtons();
    const macEl = document.getElementById("detectEspMac");
    const mac = (macEl?.value || "").trim() || st.verifyResult.mac || "";
    const name = (document.getElementById("detectEspName")?.value || "").trim();
    if (out) out.textContent = "Binding ESP32 (server re-checks license)…";
    const body = ffBuildKskBody(st.parsed, mac, name);
    fetch("/cgi-bin/api?action=esp_detect", {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    })
      .then((r) => r.json())
      .then((d) => {
        window._espBindBusy = false;
        if (d.status !== "ok") {
          const friendly = ffDetectErrorMessage(d);
          ffSetKskUiStates("✓ Loaded", "Re-verify required", "Bind failed");
          if (out) out.textContent = friendly;
          if (typeof showToast === "function") showToast(friendly, "error");
          // Force re-verify before another bind attempt. Keep the loaded license.
          window._espKskState.verified = false;
          window._espKskState.verifyResult = null;
          ffUpdateDetectButtons();
          return;
        }
        const boundMsg = d.message || "ESP32 bound successfully.";
        window.clearDetectKsk();
        if (out) out.textContent = boundMsg;
        if (typeof showToast === "function") showToast(boundMsg, "success");
        loadESPDevices();
        loadLicensePool();
      })
      .catch((e) => {
        window._espBindBusy = false;
        ffSetKskUiStates("✓ Loaded", "Re-verify required", "Bind failed");
        window._espKskState.verified = false;
        window._espKskState.verifyResult = null;
        if (out) out.textContent = String(e);
        ffUpdateDetectButtons();
      });
  };

  // Legacy alias: old Detect button / helpers now mean Verify.
  window.detectESP32 = function () {
    return window.verifyEspKskCompatibility();
  };

  window.focusBindEspWorkflow = function (macHint) {
    const card = document.getElementById("detectBindEspCard");
    if (card) card.scrollIntoView({ behavior: "smooth", block: "start" });
    if (macHint) {
      const macEl = document.getElementById("detectEspMac");
      if (macEl) macEl.value = macHint;
    }
    const out = document.getElementById("detectEspResult");
    if (out) out.textContent = "Load the signed .ksk for this license, Verify compatibility, then BIND ESP32.";
    document.getElementById("detectKskFile")?.focus();
  };

  window.unbindKskLicense = function (licenseId) {
    if (!licenseId) return;
    if (!confirm("Unbind this ESP from " + licenseId + "?\n\nClears the live binding and slot license flags. Signed .ksk is retained; the device stays in Registered until Delete.")) return;
    fetch(
      "/cgi-bin/api?action=esp_license_unbind&license_id=" + encodeURIComponent(licenseId),
      { credentials: "include" }
    )
      .then((r) => r.json())
      .then((d) => {
        if (typeof showToast === "function") {
          showToast(d.message || (d.status === "ok" ? "Unbound" : "Failed"), d.status === "ok" ? "success" : "error");
        }
        if (d.status === "ok") {
          loadESPDevices();
          loadLicensePool();
        }
      })
      .catch((e) => {
        if (typeof showToast === "function") showToast(String(e), "error");
      });
  };

  window.loadLicensePool = function () {
    const tb = document.getElementById("licensePoolBody");
    if (!tb) return;
    fetch("/cgi-bin/api?action=esp_license_list", { credentials: "include" })
      .then((r) => r.json())
      .then((data) => {
        const rows = data.data || data.licenses || (Array.isArray(data) ? data : []);
        const usedEl = document.getElementById("usedLicenseCount");
        if (usedEl) usedEl.textContent = String(rows.length);
        if (!rows.length) {
          tb.innerHTML =
            '<tr><td colspan="6" class="text-center py-3 text-muted">No ESP32 licenses yet — Load a signed .ksk, Verify, then Bind</td></tr>';
          return;
        }
        tb.innerHTML = rows
          .map((lic) => {
            const lid = lic.license_id || lic.license_key || "—";
            const live = lic.live_mac || "";
            const boundMac = live || lic.last_live_mac || "";
            const st = lic.status || "—";
            const graceN = Number(lic.grace_used || 0);
            const ever = Number(lic.ksk_ever_bound || 0);
            const hasSigned = !!(lic.has_signed_ksk || (lic.signed_ksk && String(lic.signed_ksk).trim()));
            const canRemove = st === "available" && graceN === 0 && ever === 0 && !hasSigned;
            const isActive = (st === "used" || st === "active") && !!live;
            const badge =
              isActive
                ? '<span class="badge bg-success">Active</span>'
                : '<span class="badge bg-secondary">' + ffEscHtml(st) + "</span>";
            let action = "—";
            if (isActive) {
              action =
                '<button type="button" class="btn btn-sm btn-outline-warning" onclick="unbindKskLicense(\'' +
                ffEscHtml(lid).replace(/'/g, "\\'") +
                "')\">Unbind</button>";
            } else if (canRemove) {
              action =
                '<button type="button" class="btn btn-sm btn-outline-danger" onclick="removeLicenseFromPool(' +
                lic.id +
                ')">Remove</button>';
            } else if (st === "available" || st === "unbound") {
              action =
                '<button type="button" class="btn btn-sm btn-outline-primary" onclick="focusBindEspWorkflow(\'' +
                ffEscHtml(boundMac).replace(/'/g, "\\'") +
                "')\">Bind</button>";
            } else if (hasSigned || ever > 0) {
              action = '<span class="small text-muted">History kept</span>';
            }
            return (
              '<tr><td class="font-monospace small">' +
              ffEscHtml(lid) +
              "</td><td>" +
              badge +
              '</td><td class="font-monospace small">' +
              ffEscHtml(live || "—") +
              '</td><td class="font-monospace small">' +
              ffEscHtml(boundMac || "—") +
              '</td><td class="small text-muted">' +
              ffEscHtml(lic.used_at || "—") +
              "</td><td>" +
              action +
              "</td></tr>"
            );
          })
          .join("");
      })
      .catch(() => {
        tb.innerHTML = '<tr><td colspan="6" class="text-danger text-center">Failed to load licenses</td></tr>';
      });
  };

  window.removeLicenseFromPool = function (licenseId) {
    if (!licenseId) return;
    if (typeof window.removeLicense === "function") {
      return window.removeLicense(licenseId);
    }
    if (!confirm("Remove this unused license registration? Binding history is never reset by Remove.")) return;
    fetch("/cgi-bin/api?action=esp_license_remove&id=" + encodeURIComponent(licenseId), {
      credentials: "include",
    })
      .then((r) => r.json())
      .then((d) => {
        if (typeof showToast === "function") {
          showToast(d.message || (d.status === "ok" ? "Removed" : "Failed"), d.status === "ok" ? "success" : "error");
        }
        if (d.status === "ok") loadLicensePool();
      })
      .catch((e) => {
        if (typeof showToast === "function") showToast(String(e), "error");
      });
  };

  window.loadESPDevices = function () {
    fetch("/cgi-bin/api?action=list_esp_devices", { credentials: "include" })
      .then((r) => r.json())
      .then((data) => {
        const rs = document.getElementById("routerLicenseStatus");
        if (rs) rs.textContent = data.router_license_status || "inactive";
        const free = document.getElementById("freeESPSlots");
        if (free) free.textContent = data.available_licenses || 0;
        const avail = document.getElementById("availableLicenseCount");
        if (avail) avail.textContent = String(data.licensed_esp_count != null ? data.licensed_esp_count : data.used_licenses || 0);
        const totalEl = document.getElementById("totalESPSlots");
        const tb = document.getElementById("espTableBody");
        let html = "";
        let totalCount = 0;
        if (data.esp_devices && data.esp_devices.length) {
          data.esp_devices.forEach((esp) => {
            if (esp.slot_mac === "gpio-coinslot") return;
            totalCount++;
            let licenseBadge = "";
            let statusBadge = "";
            const licId = esp.license_id || esp.license_key || "";
            if (esp.license_status === "licensed" || esp.license_status === "free") {
              licenseBadge =
                '<span class="badge bg-success">LICENSED</span>' +
                (licId ? '<div class="font-monospace small text-muted mt-1">' + ffEscHtml(licId) + "</div>" : "");
              statusBadge =
                esp.status === "online"
                  ? '<span class="badge bg-success">Coin ready</span>'
                  : '<span class="badge bg-warning text-dark">Offline</span>';
            } else if (esp.license_status === "inactive_replaced") {
              licenseBadge = '<span class="badge bg-secondary">REPLACED</span>';
              statusBadge = "—";
            } else {
              licenseBadge = '<span class="badge bg-danger">UNLICENSED</span>';
              statusBadge =
                '<button type="button" class="btn btn-primary btn-sm" onclick="focusBindEspWorkflow(\'' +
                ffEscHtml(esp.slot_mac).replace(/'/g, "\\'") +
                "')\">Bind…</button>";
            }
            const delMeta =
              "{name:'" +
              ffEscHtml(esp.slot_name || "ESP32").replace(/'/g, "\\'") +
              "',mac:'" +
              ffEscHtml(esp.slot_mac || "").replace(/'/g, "\\'") +
              "',license:'" +
              ffEscHtml(licId || "").replace(/'/g, "\\'") +
              "'}";
            const adminActions =
              '<button type="button" class="btn btn-outline-primary btn-sm" onclick="renameESPSlot(' +
              esp.id +
              ", '" +
              ffEscHtml(esp.slot_name || "ESP").replace(/'/g, "\\'") +
              "')\">Rename</button>" +
              '<button type="button" class="btn btn-outline-danger btn-sm" onclick="deleteESPDevice(' +
              esp.id +
              ", false, " +
              delMeta +
              ')">Delete</button>';
            html +=
              "<tr><td>" +
              esp.id +
              "</td><td>" +
              ffEscHtml(esp.slot_name || "ESP32") +
              '</td><td class="font-monospace small">' +
              ffEscHtml(esp.slot_mac) +
              "</td><td>" +
              ffEscHtml(esp.status || "—") +
              "</td><td>" +
              licenseBadge +
              '</td><td class="small">' +
              (typeof formatLastSeen === "function" ? formatLastSeen(esp.last_seen) : esp.last_seen || "—") +
              '</td><td><div class="ff-action-btns">' +
              statusBadge +
              adminActions +
              "</div></td></tr>";
          });
        }
        if (totalEl) totalEl.textContent = String(totalCount);
        if (tb) {
          tb.innerHTML =
            html ||
            '<tr><td colspan="7" class="text-center text-muted py-3">No ESP32 devices yet — Load .ksk, Verify, then Bind</td></tr>';
        }
      })
      .catch(() => {
        const tb = document.getElementById("espTableBody");
        if (tb) tb.innerHTML = '<tr><td colspan="7" class="text-danger text-center">Failed to load ESP devices</td></tr>';
      });
  };

  window.freeESPLicense = function () {
    if (typeof showToast === "function") {
      showToast("Use replacement flasher + Verify/Bind ESP32 (grace ≤ 3).", "info");
    }
  };

  window.bindESPLicense = function () {
    focusBindEspWorkflow("");
  };

  document.addEventListener("DOMContentLoaded", () => {
    ffUpdateDetectButtons();
  });

  // ---- Sales page: dual charts + modern date popovers ----
  function ffChartTickColor() {
    return document.documentElement.getAttribute("data-theme") === "dark" ? "#94a3b8" : "#64748b";
  }

  function ffSalesFallbackSeries(filter) {
    if (filter === "day") {
      return {
        labels: ["12a", "3a", "6a", "9a", "12p", "3p", "6p", "9p"],
        data: [0, 0, 20, 80, 120, 90, 150, 60],
      };
    }
    if (filter === "month") {
      return {
        labels: ["W1", "W2", "W3", "W4"],
        data: [1800, 2400, 2100, 2800],
      };
    }
    return {
      labels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
      data: [120, 200, 150, 280, 90, 310, 350],
    };
  }

  window.loadSalesChart = async function () {
    try {
      const filterEl = document.getElementById("chartFilter");
      const filter = filterEl ? filterEl.value : "week";
      const res = await fetch("/cgi-bin/api?action=sales_data&filter=" + encodeURIComponent(filter), {
        credentials: "include",
      });
      const data = await res.json();
      const fallback = ffSalesFallbackSeries(filter);
      const labels = Array.isArray(data.labels) && data.labels.length ? data.labels : fallback.labels;
      const values = Array.isArray(data.data) && data.data.length ? data.data : fallback.data;
      const tick = ffChartTickColor();

      const lineCtx = document.getElementById("salesChartWeekly");
      if (lineCtx) {
        if (lineCtx.chart) lineCtx.chart.destroy();
        lineCtx.chart = new Chart(lineCtx, {
          type: "line",
          data: {
            labels,
            datasets: [
              {
                label: "Sales (₱)",
                data: values,
                borderColor: "#0ea5e9",
                backgroundColor: "rgba(14, 165, 233, 0.14)",
                borderWidth: 2.5,
                fill: true,
                tension: 0.35,
                pointBackgroundColor: "#fff",
                pointBorderColor: "#0ea5e9",
                pointBorderWidth: 2,
                pointRadius: 4,
                pointHoverRadius: 6,
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
              legend: { display: false },
              tooltip: {
                backgroundColor: "rgba(15, 23, 42, 0.92)",
                titleColor: "#fff",
                bodyColor: "#e2e8f0",
                padding: 10,
                cornerRadius: 8,
                displayColors: false,
              },
            },
            scales: {
              x: { grid: { display: false }, ticks: { color: tick } },
              y: {
                grid: { color: "rgba(148, 163, 184, 0.18)" },
                ticks: {
                  color: tick,
                  callback: function (value) {
                    return "₱" + Number(value).toLocaleString();
                  },
                },
                beginAtZero: true,
              },
            },
          },
        });
      }

      const barCtx = document.getElementById("salesChartBreakdown");
      if (barCtx && typeof Chart !== "undefined") {
        if (barCtx.chart) barCtx.chart.destroy();
        const dailyEl = document.getElementById("salesDaily");
        const weeklyEl = document.getElementById("salesWeekly");
        const monthlyEl = document.getElementById("salesMonthly");
        const totalEl = document.getElementById("salesTotal");
        const parsePeso = (el) => {
          if (!el) return 0;
          const n = String(el.textContent || "").replace(/[^\d.]/g, "");
          return Number(n) || 0;
        };
        let barLabels = labels;
        let barValues = values;
        // Prefer KPI snapshot for a second “summary” view when filter is week
        if (filter === "week" || filter === "month") {
          const d = parsePeso(dailyEl);
          const w = parsePeso(weeklyEl);
          const m = parsePeso(monthlyEl);
          const t = parsePeso(totalEl);
          if (d + w + m + t > 0) {
            barLabels = ["Today", "Week", "Month", "All-time"];
            barValues = [d, w, m, t];
          }
        }
        barCtx.chart = new Chart(barCtx, {
          type: "bar",
          data: {
            labels: barLabels,
            datasets: [
              {
                label: "₱",
                data: barValues,
                borderRadius: 8,
                borderSkipped: false,
                backgroundColor: barValues.map((_, i) => {
                  const palette = ["#0ea5e9", "#14b8a6", "#22c55e", "#6366f1"];
                  return palette[i % palette.length];
                }),
                maxBarThickness: 42,
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
              legend: { display: false },
              tooltip: {
                backgroundColor: "rgba(15, 23, 42, 0.92)",
                padding: 10,
                cornerRadius: 8,
                displayColors: false,
                callbacks: {
                  label: (ctx) => "₱" + Number(ctx.raw || 0).toLocaleString(),
                },
              },
            },
            scales: {
              x: { grid: { display: false }, ticks: { color: tick } },
              y: {
                grid: { color: "rgba(148, 163, 184, 0.16)" },
                ticks: {
                  color: tick,
                  callback: (v) => "₱" + Number(v).toLocaleString(),
                },
                beginAtZero: true,
              },
            },
          },
        });
      }
    } catch (e) {
      /* ignore chart errors in preview */
    }
  };

  function ffPad2(n) {
    return String(n).padStart(2, "0");
  }
  function ffIsoDate(d) {
    return d.getFullYear() + "-" + ffPad2(d.getMonth() + 1) + "-" + ffPad2(d.getDate());
  }

  function ffCloseSalesCal() {
    document.querySelectorAll(".ff-cal-popover").forEach((el) => el.remove());
  }

  function ffOpenSalesCal(input) {
    ffCloseSalesCal();
    const pop = document.createElement("div");
    pop.className = "ff-cal-popover";
    pop.setAttribute("role", "dialog");
    const field = input.closest(".ff-date-field") || input.parentElement;
    const rect = (field || input).getBoundingClientRect();
    const scrollY = window.scrollY || document.documentElement.scrollTop;
    const scrollX = window.scrollX || document.documentElement.scrollLeft;
    let top = rect.bottom + scrollY + 6;
    let left = rect.left + scrollX;
    if (left + 280 > scrollX + window.innerWidth - 8) left = scrollX + window.innerWidth - 288;
    pop.style.top = top + "px";
    pop.style.left = Math.max(8, left) + "px";

    let view = input.value ? new Date(input.value + "T12:00:00") : new Date();
    if (Number.isNaN(view.getTime())) view = new Date();
    let cursor = new Date(view.getFullYear(), view.getMonth(), 1);

    function render() {
      const y = cursor.getFullYear();
      const m = cursor.getMonth();
      const monthName = cursor.toLocaleString(undefined, { month: "long", year: "numeric" });
      const firstDow = new Date(y, m, 1).getDay();
      const daysInMonth = new Date(y, m + 1, 0).getDate();
      const prevDays = new Date(y, m, 0).getDate();
      const selected = input.value;
      const todayIso = ffIsoDate(new Date());
      const dow = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        .map((d) => "<span>" + d + "</span>")
        .join("");
      let cells = "";
      for (let i = 0; i < 42; i++) {
        let dayNum;
        let cellDate;
        let muted = false;
        if (i < firstDow) {
          dayNum = prevDays - firstDow + i + 1;
          cellDate = new Date(y, m - 1, dayNum);
          muted = true;
        } else if (i >= firstDow + daysInMonth) {
          dayNum = i - (firstDow + daysInMonth) + 1;
          cellDate = new Date(y, m + 1, dayNum);
          muted = true;
        } else {
          dayNum = i - firstDow + 1;
          cellDate = new Date(y, m, dayNum);
        }
        const iso = ffIsoDate(cellDate);
        const cls = [
          "ff-cal-popover__day",
          muted ? "is-muted" : "",
          iso === todayIso ? "is-today" : "",
          iso === selected ? "is-selected" : "",
        ]
          .filter(Boolean)
          .join(" ");
        cells += '<button type="button" class="' + cls + '" data-date="' + iso + '">' + dayNum + "</button>";
      }
      pop.innerHTML =
        '<div class="ff-cal-popover__nav">' +
        '<button type="button" data-nav="-1" aria-label="Previous month">‹</button>' +
        '<div class="ff-cal-popover__title">' +
        monthName +
        "</div>" +
        '<button type="button" data-nav="1" aria-label="Next month">›</button>' +
        "</div>" +
        '<div class="ff-cal-popover__dow">' +
        dow +
        "</div>" +
        '<div class="ff-cal-popover__grid">' +
        cells +
        "</div>" +
        '<div class="ff-cal-popover__foot">' +
        '<button type="button" data-act="clear">Clear</button>' +
        '<button type="button" class="primary" data-act="today">Today</button>' +
        "</div>";
    }

    render();
    document.body.appendChild(pop);

    pop.addEventListener("click", (e) => {
      const t = e.target;
      if (!(t instanceof HTMLElement)) return;
      if (t.dataset.nav) {
        cursor.setMonth(cursor.getMonth() + Number(t.dataset.nav));
        render();
        return;
      }
      if (t.dataset.act === "clear") {
        input.value = "";
        input.dispatchEvent(new Event("change", { bubbles: true }));
        ffCloseSalesCal();
        return;
      }
      if (t.dataset.act === "today") {
        input.value = ffIsoDate(new Date());
        input.dispatchEvent(new Event("change", { bubbles: true }));
        ffCloseSalesCal();
        return;
      }
      if (t.dataset.date) {
        input.value = t.dataset.date;
        input.dispatchEvent(new Event("change", { bubbles: true }));
        ffCloseSalesCal();
      }
    });
  }

  function ffInitSalesDatePickers() {
    const section = document.getElementById("salesSection");
    if (!section) return;
    section.querySelectorAll("input.ff-date-input").forEach((input) => {
      input.setAttribute("readonly", "readonly");
      input.setAttribute("autocomplete", "off");
      // Avoid OS date chrome; custom popover handles picking
      input.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          ffOpenSalesCal(input);
        }
      });
    });
    if (section.dataset.ffCalBound === "1") return;
    section.dataset.ffCalBound = "1";
    section.addEventListener("click", (e) => {
      const field = e.target.closest && e.target.closest(".ff-date-field");
      if (!field || !section.contains(field)) return;
      const input = field.querySelector("input.ff-date-input");
      if (!input) return;
      e.preventDefault();
      ffOpenSalesCal(input);
    });
    document.addEventListener("mousedown", (e) => {
      if (!e.target.closest(".ff-cal-popover") && !e.target.closest(".ff-date-field")) {
        ffCloseSalesCal();
      }
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") ffCloseSalesCal();
    });
  }

  function ffMoney(n) {
    return "PHP " + Math.round(Number(n) || 0).toLocaleString("en-PH");
  }
  function ffScopeLabel() {
    const sel = document.getElementById("salesVendoFilter");
    const opt = sel && sel.options[sel.selectedIndex];
    return (opt && opt.textContent.trim()) || "Overall";
  }
  function ffVendoName(id) {
    const n = Number(id) || 0;
    if (!n) return "Main Router";
    const sel = document.getElementById("salesVendoFilter");
    if (sel) {
      for (let i = 0; i < sel.options.length; i++) {
        if (String(sel.options[i].value) === String(n)) return sel.options[i].textContent.trim();
      }
    }
    return "Sub Vendo " + n;
  }
  function ffResultLine(rep) {
    const month = Number(rep.monthly) || 0;
    const prev = Number(rep.prev_monthly) || 0;
    const diff = month - prev;
    if ((Number(rep.total) || 0) <= 0) return "No income recorded for this scope.";
    if (diff > 0) return "Income is up by " + ffMoney(diff) + " compared with last month.";
    if (diff < 0) return "Income is down by " + ffMoney(Math.abs(diff)) + " compared with last month.";
    return "Income this month matches last month.";
  }
  function ffReportLines(rep) {
    const when = new Date((Number(rep.generated_at) || Date.now() / 1000) * 1000);
    const rows = asArr(rep.rows);
    const lines = [
      "CEBJ.NET",
      "Piso WiFi income report",
      "Scope: " + ffScopeLabel(),
      "Generated: " + when.toLocaleString(),
      "",
      "MONEY COLLECTED",
      "Today: " + ffMoney(rep.daily),
      "This week: " + ffMoney(rep.weekly),
      "This month: " + ffMoney(rep.monthly),
      "All recorded: " + ffMoney(rep.total),
      "",
      "THIS MONTH",
      "Transactions: " + (Number(rep.month_count) || 0),
      "Coins: " + (Number(rep.month_coins) || 0),
      "Average sale: " + ffMoney(rep.month_avg),
      "Last month: " + ffMoney(rep.prev_monthly),
      "",
      "RESULT",
      ffResultLine(rep),
      "Rent, load, and other bills are not stored on this router.",
      "This figure is money collected from coins and vouchers.",
      "",
      "RECENT TRANSACTIONS",
      "Date | MAC | Coins | Amount | Where",
    ];
    if (!rows.length) lines.push("No transactions recorded.");
    rows.forEach((r) => {
      const at = new Date((Number(r.created_at) || 0) * 1000);
      lines.push(
        [at.toLocaleString(), r.mac || "", String(r.coins || 0), ffMoney(r.amount), ffVendoName(r.sub_vendo_id)].join(" | ")
      );
    });
    return lines;
  }
  function ffPdfEscape(s) {
    return String(s == null ? "" : s)
      .replace(/[^\x20-\x7E]/g, " ")
      .replace(/\\/g, "\\\\")
      .replace(/\(/g, "\\(")
      .replace(/\)/g, "\\)");
  }
  function ffPdfBytes(pages) {
    let body = "%PDF-1.4\n";
    const offsets = [0];
    const put = (n, data) => {
      offsets[n] = body.length;
      body += n + " 0 obj\n" + data + "\nendobj\n";
    };
    const kids = pages.map((_, i) => 6 + i * 2 + " 0 R");
    put(1, "<< /Type /Catalog /Pages 2 0 R >>");
    put(2, "<< /Type /Pages /Count " + pages.length + " /Kids [" + kids.join(" ") + "] >>");
    put(3, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
    put(4, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>");
    pages.forEach((content, i) => {
      const cid = 5 + i * 2;
      const pid = 6 + i * 2;
      put(cid, "<< /Length " + content.length + " >>\nstream\n" + content + "\nendstream");
      put(pid, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents " + cid + " 0 R /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> >>");
    });
    const start = body.length;
    const count = 4 + pages.length * 2;
    body += "xref\n0 " + (count + 1) + "\n0000000000 65535 f \n";
    for (let n = 1; n <= count; n++) body += String(offsets[n]).padStart(10, "0") + " 00000 n \n";
    body += "trailer << /Size " + (count + 1) + " /Root 1 0 R >>\nstartxref\n" + start + "\n%%EOF";
    return body;
  }
  function ffLinesToPdf(lines) {
    const pages = [];
    let cmds = [];
    let y = 786;
    const flush = () => {
      if (!cmds.length) return;
      pages.push("0.09 0.16 0.35 rg 0 808 595 34 re f\n0 g\n" + cmds.join("\n"));
      cmds = [];
      y = 786;
    };
    lines.forEach((raw, idx) => {
      const text = String(raw || "");
      const bold = idx < 2 || text === "MONEY COLLECTED" || text === "THIS MONTH" || text === "RESULT" || text === "RECENT TRANSACTIONS";
      const size = idx === 0 ? 18 : idx === 1 ? 13 : bold ? 12 : 10;
      const gap = text === "" ? 10 : size + 6;
      if (y < 48 + gap) flush();
      if (text !== "") {
        cmds.push("BT /" + (bold ? "F2" : "F1") + " " + size + " Tf 40 " + y + " Td (" + ffPdfEscape(text).slice(0, 110) + ") Tj ET");
      }
      y -= gap;
    });
    flush();
    if (!pages.length) pages.push("BT /F1 12 Tf 40 780 Td (CEBJ.NET) Tj ET");
    return ffPdfBytes(pages);
  }
  function ffDownloadText(name, text, type) {
    const blob = new Blob([text], { type: type || "text/plain" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1500);
  }
  window.ffLoadSalesVendos = function () {
    const group = document.getElementById("salesVendoGroup");
    if (!group) return Promise.resolve();
    const current = document.getElementById("salesVendoFilter")?.value || "all";
    return api("list_esp_devices").then((data) => {
      const devices = asArr(data.esp_devices);
      group.innerHTML = devices.length
        ? devices
            .map((d) => {
              const name = (d.slot_name || "Sub Vendo " + d.id).trim();
              return `<option value="${Number(d.id) || 0}">${esc(name)}</option>`;
            })
            .join("")
        : '<option value="" disabled>No sub vendo yet</option>';
      const sel = document.getElementById("salesVendoFilter");
      if (sel && current) sel.value = current;
    }).catch(() => {});
  };
  window.ffSalesScopeChanged = function () {
    if (typeof loadAllSales === "function") loadAllSales();
    if (typeof loadSalesHistory === "function") loadSalesHistory();
  };
  window.ffExportSales = function () {
    const kind = (document.getElementById("salesExportKind") || {}).value || "pdf";
    api("sales_report").then((rep) => {
      if (!rep || rep.status === "error") {
        toast((rep && rep.message) || "Could not build the report", "error");
        return;
      }
      const lines = ffReportLines(rep);
      const stamp = new Date().toISOString().slice(0, 10);
      const scope = ffScopeLabel().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "overall";
      if (kind === "csv") {
        const csv = "\uFEFF" + lines.map((line) => '"' + String(line).replace(/"/g, '""') + '"').join("\r\n") + "\r\n";
        ffDownloadText("cebj-income-" + stamp + "-" + scope + ".csv", csv, "text/csv;charset=utf-8");
      } else {
        ffDownloadText("cebj-income-" + stamp + "-" + scope + ".pdf", ffLinesToPdf(lines), "application/pdf");
      }
      toast("Report downloaded", "success");
    }).catch(() => toast("Could not build the report", "error"));
  };
  window.exportSales = function () { window.ffExportSales(); };
  window.ffQuickAction = function (key) {
    const go = {
      update: () => typeof showUpdate === "function" && showUpdate(),
      sales: () => typeof showSales === "function" && showSales(),
      sessions: () => typeof showSessions === "function" && showSessions(),
      ap: () => typeof showAccessPoints === "function" && showAccessPoints(),
      vouchers: () => typeof showVouchers === "function" && showVouchers(),
      vendo: () => typeof showESPSlots === "function" && showESPSlots(),
      network: () => typeof showNetwork === "function" && showNetwork(),
      reboot: () => typeof confirmReboot === "function" && confirmReboot(),
    };
    if (go[key]) go[key]();
  };

  const _ffShowSales = typeof window.showSales === "function" ? window.showSales : null;
  window.showSales = function () {
    if (_ffShowSales) _ffShowSales.apply(this, arguments);
    else if (typeof window.showSection === "function") window.showSection("salesSection");
    setTimeout(() => {
      ffInitSalesDatePickers();
      ffLoadSalesVendos();
      if (typeof hydrateIcons === "function") hydrateIcons();
      if (typeof loadSalesChart === "function") loadSalesChart();
    }, 50);
  };

  function ffSetGcashReady(id, value, ok) {
    const card = document.getElementById(id);
    const val = document.getElementById(id + "Val");
    if (val) val.textContent = value;
    if (!card) return;
    card.classList.toggle("is-ok", !!ok);
    card.classList.toggle("is-warn", !ok);
  }

  window.ffPortalFileChanged = function (input, labelId) {
    const nameEl = document.getElementById(labelId);
    const file = input && input.files && input.files[0];
    if (!nameEl) return;
    if (file) {
      nameEl.textContent = file.name;
      nameEl.classList.add("has-file");
      nameEl.title = file.name;
    } else {
      nameEl.textContent = "No file chosen";
      nameEl.classList.remove("has-file");
      nameEl.title = "";
    }
    if (typeof hydrateIcons === "function") hydrateIcons();
  };

  window.ffGcashQrFileChanged = function (input) {
    window.ffPortalFileChanged(input, "gcashQrFileName");
  };

  window.ffSyncGcashEnableBtn = function () {
    const chk = document.getElementById("gcashEnabled");
    const btn = document.getElementById("gcashEnableBtn");
    if (!chk || !btn) return;
    const on = !!chk.checked;
    btn.classList.toggle("is-on", on);
    btn.textContent = on ? "GCash Enabled" : "Enable GCash";
    btn.setAttribute("aria-pressed", on ? "true" : "false");
  };

  window.ffToggleGcashEnabled = function () {
    const chk = document.getElementById("gcashEnabled");
    if (!chk) return;
    const next = !chk.checked;
    chk.checked = next;
    window.ffSyncGcashEnableBtn();

    const g = (id) => document.getElementById(id);
    const params = new URLSearchParams({
      action: "gcash_config_set",
      enabled: next ? "1" : "0",
      freewindow_enabled: g("gcashFreewindowEnabled")?.checked ? "1" : "0",
      gcash_number: g("gcashNumber")?.value || "",
      gcash_qr: g("gcashQr")?.value || "",
      voucher_expiry_days: g("gcashVoucherExpiry")?.value || "0",
    });

    fetch("/cgi-bin/api?" + params.toString(), { credentials: "include", cache: "no-store" })
      .then((r) => r.json())
      .then((data) => {
        if (!data || data.status !== "ok") {
          chk.checked = !next;
          window.ffSyncGcashEnableBtn();
          if (typeof showToast === "function") {
            showToast((data && data.message) || "Could not update GCash", "error");
          }
          return;
        }
        if (typeof showToast === "function") {
          showToast(next ? "GCash enabled" : "GCash disabled", next ? "success" : "error");
        }
        const secretVal = (g("gcashSecretDisplay")?.value || "").trim();
        window.updateGcashReadyCards({
          enabled: next,
          gcash_number: g("gcashNumber")?.value || "",
          gcash_qr: g("gcashQr")?.value || "",
          has_secret: !!secretVal && !/^not generated$/i.test(secretVal),
          pool: [],
        });
        // Refresh inventory only — do not wipe enable button state
        fetch("/cgi-bin/api?action=gcash_config_get", { credentials: "include", cache: "no-store" })
          .then((r) => r.json())
          .then((cfg) => {
            if (!cfg || cfg.status !== "ok") return;
            chk.checked = !!(cfg.enabled === true || cfg.enabled === 1 || cfg.enabled === "1");
            window.ffSyncGcashEnableBtn();
            if (typeof renderGcashPool === "function") renderGcashPool(cfg.pool || []);
            window.updateGcashReadyCards(cfg);
          })
          .catch(() => {});
      })
      .catch(() => {
        chk.checked = !next;
        window.ffSyncGcashEnableBtn();
        if (typeof showToast === "function") showToast("Network error", "error");
      });
  };

  window.updateGcashReadyCards = function (data) {
    const enabled = !!(
      data &&
      (data.enabled === true || data.enabled === 1 || data.enabled === "1")
    );
    const number = ((data && data.gcash_number) || "").trim();
    const qr = ((data && data.gcash_qr) || "").trim();
    const hasSecret = !!(data && data.has_secret);
    const pool = (data && data.pool) || [];
    const available = pool.reduce((n, p) => n + (Number(p.active) || 0), 0);
    ffSetGcashReady("gcashReadyEnabled", enabled ? "Enabled" : "Off", enabled);
    ffSetGcashReady("gcashReadyPay", number || (qr ? "QR only" : "Missing"), !!(number || qr));
    ffSetGcashReady("gcashReadySecret", hasSecret ? "Ready" : "Missing", hasSecret);
    ffSetGcashReady("gcashReadyPool", String(available), available > 0);
    const chk = document.getElementById("gcashEnabled");
    if (chk && data && Object.prototype.hasOwnProperty.call(data, "enabled")) {
      chk.checked = enabled;
    }
    window.ffSyncGcashEnableBtn();
  };

  function ffEnhanceGcashPage() {
    window.loadGcashConfig = function () {
      fetch("/cgi-bin/api?action=gcash_config_get", { credentials: "include", cache: "no-store" })
        .then((r) => r.json())
        .then((data) => {
          if (!data || data.status !== "ok") return;
          const set = (id, v) => {
            const el = document.getElementById(id);
            if (el) el.value = v;
          };
          const chk = (id, v) => {
            const el = document.getElementById(id);
            if (el) el.checked = !!v;
          };
          chk("gcashEnabled", data.enabled === true || data.enabled === 1 || data.enabled === "1");
          window.ffSyncGcashEnableBtn();
          chk("gcashFreewindowEnabled", data.freewindow_enabled === true || data.freewindow_enabled === 1 || data.freewindow_enabled === "1");
          set("gcashNumber", data.gcash_number || "");
          set("gcashQr", data.gcash_qr || "");
          set("gcashVoucherExpiry", data.voucher_expiry_days ?? 0);
          const qrPrev = document.getElementById("gcashQrPreview");
          if (qrPrev) {
            const qr = data.gcash_qr || "";
            if (qr) {
              qrPrev.src = qr;
              qrPrev.style.display = "block";
            } else {
              qrPrev.src = "";
              qrPrev.style.display = "none";
            }
          }
          const secDisp = document.getElementById("gcashSecretDisplay");
          if (secDisp) {
            secDisp.value = data.has_secret
              ? "Set (hidden — Generate to view a new one)"
              : "Not generated";
          }
          if (typeof renderGcashPool === "function") renderGcashPool(data.pool || []);
          window.updateGcashReadyCards(data);
          if (typeof hydrateIcons === "function") hydrateIcons();
        })
        .catch((e) => console.warn("loadGcashConfig failed:", e));
    };

    const afterMutate = () => {
      if (typeof window.loadGcashConfig === "function") window.loadGcashConfig();
    };
    // Do NOT wrap generateGcashSecret — reload would hide the one-time plaintext secret.
    ["generateGcashPool", "saveGcashConfig", "uploadGcashQr"].forEach((name) => {
      const fn = window[name];
      if (typeof fn !== "function" || fn._ffReadyBound) return;
      window[name] = function () {
        const ret = fn.apply(this, arguments);
        setTimeout(afterMutate, 700);
        return ret;
      };
      window[name]._ffReadyBound = true;
    });
    if (typeof window.generateGcashSecret === "function" && !window.generateGcashSecret._ffReadyBound) {
      const genSecret = window.generateGcashSecret;
      window.generateGcashSecret = function () {
        const ret = genSecret.apply(this, arguments);
        setTimeout(() => {
          window.updateGcashReadyCards({
            enabled: document.getElementById("gcashEnabled")?.checked,
            gcash_number: document.getElementById("gcashNumber")?.value,
            gcash_qr: document.getElementById("gcashQr")?.value,
            has_secret: true,
            pool: [],
          });
          // Refresh pool counts only (leave secret display alone)
          fetch("/cgi-bin/api?action=gcash_config_get", { credentials: "include", cache: "no-store" })
            .then((r) => r.json())
            .then((data) => {
              if (data && data.status === "ok") {
                if (typeof renderGcashPool === "function") renderGcashPool(data.pool || []);
                window.updateGcashReadyCards({ ...data, has_secret: true });
              }
            })
            .catch(() => {});
        }, 500);
        return ret;
      };
      window.generateGcashSecret._ffReadyBound = true;
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    if (localStorage.getItem("fastfi_admin_logged") === "yes") {
      setTimeout(() => {
        ffLoadBranding();
        ffLoadDashboardOverview();
        if (typeof highlightSidebar === "function") {
          highlightSidebar((location.hash || "#dashboard").replace(/^#/, "") || "dashboard");
        }
      }, 800);
    }
    ffInitSalesDatePickers();
    ffEnhanceGcashPage();
    ffBindOtaPage();
  });
})();

function ffBindOtaPage() {
  var card = document.getElementById("otaReleaseCard");
  var btnCheck = document.getElementById("btnOTA_Check");
  if (!card || !btnCheck) return;
  var btnProceed = document.getElementById("btnOTA_Proceed");
  if (btnProceed) {
    btnProceed.onclick = function () {
      if (typeof ffConfirm !== "function") return;
      ffConfirm("Apply this update now? The router will reboot and active sessions will disconnect.", {
        title: "Apply Update",
        okText: "Apply Update",
        okClass: "btn btn-warning btn-sm",
        onConfirm: function () {
          btnProceed.disabled = true;
          if (typeof window.ffBeginFlashLock === "function") window.ffBeginFlashLock("ota");
          fetch("/cgi-bin/api?action=proceed_update", { method: "POST", credentials: "include" })
            .then(function (r) { return r.json(); })
            .then(function (data) {
              if (data && data.status === "ok") {
                if (typeof window.ffMarkFlashAccepted === "function") {
                  window.ffMarkFlashAccepted(data.message || "Applying update. Do not unplug.");
                }
              } else {
                if (typeof window.ffEndFlashLock === "function") window.ffEndFlashLock();
                btnProceed.disabled = false;
                if (typeof showToast === "function") showToast((data && data.message) || "Update failed to start", "error");
              }
            })
            .catch(function () {
              if (typeof window.ffEndFlashLock === "function") window.ffEndFlashLock();
              btnProceed.disabled = false;
              if (typeof showToast === "function") showToast("Update failed to start.", "error");
            });
        }
      });
    };
  }
  card.style.display = "block";
  fetch("/version.txt?t=" + Date.now())
    .then(function (r) { return r.text(); })
    .then(function (v) {
      v = String(v || "").trim();
      var cur = document.getElementById("otaCurrentVersion");
      var label = document.getElementById("currentVersionLabel");
      if (v && cur) cur.textContent = v;
      if (v && label && (label.textContent === "--" || !label.textContent)) label.textContent = v;
    })
    .catch(function () {});

  function esc(s) {
    return String(s || "").replace(/[&<>]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c];
    });
  }
  function releaseLines(raw) {
    var skip = false;
    var out = [];
    String(raw || "").replace(/\r/g, "").split("\n").forEach(function (rawLine) {
      var line = rawLine.trim();
      if (!line) return;
      var heading = line.match(/^#{1,6}\s+(.+)$/);
      if (heading) {
        var title = heading[1].toLowerCase();
        skip = /asset|flash|this router|contact/.test(title);
        return;
      }
      if (skip || line.charAt(0) === "|" || /^contact:/i.test(line) || /^-{3,}$/.test(line)) return;
      line = line.replace(/^[-*]\s+/, "").replace(/\*\*/g, "").replace(/`/g, "");
      if (line) out.push(line);
    });
    return out;
  }
  function showRelease(data) {
    card.style.display = "block";
    var cur = document.getElementById("otaCurrentVersion");
    var lat = document.getElementById("otaLatestVersion");
    var badge = document.getElementById("otaUpdateStatus");
    var notes = document.getElementById("otaReleaseNotes");
    var label = document.getElementById("currentVersionLabel");
    if (cur) cur.textContent = data.current || (label && label.textContent) || "--";
    if (lat) lat.textContent = data.latest || data.version || "--";
    if (notes) {
      var items = releaseLines(data.notes);
      if (!items.length && data.message) items = [String(data.message)];
      if (!items.length) items = ["No release notes."];
      notes.innerHTML = items.map(function (line) {
        return '<li>' + esc(line) + "</li>";
      }).join("");
    }
    if (!badge) return;
    badge.className = "ota-status";
    if (data.status === "available") {
      badge.classList.add("is-available");
      badge.textContent = "Update Available";
    } else if (data.status === "uptodate") {
      badge.classList.add("is-current");
      badge.textContent = "Up to date";
    } else {
      badge.classList.add("is-fail");
      badge.textContent = "Check failed";
    }
  }

  btnCheck.onclick = function () {
    btnCheck.disabled = true;
    var btnProceed = document.getElementById("btnOTA_Proceed");
    if (btnProceed) btnProceed.disabled = true;
    fetch("/cgi-bin/api?action=check_update", { method: "POST", credentials: "include" })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        data = data || {};
        showRelease(data);
        if (data.status === "uptodate") {
          if (typeof setRollbackBusy === "function") setRollbackBusy(false);
          if (typeof showToast === "function") showToast("Router is up to date", "info");
        } else if (data.status === "available") {
          if (typeof setRollbackBusy === "function") setRollbackBusy(true);
          var container = document.getElementById("otaProgressContainer");
          var bar = document.getElementById("otaProgressBar");
          var label = document.getElementById("otaProgressLabel");
          if (container) container.style.display = "block";
          if (bar) bar.style.width = "10%";
          if (label) label.textContent = "Contacting GitHub...";
          if (typeof showToast === "function") showToast("Update available. Downloading…", "info");
          if (window.otaLogInterval) clearInterval(window.otaLogInterval);
          window.otaLogInterval = setInterval(function () {
            fetch("/cgi-bin/api?action=update_progress&t=" + Date.now(), { credentials: "include" })
              .then(function (r) { return r.json(); })
              .then(function (prog) {
                var text = (prog && prog.progress) || "";
                if (!text) return;
                var lines = text.trim().split("\n");
                var lastLine = lines[lines.length - 1];
                if (label && lastLine.indexOf("Download complete") === -1) {
                  label.textContent = lastLine;
                  if (bar && parseInt(bar.style.width, 10) < 90) {
                    bar.style.width = (parseInt(bar.style.width, 10) + 5) + "%";
                  }
                }
                if (text.indexOf("Download complete") !== -1) {
                  if (typeof setRollbackBusy === "function") setRollbackBusy(false);
                  if (btnProceed) btnProceed.disabled = false;
                  if (bar) {
                    bar.style.width = "100%";
                    bar.classList.remove("progress-bar-animated");
                  }
                  if (label) label.textContent = "Download complete. Ready to flash.";
                  clearInterval(window.otaLogInterval);
                  if (typeof showToast === "function") showToast("Download complete. Ready to flash.", "success");
                }
              });
          }, 1500);
        } else if (typeof showToast === "function") {
          if (typeof setRollbackBusy === "function") setRollbackBusy(false);
          showToast(data.message || "Error checking update", "error");
        }
        if (data.status !== "available") btnCheck.disabled = false;
      })
      .catch(function () {
        btnCheck.disabled = false;
        showRelease({ status: "error", message: "Could not reach the router." });
      });
  };

  var autoToggle = document.getElementById("otaAutoToggle");
  var scheduleStatus = document.getElementById("otaScheduleStatus");
  var releaseSelect = document.getElementById("otaReleaseSelect");
  var selectedDetail = document.getElementById("otaSelectedDetail");
  var rollbackStatus = document.getElementById("otaRollbackStatus");
  var btnLoad = document.getElementById("btnOTA_Load");
  var btnDownload = document.getElementById("btnOTA_Download");
  var btnInstall = document.getElementById("btnOTA_Install");
  var loadedTag = "";
  var rollbackBusy = false;

  function resultText(data) {
    var result = (data && data.last_result) || "";
    var when = (data && data.last_check) || "";
    var detail = (data && data.detail) || "";
    var clock = (data && String(data.clock_ok) === "0");
    var line = "Scheduled time: 2:00 PM.";
    if (clock || result === "clock_invalid") {
      return line + " Router clock is not synchronized, so the 2:00 PM update did not run.";
    }
    if (!result) return line + " No scheduled check yet.";
    var label = {
      uptodate: "No newer release.",
      installing: "Check started.",
      error: "Check failed.",
      deferred: "Deferred because customers are online.",
      busy: "Skipped because another update is running.",
      started: "Check started."
    }[result] || result;
    return line + " Last check" + (when ? " " + when : "") + ": " + (detail || label);
  }

  function paintSchedule(data) {
    data = data || {};
    if (autoToggle) autoToggle.checked = String(data.enabled) === "1" || data.enabled === 1;
    if (scheduleStatus) scheduleStatus.textContent = resultText(data);
  }

  function setRollbackBusy(on) {
    rollbackBusy = !!on;
    if (btnCheck) btnCheck.disabled = rollbackBusy;
    if (btnProceed && rollbackBusy) btnProceed.disabled = true;
    if (btnLoad) btnLoad.disabled = rollbackBusy || !releaseSelect || !releaseSelect.value;
    if (btnDownload) btnDownload.disabled = rollbackBusy || !loadedTag;
    if (btnInstall && rollbackBusy) btnInstall.disabled = true;
    if (autoToggle) autoToggle.disabled = rollbackBusy;
    if (releaseSelect) releaseSelect.disabled = rollbackBusy;
  }

  function postAction(action, body) {
    return fetch("/cgi-bin/api?action=" + action, {
      method: "POST",
      credentials: "include",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body || {})
    }).then(function (r) { return r.json(); });
  }

  if (autoToggle) {
    fetch("/cgi-bin/api?action=ota_schedule_get", { credentials: "include" })
      .then(function (r) { return r.json(); })
      .then(paintSchedule)
      .catch(function () {
        if (scheduleStatus) scheduleStatus.textContent = "Scheduled time: 2:00 PM. Could not read the saved setting.";
      });
    autoToggle.addEventListener("change", function () {
      var want = autoToggle.checked ? "1" : "0";
      autoToggle.disabled = true;
      postAction("ota_schedule_set", { enabled: want })
        .then(function (data) {
          autoToggle.disabled = rollbackBusy;
          if (!data || data.status !== "ok") {
            autoToggle.checked = want !== "1";
            if (typeof showToast === "function") showToast((data && data.message) || "Could not save automatic updates", "error");
            return;
          }
          paintSchedule(data);
          if (typeof showToast === "function") showToast(data.message || "Saved", "success");
        })
        .catch(function () {
          autoToggle.disabled = false;
          autoToggle.checked = want !== "1";
          if (typeof showToast === "function") showToast("Could not save automatic updates", "error");
        });
    });
  }

  function selectedRelease() {
    if (!releaseSelect) return null;
    var opt = releaseSelect.options[releaseSelect.selectedIndex];
    if (!opt || !opt.value) return null;
    return {
      tag: opt.value,
      version: opt.getAttribute("data-version") || "",
      published: opt.getAttribute("data-published") || "",
      current: opt.getAttribute("data-current") === "1",
      notes: opt.getAttribute("data-notes") || ""
    };
  }

  function paintSelected(rel, extra) {
    if (!selectedDetail) return;
    if (!rel) {
      selectedDetail.textContent = "Select a release, then Load. Loading does not install firmware.";
      return;
    }
    var lines = [
      (rel.current ? "Installed version: " : "Selected version: ") + (rel.version || rel.tag),
      "Tag: " + rel.tag,
      rel.published ? "Published: " + rel.published : ""
    ];
    var noteLines = releaseLines(rel.notes).slice(0, 4);
    if (noteLines.length) lines.push(noteLines.join(" "));
    if (extra) lines.push(extra);
    selectedDetail.textContent = lines.filter(Boolean).join("\n");
  }

  function refreshReleaseChoices() {
    if (!releaseSelect) return;
    releaseSelect.disabled = true;
    fetch("/cgi-bin/api?action=ota_releases", { credentials: "include" })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        releaseSelect.innerHTML = "";
        var placeholder = document.createElement("option");
        placeholder.value = "";
        if (!data || data.status !== "ok") {
          placeholder.textContent = "Could not load releases";
          releaseSelect.appendChild(placeholder);
          if (rollbackStatus) rollbackStatus.textContent = (data && data.message) || "GitHub releases could not be loaded.";
          return;
        }
        var rows = data.releases || [];
        if (!rows.length) {
          placeholder.textContent = "No eligible releases";
          releaseSelect.appendChild(placeholder);
          if (rollbackStatus) rollbackStatus.textContent = "No production release with update.tar.gz was found.";
          return;
        }
        placeholder.textContent = "Select a release";
        releaseSelect.appendChild(placeholder);
        rows.forEach(function (rel) {
          var opt = document.createElement("option");
          opt.value = rel.tag;
          opt.setAttribute("data-version", rel.version || "");
          opt.setAttribute("data-published", rel.published || "");
          opt.setAttribute("data-current", String(rel.current) === "1" ? "1" : "0");
          opt.setAttribute("data-notes", rel.notes || "");
          opt.textContent = (rel.version || rel.tag) + (String(rel.current) === "1" ? " (installed)" : "") + (rel.published ? " — " + String(rel.published).slice(0, 10) : "");
          releaseSelect.appendChild(opt);
        });
        if (rollbackStatus) rollbackStatus.textContent = "";
      })
      .catch(function () {
        if (rollbackStatus) rollbackStatus.textContent = "GitHub releases could not be loaded.";
      })
      .then(function () {
        if (releaseSelect) releaseSelect.disabled = rollbackBusy;
        loadedTag = "";
        if (btnDownload) btnDownload.disabled = true;
        if (btnInstall) btnInstall.disabled = true;
        if (btnLoad) btnLoad.disabled = rollbackBusy || !releaseSelect || !releaseSelect.value;
      });
  }

  if (releaseSelect) {
    releaseSelect.addEventListener("change", function () {
      loadedTag = "";
      if (btnDownload) btnDownload.disabled = true;
      if (btnInstall) btnInstall.disabled = true;
      if (btnLoad) btnLoad.disabled = rollbackBusy || !releaseSelect.value;
      paintSelected(selectedRelease());
    });
    refreshReleaseChoices();
  }

  if (btnLoad) {
    btnLoad.addEventListener("click", function () {
      var rel = selectedRelease();
      if (!rel || rollbackBusy) return;
      btnLoad.disabled = true;
      if (rollbackStatus) rollbackStatus.textContent = "Loading " + rel.tag + "…";
      postAction("ota_load_release", { tag: rel.tag })
        .then(function (data) {
          btnLoad.disabled = rollbackBusy || !releaseSelect.value;
          if (!data || data.status !== "ok") {
            loadedTag = "";
            if (btnDownload) btnDownload.disabled = true;
            if (rollbackStatus) rollbackStatus.textContent = (data && data.message) || "Could not load that release.";
            return;
          }
          loadedTag = data.tag || rel.tag;
          var same = String(data.same) === "1";
          paintSelected({
            tag: loadedTag,
            version: data.version || rel.version,
            published: data.published || rel.published,
            current: same,
            notes: data.notes || rel.notes
          }, same ? "This is the installed version. Nothing will be downloaded." : "Loaded. Download validates the file and does not install it.");
          if (btnDownload) btnDownload.disabled = rollbackBusy || same;
          if (btnInstall) btnInstall.disabled = true;
          if (rollbackStatus) rollbackStatus.textContent = data.message || "Release loaded.";
        })
        .catch(function () {
          btnLoad.disabled = false;
          if (rollbackStatus) rollbackStatus.textContent = "Could not load that release.";
        });
    });
  }

  function watchSelectedDownload(tag) {
    var bar = document.getElementById("otaProgressBar");
    var label = document.getElementById("otaProgressLabel");
    var container = document.getElementById("otaProgressContainer");
    if (container) container.style.display = "block";
    if (window.otaLogInterval) clearInterval(window.otaLogInterval);
    window.otaLogInterval = setInterval(function () {
      fetch("/cgi-bin/api?action=update_progress&t=" + Date.now(), { credentials: "include" })
        .then(function (r) { return r.json(); })
        .then(function (prog) {
          var text = (prog && prog.progress) || "";
          if (!text) return;
          var lines = text.trim().split("\n");
          var lastLine = lines[lines.length - 1];
          if (label && lastLine.indexOf("Download complete") === -1 && lastLine.indexOf("FATAL") === -1) {
            label.textContent = lastLine;
          }
          if (text.indexOf("FATAL") !== -1 || text.indexOf("CHECKSUM MISMATCH") !== -1) {
            clearInterval(window.otaLogInterval);
            setRollbackBusy(false);
            if (btnInstall) btnInstall.disabled = true;
            if (label) label.textContent = lastLine;
            if (rollbackStatus) rollbackStatus.textContent = lastLine;
            return;
          }
          if (text.indexOf("Download complete") !== -1) {
            clearInterval(window.otaLogInterval);
            postAction("ota_stage_release", { tag: tag })
              .then(function (data) {
                setRollbackBusy(false);
                if (!data || data.status !== "ok") {
                  if (btnInstall) btnInstall.disabled = true;
                  if (rollbackStatus) rollbackStatus.textContent = (data && data.message) || "Validation failed. Firmware was not installed.";
                  return;
                }
                if (bar) bar.style.width = "100%";
                if (label) label.textContent = "Validated " + (data.version || tag) + ". Confirm install to flash it.";
                if (btnInstall) btnInstall.disabled = false;
                if (rollbackStatus) rollbackStatus.textContent = data.message || "";
              })
              .catch(function () {
                setRollbackBusy(false);
                if (btnInstall) btnInstall.disabled = true;
                if (rollbackStatus) rollbackStatus.textContent = "Validation failed. Firmware was not installed.";
              });
          }
        });
    }, 1500);
  }

  if (btnDownload) {
    btnDownload.addEventListener("click", function () {
      if (!loadedTag || rollbackBusy) return;
      var tag = loadedTag;
      setRollbackBusy(true);
      if (btnInstall) btnInstall.disabled = true;
      var container = document.getElementById("otaProgressContainer");
      var bar = document.getElementById("otaProgressBar");
      var label = document.getElementById("otaProgressLabel");
      if (container) container.style.display = "block";
      if (bar) bar.style.width = "10%";
      if (label) label.textContent = "Downloading " + tag + "…";
      postAction("ota_download_release", { tag: tag })
        .then(function (data) {
          if (!data || data.status !== "ok") {
            setRollbackBusy(false);
            if (rollbackStatus) rollbackStatus.textContent = (data && data.message) || "Download did not start.";
            return;
          }
          if (rollbackStatus) rollbackStatus.textContent = data.message || "";
          watchSelectedDownload(tag);
        })
        .catch(function () {
          setRollbackBusy(false);
          if (rollbackStatus) rollbackStatus.textContent = "Download did not start.";
        });
    });
  }

  if (btnInstall) {
    btnInstall.addEventListener("click", function () {
      if (!loadedTag || rollbackBusy || typeof ffConfirm !== "function") return;
      var tag = loadedTag;
      var rel = selectedRelease();
      var ver = (rel && rel.version) || tag;
      ffConfirm("Install " + ver + " (" + tag + ")? The router will reboot and disconnect active sessions. Automatic updates will be turned off and will stay off until you turn them on again.", {
        title: "Install selected version",
        okText: "Install and reboot",
        okClass: "btn btn-warning btn-sm",
        onConfirm: function () {
          setRollbackBusy(true);
          if (typeof window.ffBeginFlashLock === "function") window.ffBeginFlashLock("ota");
          postAction("ota_install_release", { tag: tag })
            .then(function (data) {
              if (!data || data.status !== "ok") {
                setRollbackBusy(false);
                if (typeof window.ffEndFlashLock === "function") window.ffEndFlashLock();
                if (rollbackStatus) rollbackStatus.textContent = (data && data.message) || "Install did not start.";
                return;
              }
              if (autoToggle) autoToggle.checked = false;
              if (scheduleStatus) scheduleStatus.textContent = "Scheduled time: 2:00 PM. Automatic updates are off after installing " + ver + ".";
              if (rollbackStatus) rollbackStatus.textContent = data.message || "";
              if (typeof window.ffMarkFlashAccepted === "function") window.ffMarkFlashAccepted(data.message || "Installing. Do not unplug.");
            })
            .catch(function () {
              setRollbackBusy(false);
              if (typeof window.ffEndFlashLock === "function") window.ffEndFlashLock();
              if (rollbackStatus) rollbackStatus.textContent = "Install did not start.";
            });
        }
      });
    });
  }
}
