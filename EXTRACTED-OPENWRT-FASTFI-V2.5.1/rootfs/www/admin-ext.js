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

  const toast = (m, t) => {
    if (typeof showToast === "function") showToast(m, t || "info");
    else console.log(t, m);
  };

  const peso = (n) => "₱" + Number(n || 0).toLocaleString();

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
      "plansSection",
      "bandwidthSection",
      "planClientsSection",
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

  window.showPlans = () => showSec("plansSection", "plans", ffLoadPlans);
  window.showBandwidth = () => showSec("bandwidthSection", "bandwidth", ffLoadProfiles);
  window.showPlanClients = () => showSec("planClientsSection", "plan-clients", ffLoadPlanClients);
  window.showDevices = () => showSec("devicesSection", "devices", () => {
    ffLoadDevices();
    ffLoadBlocks();
  });
  window.showWaitingQueue = () => showSec("waitingSection", "waiting", ffLoadWaiting);
  window.showRadioStatus = () => showSec("radioSection", "radio", ffLoadRadios);
  window.showPricingHub = function () {
    toast("Pricing Hub removed — use Coin Rates and Plans instead", "info");
    showPlans();
  };

  const PAGE_META = {
    dashboard: ["Dashboard", "Overview of your CEBJ.NET system"],
    sales: ["Sales", "Revenue and transaction history"],
    rates: ["Coin Rates", "Insert-coin pricing tiers"],
    plans: ["Plans", "Subscription / timed plans"],
    bandwidth: ["Bandwidth", "Speed profiles and current traffic"],
    "plan-clients": ["Plan Clients", "Households and named customers"],
    sessions: ["Sessions", "Active and paused internet sessions"],
    devices: ["Devices", "LAN / Wi‑Fi clients"],
    waiting: ["Waiting Queue", "Unauthenticated clients"],
    vouchers: ["Vouchers", "Generate and manage vouchers"],
    gcash: ["GCash", "GCash pay and companion pool"],
    "captive-portal": ["Captive Portal", "Banner and portal audio"],
    network: ["Network", "WAN, DHCP, and Shield"],
    "access-points": ["Access Points", "Built-in radios and LAN APs"],
    wifi: ["WiFi SSID", "Public and private SSIDs"],
    radio: ["Radio Status", "Built-in Ruijie Wi‑Fi radios"],
    settings: ["Settings", "License, security, and branding"],
    operators: ["Operators", "RBAC users and audit log"],
    reports: ["Reports", "Sales summaries"],
    "remote-access": ["Remote Access", "On-demand Tailscale (optional)"],
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
  window.showReports = () => showSec("reportsSection", "reports", () => {
    ffLoadReport("day");
    ffLoadVendoSales();
  });

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
  window.showRemoteAccess = () => showSec("remoteAccessSection", "remote-access", ffLoadTailscale);

  // ---- Tailscale remote access (on-demand) ----
  function ffTsSetBadge(el, on, onText, offText) {
    if (!el) return;
    el.className = "badge " + (on ? "bg-success" : "bg-danger");
    el.textContent = on ? onText : offText;
  }

  window.ffLoadTailscale = function () {
    api("tailscale_status").catch(() => api("remote_access")).then((d) => {
      if (!d) return;
      const installed = Number(d.installed) === 1;
      const daemon = Number(d.daemon_running) === 1;
      const connected = Number(d.connected) === 1 || Number(d.vpn_connected) === 1;
      const ip = d.ip || d.vpn_ip || "";
      const adminUrl = d.admin_url || d.remote_url || (ip ? "http://" + ip + "/admin.html" : "");
      const inst = document.getElementById("tsInstalled");
      if (inst) inst.textContent = installed ? "Yes" : "No";
      const daemonEl = document.getElementById("tsDaemon");
      if (daemonEl) {
        daemonEl.className = "badge " + (daemon ? "bg-warning text-dark" : "bg-secondary");
        daemonEl.textContent = daemon ? "Running" : "Stopped";
      }
      ffTsSetBadge(document.getElementById("vpnStatus"), connected, "Connected", "Stopped");
      const ipEl = document.getElementById("vpnIP");
      if (ipEl) ipEl.textContent = ip || "—";
      const urlEl = document.getElementById("remoteURL");
      if (urlEl) {
        if (adminUrl) {
          urlEl.href = adminUrl;
          urlEl.textContent = adminUrl;
        } else {
          urlEl.removeAttribute("href");
          urlEl.textContent = "—";
        }
      }
      const msg = document.getElementById("tsMessage");
      if (msg) msg.textContent = d.message || "";
      const loginWrap = document.getElementById("tsLoginUrlWrap");
      const loginA = document.getElementById("tsLoginUrl");
      if (loginWrap && loginA) {
        if (d.login_url) {
          loginWrap.classList.remove("hidden");
          loginA.href = d.login_url;
          loginA.textContent = d.login_url;
        } else {
          loginWrap.classList.add("hidden");
        }
      }
      const startBtn = document.getElementById("toggleVpnBtn");
      if (startBtn) {
        startBtn.disabled = connected;
        startBtn.innerHTML = connected
          ? '<i data-icon="check" data-size="16"></i> Connected'
          : '<i data-icon="power" data-size="16"></i> Start remote';
        if (typeof refreshIcons === "function") refreshIcons();
      }
    });
  };

  window.ffTailscaleInstall = function (btn) {
    if (btn) btn.disabled = true;
    api("tailscale_install", { method: "POST", body: {} })
      .then((d) => {
        toast(d.message || (d.status === "ok" ? "Installed" : "Failed"), d.status === "ok" ? "success" : "error");
        ffLoadTailscale();
      })
      .finally(() => {
        if (btn) btn.disabled = false;
      });
  };

  window.ffTailscaleStart = function (btn) {
    const key = (document.getElementById("remoteToken") || {}).value || "";
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = '<span class="spinner-border spinner-border-sm me-2"></span>Starting…';
    }
    api("tailscale_up", { method: "POST", body: { auth_key: key } })
      .catch(() => api("remote_access_connect", { method: "POST", body: { auth_key: key, token: key } }))
      .then((d) => {
        toast(d.message || (d.status === "ok" ? "Started" : "Failed"), d.status === "ok" ? "success" : "error");
        ffLoadTailscale();
      })
      .finally(() => {
        if (btn) {
          btn.disabled = false;
          btn.innerHTML = '<i data-icon="power" data-size="16"></i> Start remote';
          if (typeof refreshIcons === "function") refreshIcons();
        }
      });
  };

  window.ffTailscaleStop = function (btn) {
    if (btn) btn.disabled = true;
    api("tailscale_down", { method: "POST", body: {} })
      .catch(() => api("remote_access_disconnect", { method: "POST", body: {} }))
      .then((d) => {
        toast(d.message || "Stopped", d.status === "ok" ? "success" : "error");
        ffLoadTailscale();
      })
      .finally(() => {
        if (btn) btn.disabled = false;
      });
  };

  // Override legacy FastFi VPN helpers if admin.js still calls them
  window.loadRemoteAccessStatus = function () {
    ffLoadTailscale();
  };
  window.toggleVPN = function (btn) {
    ffTailscaleStart(btn);
  };
  window.enrollRemoteAccess = function () {
    ffTailscaleStart(document.getElementById("toggleVpnBtn"));
  };

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
      if (!data || data.status !== "ok") return;
      const k = data.kpis || {};
      const el = (id) => document.getElementById(id);
      if (el("sysSalesToday")) el("sysSalesToday").innerText = peso(k.sales_today);
      if (el("sysSalesMonth")) el("sysSalesMonth").innerText = peso(k.sales_month);
      if (el("sysSalesWeek")) el("sysSalesWeek").innerText = peso(k.sales_week);
      if (el("connectedCount")) el("connectedCount").innerText = k.connected ?? 0;
      if (el("totalClients")) el("totalClients").innerText = k.sessions ?? 0;
      if (el("sysUptime") && data.ruijie) el("sysUptime").innerText = fmtUptime(data.ruijie.uptime);

      const tb = el("ffPerApEspTable");
      if (tb) {
        const rows = data.per_ap_esp || [];
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
        const slices = rj.storageSlices || [];
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
        const recent = data.recent_sessions || [];
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
        const users = data.connected_users || [];
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
                const espNames = (a.esp || []).map((e) => e.name).join(", ") || "—";
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
  let _ffPlanCache = [];
  window.ffLoadPlans = function () {
    api("list_plans").then((data) => {
      const tb = document.getElementById("ffPlansTable");
      if (!tb) return;
      const rows = data.data || [];
      _ffPlanCache = rows;
      tb.innerHTML = rows.length
        ? rows
            .map(
              (p) => `<tr>
          <td>${esc(p.name)}</td><td>${peso(p.price)}</td>
          <td>${p.duration_min} min</td><td>${p.data_mb || 0} MB</td>
          <td>${esc(p.profile_name || "—")}</td><td>${p.pause_limit || 0}</td>
          <td class="ff-table-actions">
            <div class="ff-action-btns">
              <button type="button" class="btn btn-sm btn-outline-secondary" onclick='ffOpenPlanModal(${JSON.stringify(p).replace(/'/g, "&#39;")})'>Edit</button>
              <button type="button" class="btn btn-sm btn-outline-danger" onclick="ffDeletePlan(${p.id})">Del</button>
              <button type="button" class="btn btn-sm btn-primary" onclick="ffActivatePlanPrompt(${p.id})">Activate</button>
            </div>
          </td></tr>`
            )
            .join("")
        : '<tr><td colspan="7" class="text-muted text-center">No plans yet</td></tr>';
    });
  };

  function ffFillProfileSelect(sel, selectedId) {
    if (!sel) return;
    const opts = ['<option value="0">None</option>'].concat(
      _ffProfileCache.map((p) => `<option value="${p.id}">${esc(p.name)}</option>`)
    );
    sel.innerHTML = opts.join("");
    sel.value = String(selectedId ?? 0);
  }

  window.ffOpenPlanModal = function (existing) {
    const fill = function () {
      document.getElementById("ffPlanModalTitle").textContent = existing?.id ? "Edit Plan" : "Add Plan";
      document.getElementById("ffPlanId").value = existing?.id || "";
      document.getElementById("ffPlanName").value = existing?.name || "";
      document.getElementById("ffPlanPrice").value = existing?.price ?? 50;
      document.getElementById("ffPlanDuration").value = existing?.duration_min ?? 1440;
      document.getElementById("ffPlanData").value = existing?.data_mb ?? 0;
      document.getElementById("ffPlanPause").value = existing?.pause_limit ?? 0;
      ffFillProfileSelect(document.getElementById("ffPlanProfile"), existing?.profile_id ?? 0);
      ffShowOverlay("ffPlanModal");
      setTimeout(() => document.getElementById("ffPlanName")?.focus(), 50);
    };
    api("list_profiles")
      .then((data) => {
        _ffProfileCache = data.data || [];
        fill();
      })
      .catch(fill);
  };
  window.ffClosePlanModal = function () {
    ffHideOverlay("ffPlanModal");
  };
  window.ffSavePlan = function () {
    const name = document.getElementById("ffPlanName").value.trim();
    if (!name) {
      toast("Plan name is required", "warning");
      return;
    }
    const body = {
      id: document.getElementById("ffPlanId").value || undefined,
      name,
      price: Number(document.getElementById("ffPlanPrice").value || 0),
      duration_min: Number(document.getElementById("ffPlanDuration").value || 0),
      data_mb: Number(document.getElementById("ffPlanData").value || 0),
      profile_id: Number(document.getElementById("ffPlanProfile").value || 0),
      pause_limit: Number(document.getElementById("ffPlanPause").value || 0),
      enabled: 1,
    };
    api("save_plan", { method: "POST", body }).then((d) => {
      toast(d.status === "ok" ? "Plan saved" : d.message || "Failed", d.status === "ok" ? "success" : "error");
      if (d.status === "ok") {
        ffClosePlanModal();
        ffLoadPlans();
      }
    });
  };

  window.ffDeletePlan = function (id) {
    ffConfirm("Delete this plan? This cannot be undone.", {
      title: "Delete Plan",
      okText: "Delete",
      onConfirm: function () {
        api("delete_plan", { method: "POST", body: { id } }).then(() => ffLoadPlans());
      },
    });
  };

  window.ffActivatePlanPrompt = function (plan_id) {
    ffPromptFields({
      title: "Activate Plan",
      label1: "Client MAC address",
      placeholder1: "AA:BB:CC:DD:EE:FF",
      emptyMsg: "Enter a MAC address",
      onOk: function (mac) {
        api("activate_plan", { method: "POST", body: { plan_id, mac } }).then((d) => {
          toast(d.status === "ok" ? "Plan activated" : d.message || "Failed", d.status === "ok" ? "success" : "error");
        });
      },
    });
  };

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
      const rows = data.data || [];
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

  // ---- Plan clients (table) ----
  window.ffLoadPlanClients = function () {
    api("list_plan_clients").then((data) => {
      const tb = document.getElementById("ffPlanClientsTable");
      if (!tb) return;
      const rows = data.data || [];
      if (!rows.length) {
        tb.innerHTML = '<tr><td colspan="6" class="text-muted text-center">No clients yet</td></tr>';
        return;
      }
      tb.innerHTML = rows
        .map((c) => {
          const nDev = (c.devices || []).length;
          const devHint = (c.devices || []).map((d) => d.mac).slice(0, 2).join(", ") || "—";
          return `<tr>
            <td>${esc(c.name)}</td>
            <td>${esc(c.contact || "—")}</td>
            <td>${esc(c.plan_name || "No plan")}</td>
            <td>${esc(c.status || "active")}</td>
            <td class="small">${nDev} <span class="text-muted">(${esc(devHint)})</span></td>
            <td class="ff-table-actions">
              <div class="ff-action-btns">
                <button type="button" class="btn btn-sm btn-outline-secondary" onclick="ffAttachDevice(${c.id})">Add MAC</button>
                <button type="button" class="btn btn-sm btn-outline-primary" onclick='ffOpenClientModal(${JSON.stringify(c).replace(/'/g, "&#39;")})'>Edit</button>
                <button type="button" class="btn btn-sm btn-outline-danger" onclick="ffDeleteClient(${c.id})">Del</button>
              </div>
            </td>
          </tr>`;
        })
        .join("");
    });
  };

  window.ffOpenClientModal = function (existing) {
    const fill = function () {
      document.getElementById("ffClientModalTitle").textContent = existing?.id ? "Edit Client" : "Add Client";
      document.getElementById("ffClientId").value = existing?.id || "";
      document.getElementById("ffClientName").value = existing?.name || "";
      document.getElementById("ffClientContact").value = existing?.contact || "";
      document.getElementById("ffClientNotes").value = existing?.notes || "";
      const sel = document.getElementById("ffClientPlan");
      sel.innerHTML =
        '<option value="0">No plan</option>' +
        _ffPlanCache.map((p) => `<option value="${p.id}">${esc(p.name)}</option>`).join("");
      sel.value = String(existing?.plan_id ?? 0);
      ffShowOverlay("ffClientModal");
      setTimeout(() => document.getElementById("ffClientName")?.focus(), 50);
    };
    api("list_plans")
      .then((data) => {
        _ffPlanCache = data.data || [];
        fill();
      })
      .catch(fill);
  };
  window.ffCloseClientModal = function () {
    ffHideOverlay("ffClientModal");
  };
  window.ffSaveClient = function () {
    const name = document.getElementById("ffClientName").value.trim();
    if (!name) {
      toast("Client name is required", "warning");
      return;
    }
    api("save_plan_client", {
      method: "POST",
      body: {
        id: document.getElementById("ffClientId").value || undefined,
        name,
        contact: document.getElementById("ffClientContact").value.trim(),
        plan_id: Number(document.getElementById("ffClientPlan").value || 0),
        notes: document.getElementById("ffClientNotes").value.trim(),
        status: "active",
      },
    }).then((d) => {
      if (d.status === "ok") {
        toast("Client saved", "success");
        ffCloseClientModal();
        ffLoadPlanClients();
      } else toast(d.message || "Failed", "error");
    });
  };

  window.ffDeleteClient = function (id) {
    ffConfirm("Delete this plan client?", {
      title: "Delete Client",
      okText: "Delete",
      onConfirm: function () {
        api("delete_plan_client", { method: "POST", body: { id } }).then(() => ffLoadPlanClients());
      },
    });
  };

  window.ffAttachDevice = function (client_id) {
    ffPromptFields({
      title: "Attach Device",
      label1: "MAC address",
      placeholder1: "AA:BB:CC:DD:EE:FF",
      label2: "Hostname (optional)",
      placeholder2: "Galaxy",
      emptyMsg: "Enter a MAC address",
      onOk: function (mac, hostname) {
        api("attach_plan_device", { method: "POST", body: { client_id, mac, hostname } }).then((d) => {
          toast(d.status === "ok" ? "Attached" : d.message, d.status === "ok" ? "success" : "error");
          ffLoadPlanClients();
        });
      },
    });
  };

  window.ffDetachDevice = function (id) {
    api("detach_plan_device", { method: "POST", body: { id } }).then(() => ffLoadPlanClients());
  };

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
      const plans = (data.plans || [])
        .map((p) => `<li>${esc(p.name)} — ${peso(p.price)} / ${p.duration_min} min</li>`)
        .join("");
      const profiles = (data.profiles || [])
        .map((p) => `<li>${esc(p.name)} — ${p.down_kbps}/${p.up_kbps} Kbps · ${ffBandLabel(p.band)}</li>`)
        .join("");
      host.innerHTML = `
        <div class="col-md-4"><div class="card border-0 shadow-sm"><div class="card-body"><h5>Coin Rates</h5><ul>${rates || "<li class='text-muted'>None</li>"}</ul></div></div></div>
        <div class="col-md-4"><div class="card border-0 shadow-sm"><div class="card-body"><h5>Plans</h5><ul>${plans || "<li class='text-muted'>None</li>"}</ul></div></div></div>
        <div class="col-md-4"><div class="card border-0 shadow-sm"><div class="card-body"><h5>Bandwidth</h5><ul>${profiles || "<li class='text-muted'>None</li>"}</ul></div></div></div>`;
    });
  };

  // ---- Operators ----
  const FF_ROLE_PERM_META = [
    { key: "view_dashboard", label: "View dashboard / sales" },
    { key: "manage_sessions", label: "Manage sessions / devices" },
    { key: "edit_rates", label: "Edit rates / plans / vouchers" },
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
      .then((r) => r.json())
      .then((d) => {
        if (d.status === "ok") {
          toast("Firmware staged (" + (d.size_mb || "?") + " MB)", "success");
          if (status) status.textContent = "Staged: " + file.name + " (" + (d.size_mb || "?") + " MB). Ready to flash.";
          if (flashBtn) flashBtn.disabled = false;
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
          api("flash_firmware", { method: "POST", body: { confirm_stock: "1" } }).then((d) => {
            toast(d.message || (d.status === "ok" ? "Flashing…" : "Failed"), d.status === "ok" ? "success" : "error");
            const status = document.getElementById("ffFwStatus");
            if (status) status.textContent = d.message || "";
          });
        },
      }
    );
  };

  let ffOemConfirmToken = "";

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
      <div class="mb-1"><strong>OEM Firmware Detected</strong></div>
      <div>Type: ${report.package_type || "—"}</div>
      <div>Product ID: ${report.product_id || "—"}</div>
      <div>Hardware: ${report.hardware || "RG-EW1200G-PRO"}</div>
      <div>Version: ${report.version || "—"}</div>
      <div>Image size: ${report.image_size || "—"} bytes</div>
      <div>Firmware partition: ${report.firmware_mtd_size || "—"} bytes</div>
      <div>SHA256: <code style="font-size:10px">${report.sha256 || "—"}</code></div>
      <div>Flash target: <code>${report.flash_target || "firmware"}</code></div>
      <div>Ready: ${report.ready ? "YES" : "NO"}</div>
      <div class="mt-2">${rows}</div>`;
  }

  window.ffUploadOemFirmware = function () {
    const input = document.getElementById("ffOemFirmwareFile");
    const file = input && input.files && input.files[0];
    const status = document.getElementById("ffOemStatus");
    const flashBtn = document.getElementById("ffOemFlashBtn");
    const cancelBtn = document.getElementById("ffOemCancelBtn");
    ffOemConfirmToken = "";
    if (flashBtn) flashBtn.disabled = true;
    if (!file) {
      toast("Choose an official OEM package first", "warning");
      return;
    }
    if (status) status.textContent = "Uploading & validating " + file.name + "…";
    fetch("/cgi-bin/api?action=upload_oem_firmware", {
      method: "POST",
      credentials: "include",
      body: file,
    })
      .then((r) => r.json())
      .then((d) => {
        if (d.status === "ok" && d.report) {
          ffOemConfirmToken = d.report.confirm_token || "";
          ffRenderOemReport(d.report);
          toast("OEM firmware validated", "success");
          if (status) status.textContent = "Validated. Review the report, then confirm to install.";
          if (flashBtn) flashBtn.disabled = false;
          if (cancelBtn) cancelBtn.disabled = false;
        } else {
          ffRenderOemReport(d.report || null);
          toast(d.message || "OEM validation failed", "error");
          if (status) status.textContent = d.message || "OEM validation failed";
        }
      })
      .catch((e) => {
        toast("OEM upload failed: " + e, "error");
        if (status) status.textContent = "OEM upload failed";
      });
  };

  window.ffCancelOemFirmware = function () {
    api("cancel_oem_firmware", { method: "POST", body: {} }).then((d) => {
      ffOemConfirmToken = "";
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
          api("flash_oem_firmware", {
            method: "POST",
            body: { confirm_oem: "1", confirm_token: ffOemConfirmToken },
          }).then((d) => {
            toast(d.message || (d.status === "ok" ? "OEM flash started…" : "Failed"), d.status === "ok" ? "success" : "error");
            const status = document.getElementById("ffOemStatus");
            if (status) status.textContent = d.message || "";
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
      plans: showPlans,
      bandwidth: showBandwidth,
      "plan-clients": showPlanClients,
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

  window.detectESP32 = function () {
    const mac = (document.getElementById("detectEspMac")?.value || "").trim();
    const license_id = (document.getElementById("detectLicenseId")?.value || "").trim();
    const name = (document.getElementById("detectEspName")?.value || "").trim();
    const out = document.getElementById("detectEspResult");
    if (!mac || !license_id) {
      if (out) out.textContent = "Enter ESP MAC and License ID (KSK-…).";
      if (typeof showToast === "function") showToast("MAC + License ID required", "warning");
      return;
    }
    if (out) out.textContent = "Detecting…";
    const q =
      "/cgi-bin/api?action=esp_detect&mac=" +
      encodeURIComponent(mac) +
      "&license_id=" +
      encodeURIComponent(license_id) +
      (name ? "&name=" + encodeURIComponent(name) : "");
    fetch(q, { credentials: "include" })
      .then((r) => r.json())
      .then((d) => {
        if (out) out.textContent = d.message || d.status || JSON.stringify(d);
        if (typeof showToast === "function") {
          showToast(d.message || (d.status === "ok" ? "Detected" : "Failed"), d.status === "ok" ? "success" : "error");
        }
        if (d.status === "ok") {
          loadESPDevices();
          loadLicensePool();
        }
      })
      .catch((e) => {
        if (out) out.textContent = String(e);
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
            '<tr><td colspan="6" class="text-center py-3 text-muted">No ESP32 licenses yet — Detect an ESP or Register a KSK ID</td></tr>';
          return;
        }
        tb.innerHTML = rows
          .map((lic) => {
            const lid = lic.license_id || lic.license_key || "—";
            const grace = (lic.grace_used || 0) + " / " + (lic.grace_max || 3);
            const live = lic.live_mac || lic.slot_mac || "—";
            const st = lic.status || "—";
            const badge =
              st === "used"
                ? '<span class="badge bg-success">Active</span>'
                : '<span class="badge bg-secondary">' + ffEscHtml(st) + "</span>";
            return (
              '<tr><td class="font-monospace small">' +
              ffEscHtml(lid) +
              "</td><td>" +
              badge +
              '</td><td class="font-monospace small">' +
              ffEscHtml(live) +
              "</td><td>" +
              ffEscHtml(grace) +
              '</td><td class="small text-muted">' +
              ffEscHtml(lic.used_at || "—") +
              "</td><td>" +
              (st === "available"
                ? '<button type="button" class="btn btn-sm btn-outline-danger" onclick="removeLicenseFromPool(' +
                  lic.id +
                  ')">Remove</button>'
                : "—") +
              "</td></tr>"
            );
          })
          .join("");
      })
      .catch(() => {
        tb.innerHTML = '<tr><td colspan="6" class="text-danger text-center">Failed to load licenses</td></tr>';
      });
  };

  window.addLicenseToPool = function () {
    const key = (document.getElementById("newLicenseKey")?.value || "").trim();
    if (!key) {
      if (typeof showToast === "function") showToast("Enter a KSK license ID", "warning");
      return;
    }
    fetch("/cgi-bin/api?action=esp_license_add&key=" + encodeURIComponent(key), { credentials: "include" })
      .then((r) => r.json())
      .then((d) => {
        if (typeof showToast === "function") showToast(d.message || d.status, d.status === "ok" ? "success" : "error");
        if (d.status === "ok") {
          const inp = document.getElementById("newLicenseKey");
          if (inp) inp.value = "";
          loadLicensePool();
        }
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
            let actionBtn = "";
            const licId = esp.license_id || esp.license_key || "";
            if (esp.license_status === "licensed" || esp.license_status === "free") {
              licenseBadge =
                '<span class="badge bg-success">LICENSED</span>' +
                (licId ? '<div class="font-monospace small text-muted mt-1">' + ffEscHtml(licId) + "</div>" : "");
              actionBtn =
                esp.status === "online"
                  ? '<span class="badge bg-success">Coin ready</span>'
                  : '<span class="badge bg-warning text-dark">Offline</span>';
            } else if (esp.license_status === "inactive_replaced") {
              licenseBadge = '<span class="badge bg-secondary">REPLACED</span>';
              actionBtn = "—";
            } else {
              licenseBadge = '<span class="badge bg-danger">UNLICENSED</span>';
              actionBtn =
                '<button type="button" class="btn btn-primary btn-sm" onclick="document.getElementById(\'detectEspMac\').value=\'' +
                ffEscHtml(esp.slot_mac) +
                "';document.getElementById('detectLicenseId').focus()\">Detect…</button>";
            }
            const adminActions =
              '<button type="button" class="btn btn-outline-primary btn-sm" onclick="renameESPSlot(' +
              esp.id +
              ", '" +
              ffEscHtml(esp.slot_name || "ESP") +
              "')\">Rename</button> " +
              '<button type="button" class="btn btn-outline-danger btn-sm" onclick="deleteESPDevice(' +
              esp.id +
              ')">Del</button>';
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
              actionBtn +
              " " +
              adminActions +
              "</div></td></tr>";
          });
        }
        if (totalEl) totalEl.textContent = String(totalCount);
        if (tb) {
          tb.innerHTML =
            html ||
            '<tr><td colspan="7" class="text-center text-muted py-3">No ESP32 devices yet — Detect ESP32 to bind</td></tr>';
        }
      })
      .catch(() => {
        const tb = document.getElementById("espTableBody");
        if (tb) tb.innerHTML = '<tr><td colspan="7" class="text-danger text-center">Failed to load ESP devices</td></tr>';
      });
  };

  window.freeESPLicense = function () {
    if (typeof showToast === "function") {
      showToast("Use replacement flasher + Detect ESP32 (grace ≤ 3). Free License removed.", "info");
    }
  };

  window.bindESPLicense = function () {
    if (typeof showToast === "function") showToast("Enter License ID and click Detect ESP32", "info");
    document.getElementById("detectLicenseId")?.focus();
  };

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

  const _ffShowSales = typeof window.showSales === "function" ? window.showSales : null;
  window.showSales = function () {
    if (_ffShowSales) _ffShowSales.apply(this, arguments);
    else if (typeof window.showSection === "function") window.showSection("salesSection");
    setTimeout(() => {
      ffInitSalesDatePickers();
      if (typeof hydrateIcons === "function") hydrateIcons();
      if (typeof loadSalesChart === "function") loadSalesChart();
    }, 50);
  };

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
  });
})();
