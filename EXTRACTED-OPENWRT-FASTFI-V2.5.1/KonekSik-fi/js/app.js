/**
 * KonekSik-fi Admin Console — shell, routing, mock interactions
 */
window.KskApp = (function () {
  const AUTH_KEY = "ksk_auth";
  let booted = false;

  const NAV = [
    { group: "Overview", items: [
      { id: "dashboard", label: "Dashboard", icon: "grid" },
      { id: "sales", label: "Sales", icon: "peso" },
    ]},
    { group: "Management", items: [
      { id: "coin-rates", label: "Coin Rates", icon: "coin" },
      { id: "plans", label: "Plans", icon: "plan" },
      { id: "sessions", label: "Sessions", icon: "clock" },
      { id: "vouchers", label: "Vouchers", icon: "ticket" },
    ]},
    { group: "Networking", items: [
      { id: "network", label: "Network Overview", icon: "net" },
      { id: "access-points", label: "Access Points", icon: "ap" },
      { id: "devices", label: "Connected Devices", icon: "device" },
      { id: "bandwidth", label: "Bandwidth", icon: "wave" },
      { id: "security", label: "Security", icon: "shield" },
    ]},
    { group: "System", items: [
      { id: "settings", label: "Settings", icon: "gear" },
      { id: "remote-access", label: "Remote Access", icon: "remote" },
      { id: "sub-vendo", label: "Sub Vendo", icon: "nodes" },
      { id: "ota", label: "OTA Update", icon: "arrow" },
    ]},
  ];

  const ICONS = {
    grid: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>`,
    peso: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M7 7h7a4 4 0 0 1 0 8H7V4"/><path d="M5 10h12M5 13h12"/></svg>`,
    coin: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="8"/><path d="M12 7v10M9 9.5c.8-.8 4.2-.8 5 1.2s-1.8 2.8-5 1.3"/></svg>`,
    plan: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M8 6h13M8 12h13M8 18h13"/><path d="M3 6h.01M3 12h.01M3 18h.01"/></svg>`,
    clock: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="8"/><path d="M12 8v5l3 2"/></svg>`,
    ticket: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 8h16v3a2 2 0 1 0 0 4v3H4v-3a2 2 0 1 0 0-4V8z"/><path d="M12 8v10"/></svg>`,
    net: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 19c7-3 9-8 14-14"/><path d="M5 12c4-1 7-4 10-8"/><circle cx="6" cy="18" r="2"/></svg>`,
    ap: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 12a7 7 0 0 1 14 0"/><path d="M8.5 12a3.5 3.5 0 0 1 7 0"/><circle cx="12" cy="16" r="1.4"/><path d="M12 17v3"/></svg>`,
    device: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="7" y="3" width="10" height="18" rx="2"/><path d="M11 18h2"/></svg>`,
    wave: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 16c3-8 5 8 8 0s5 8 8 0 2-8 2-8"/></svg>`,
    shield: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3z"/></svg>`,
    gear: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="3"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6L17 7M7 17l-1.4 1.4"/></svg>`,
    remote: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 12a7 7 0 0 1 14 0"/><path d="M8 12a4 4 0 0 1 8 0"/><circle cx="12" cy="12" r="1.5"/></svg>`,
    nodes: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="M8.2 11l7-4M8.2 13l7 4"/></svg>`,
    arrow: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M12 4v12"/><path d="M7 11l5 5 5-5"/><path d="M5 20h14"/></svg>`,
    reboot: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 12a8 8 0 1 0 2.3-5.7"/><path d="M4 4v6h6"/></svg>`,
    logout: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M10 7V5a2 2 0 0 1 2-2h7v18h-7a2 2 0 0 1-2-2v-2"/><path d="M4 12h11M12 9l3 3-3 3"/></svg>`,
  };

  const state = {
    route: "dashboard",
    sessionTab: "active",
    salesFilter: "today",
    salesPage: 1,
    deviceFilter: "all",
    apFilter: "all",
    apQuery: "",
    apView: "list",
    apId: null,
    apLoading: false,
    planId: null,
  };

  function $(sel) { return document.querySelector(sel); }

  function selectedVoucherCodes() {
    return [...document.querySelectorAll(".v-check:checked")].map((el) => el.dataset.id).filter(Boolean);
  }

  function syncVoucherBulk() {
    const boxes = document.querySelectorAll(".v-check");
    const n = selectedVoucherCodes().length;
    const btn = document.getElementById("v-bulk-del");
    const lab = document.getElementById("v-bulk-n");
    const all = document.querySelector("[data-action='vouchers-select-all']");
    if (btn) btn.disabled = n === 0;
    if (lab) lab.textContent = n ? n + " selected" : "";
    if (all && boxes.length) {
      all.checked = n === boxes.length;
      all.indeterminate = n > 0 && n < boxes.length;
    }
  }

  function renderSidebar() {
    const groups = NAV.map((g) => `
      <div class="nav-label">${g.group}</div>
      ${g.items.map((i) => `
        <a class="nav-item ${state.route === i.id ? "active" : ""}" href="#${i.id}" data-action="goto" data-route="${i.id}">
          ${ICONS[i.icon] || ""}<span>${i.label}</span>
        </a>
      `).join("")}
    `).join("");
    $("#sidebar-nav").innerHTML = groups;
  }

  function unreadCount() {
    return AppData.notifications.filter((n) => n.unread).length;
  }

  function renderHeader() {
    let [title, crumb] = Pages.meta[state.route] || ["KonekSik-fi", ""];
    if (state.route === "access-points" && state.apId) {
      title = state.apId;
      crumb = "Access Point hardware, radios, and wireless clients";
    }
    if (state.route === "plans" && state.planId) {
      const p = AppData.plans.find((x) => x.id === state.planId);
      title = p ? p.name : "Plan";
      crumb = "Households on this plan, AP deployment, and connected devices";
    }
    $("#page-title").textContent = title;
    $("#page-crumb").textContent = crumb;
    const n = unreadCount();
    const badge = $("#notif-count");
    badge.textContent = n;
    badge.hidden = n === 0;
    document.querySelectorAll(".nav-item[data-route]").forEach((el) => {
      el.classList.toggle("active", el.dataset.route === state.route);
    });
  }

  function renderPage(opts) {
    const quiet = opts && opts.quiet;
    const host = $("#page-content");
    if (!quiet) host.classList.remove("page-enter");
    document.body.classList.toggle("route-sales", state.route === "sales");
    let html = "";
    if (state.route === "sales") html = Pages.sales(state.salesFilter, state.salesPage);
    else if (state.route === "sessions") html = Pages.sessions(state.sessionTab);
    else if (state.route === "devices") html = Pages.devices(state.deviceFilter);
    else if (state.route === "plans") html = Pages.plans(state.planId);
    else if (state.route === "access-points") {
      html = Pages["access-points"]({
        apId: state.apId,
        filter: state.apFilter,
        query: state.apQuery,
        view: state.apView,
        loading: state.apLoading,
      });
    }
    else html = (Pages[state.route] || Pages.dashboard)();
    host.innerHTML = html;
    if (!quiet) {
      void host.offsetWidth;
      host.classList.add("page-enter");
    }
    UI.initCharts(host);
    UI.enhanceSelects(host);
    renderHeader();
    applyDisplayPrefs();
  }

  function applyDisplayPrefs() {
    document.documentElement.setAttribute("data-theme", AppData.settings.theme);
    document.body.classList.toggle("compact", !!AppData.settings.compactMode);
  }

  function goto(route) {
    closeMenus();
    state.apId = null;
    if (route !== "plans") state.planId = null;
    if (route === "plans") state.planId = null;
    if (route !== "sales") state.salesPage = 1;
    state.route = route || "dashboard";
    if (currentRoute() !== state.route) {
      location.hash = state.route;
    }
    renderSidebar();
    renderPage();
    setTimeout(closeSidebar, 60);
  }

  function closeMenus() {
    document.querySelectorAll(".dropdown").forEach((d) => d.classList.remove("show"));
    if (window.UI && UI.closeSelectMenus) UI.closeSelectMenus();
  }

  function closeSidebar() {
    $("#sidebar").classList.remove("open");
    $("#sidebar-overlay").classList.remove("show");
  }

  function findDevice(id) {
    return AppData.devices.find((d) => d.id === id);
  }

  function findSession(id) {
    return AppData.sessions.find((s) => s.id === id);
  }

  function deviceDrawer(d) {
    UI.modal({
      title: "Device Details",
      width: "560px",
      body: `
        <h2 style="margin-bottom:10px">Device Information</h2>
        ${UI.dl([
          ["Hostname", d.hostname],
          ["Device type", d.type],
          ["IP", `<span class="mono">${d.ip}</span>`],
          ["MAC", `<span class="mono">${d.mac}</span>`],
          ["Connection", d.connection],
          ["First seen", d.firstSeen],
          ["Last seen", d.lastSeen],
        ])}
        <h2 class="mt-14" style="margin-bottom:10px">Session</h2>
        ${UI.dl([
          ["Plan", d.plan],
          ["Start", d.start],
          ["Expiration", d.expires],
          ["Remaining", d.remaining],
        ])}
        <h2 class="mt-14" style="margin-bottom:10px">Traffic</h2>
        ${UI.dl([
          ["Download", d.download],
          ["Upload", d.upload],
          ["Current speed", d.speed],
        ])}
        <h2 class="mt-14" style="margin-bottom:10px">Security</h2>
        ${UI.dl([
          ["Blocked", d.blocked ? UI.badge("blocked") : UI.badge("active", "Allowed")],
          ["Isolation status", d.isolation],
        ])}
      `,
      actions: `
        <button type="button" class="btn btn-ghost" data-action="close-modal">Close</button>
        <button type="button" class="btn btn-ghost" data-action="disconnect-device" data-id="${d.id}">Disconnect</button>
        <button type="button" class="btn btn-danger" data-action="block-device" data-id="${d.id}">Block Device</button>
        <button type="button" class="btn btn-primary" data-action="extend-device" data-id="${d.id}">Extend Session</button>
      `,
    });
  }

  function sessionDrawer(s) {
    UI.closeDrawer();
    UI.closeModal();
    UI.modal({
      title: "Session Details",
      width: "560px",
      body: `
        <div class="detail-hero">
          <div>
            <div class="detail-kicker">${s.id}</div>
            <h4>${s.device}</h4>
            <p class="muted sm">${s.type} · <span class="mono">${s.ip}</span></p>
          </div>
          ${UI.badge(s.status)}
        </div>
        <div class="detail-grid">
          <section class="detail-panel">
            <h5>Device</h5>
            ${UI.dl([
              ["IP Address", `<span class="mono">${s.ip}</span>`],
              ["MAC Address", `<span class="mono">${s.mac}</span>`],
            ])}
          </section>
          <section class="detail-panel">
            <h5>Plan</h5>
            ${UI.dl([
              ["Plan", `${s.plan} / ${s.duration}`],
              ["Remaining", `<strong>${s.remaining}</strong>`],
            ])}
          </section>
          <section class="detail-panel">
            <h5>Time</h5>
            ${UI.dl([
              ["Started", s.start],
              ["Expires", s.expires],
            ])}
          </section>
          <section class="detail-panel">
            <h5>Traffic</h5>
            ${UI.dl([
              ["Download", s.download],
              ["Upload", s.upload],
            ])}
          </section>
        </div>
      `,
      actions: `
        <button type="button" class="btn btn-ghost" data-action="close-modal">Close</button>
        <button type="button" class="btn btn-ghost" data-action="extend-session" data-id="${s.id}">Extend</button>
        <button type="button" class="btn btn-ghost" data-action="disconnect-session" data-id="${s.id}">Disconnect</button>
        <button type="button" class="btn btn-danger" data-action="block-session" data-id="${s.id}">Block</button>
      `,
    });
  }

  function voucherQr(code) {
    const size = 11;
    let cells = "";
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const on = (code.charCodeAt((x + y * 3) % code.length) + x * 7 + y * 13) % 4 !== 0
          || (x < 3 && y < 3) || (x > 7 && y < 3) || (x < 3 && y > 7);
        if (on) cells += `<rect x="${x}" y="${y}" width="1" height="1"/>`;
      }
    }
    return `<svg class="voucher-qr" viewBox="0 0 ${size} ${size}" fill="#0f172a" aria-hidden="true">${cells}</svg>`;
  }

  function speedSelect(selected) {
    const names = AppData.bandwidthProfiles.map((p) => p.name).concat("Custom");
    return names.map((p) => `<option ${selected === p ? "selected" : ""}>${p}</option>`).join("");
  }

  function customSpeedFields(existing) {
    const show = existing && existing.speed === "Custom";
    return `<div class="field mt-10" id="custom-speed-fields" ${show ? "" : "hidden"}>
      <label>Custom speed (Mbps)</label>
      <div class="form-grid">
        <input id="speed-dl" type="number" placeholder="Download" value="${existing && existing.download ? existing.download : 10}">
        <input id="speed-ul" type="number" placeholder="Upload" value="${existing && existing.upload ? existing.upload : 5}">
      </div>
    </div>`;
  }

  function bindSpeedSelect(selId) {
    const sel = document.getElementById(selId);
    if (!sel) return;
    sel.onchange = () => {
      const box = document.getElementById("custom-speed-fields");
      if (box) box.hidden = sel.value !== "Custom";
    };
  }

  function speedPayload(speed) {
    if (speed !== "Custom") return { speed };
    return {
      speed: "Custom",
      download: Number($("#speed-dl")?.value) || 10,
      upload: Number($("#speed-ul")?.value) || 5,
    };
  }

  function rateForm(existing) {
    UI.modal({
      title: existing ? "Edit Coin Rate" : "Add Coin Rate",
      body: `
        <div class="field"><label>Coin value (₱)</label><input id="rate-coin" type="number" value="${existing ? existing.coin : 10}"></div>
        <div class="field mt-10"><label>Time label</label><input id="rate-label" value="${existing ? existing.label : "1 Hour"}"></div>
        <div class="field mt-10"><label>Speed profile</label>
          <select id="rate-speed">${speedSelect(existing ? existing.speed : "Standard")}</select>
        </div>
        ${customSpeedFields(existing)}
      `,
      actions: `<button class="btn btn-ghost" data-action="close-modal">Cancel</button>
                <button class="btn btn-primary" id="save-rate">Save</button>`,
    });
    bindSpeedSelect("rate-speed");
    $("#save-rate").onclick = () => {
      const coin = Number($("#rate-coin").value);
      const label = $("#rate-label").value;
      const extra = speedPayload($("#rate-speed").value);
      if (existing) {
        existing.coin = coin;
        existing.label = label;
        Object.assign(existing, extra);
      } else {
        AppData.coinRates.push({ id: "rate-" + Date.now(), coin, minutes: 60, label, status: "active", ...extra });
      }
      UI.closeModal();
      UI.toast("Coin rate saved", "success");
      renderPage();
    };
  }

  function profileForm(existing) {
    UI.modal({
      title: existing ? "Edit Profile" : "Add Profile",
      body: `
        <div class="field"><label>Name</label><input id="bw-name" value="${existing ? existing.name : ""}"></div>
        <div class="field mt-10"><label>Download (Mbps)</label><input id="bw-dl" type="number" value="${existing ? existing.download : 10}"></div>
        <div class="field mt-10"><label>Upload (Mbps)</label><input id="bw-ul" type="number" value="${existing ? existing.upload : 5}"></div>
      `,
      actions: `<button class="btn btn-ghost" data-action="close-modal">Cancel</button>
                <button class="btn btn-primary" id="save-bw">Save</button>`,
    });
    $("#save-bw").onclick = () => {
      const name = $("#bw-name").value || "Custom";
      const download = Number($("#bw-dl").value);
      const upload = Number($("#bw-ul").value);
      if (existing) {
        existing.name = name;
        existing.download = download;
        existing.upload = upload;
      } else {
        AppData.bandwidthProfiles.push({ id: "bw-" + Date.now(), name, download, upload, status: "active" });
      }
      UI.closeModal();
      UI.toast("Bandwidth profile saved", "success");
      renderPage();
    };
  }

  function planForm(existing) {
    UI.modal({
      title: existing ? "Edit Plan" : "Add Plan",
      body: `
        <div class="field"><label>Plan name</label><input id="plan-name" value="${existing ? existing.name : ""}" placeholder="Plan 50"></div>
        <div class="field mt-10"><label>Rate (₱)</label><input id="plan-price" type="number" value="${existing ? existing.price : 600}"></div>
        <div class="field mt-10"><label>Download (Mbps)</label><input id="plan-dl" type="number" value="${existing ? existing.download : 50}"></div>
        <div class="field mt-10"><label>Upload (Mbps)</label><input id="plan-ul" type="number" value="${existing ? existing.upload : 20}"></div>
        <div class="field mt-10"><label>Duration</label><input id="plan-dur" value="${existing ? existing.duration : "30 days"}"></div>
      `,
      actions: `<button class="btn btn-ghost" data-action="close-modal">Cancel</button>
                <button class="btn btn-primary" id="save-plan">Save</button>`,
    });
    $("#save-plan").onclick = () => {
      const row = {
        name: $("#plan-name").value || "Custom Plan",
        price: Number($("#plan-price").value) || 0,
        download: Number($("#plan-dl").value) || 0,
        upload: Number($("#plan-ul").value) || 0,
        duration: $("#plan-dur").value || "30 days",
        status: existing ? existing.status : "active",
      };
      if (existing) Object.assign(existing, row);
      else AppData.plans.push({ id: "plan-" + Date.now(), ...row });
      UI.closeModal();
      UI.toast("Plan saved", "success");
      renderPage();
    };
  }

  function apOptions(selected) {
    return `<option value="">Select access point</option>` + AppData.accessPoints.map((ap) =>
      `<option value="${ap.id}" ${ap.id === selected ? "selected" : ""}>${ap.identity} · ${ap.model}${ap.status === "offline" ? " (offline)" : ""}</option>`
    ).join("");
  }

  function bindVendoForm(v) {
    UI.modal({
      title: "Bind ESP32 through MikroTik",
      width: "520px",
      body: `
        <p class="muted sm">The ESP32 connects to the AP over Wi-Fi as a station (same as a phone). The AP is a CAP/bridge only. MikroTik CAPsMAN is what records that this ESP32 belongs to that AP.</p>
        <div class="bind-path mt-14">
          <span>ESP32 Wi-Fi</span><em>→</em><span>AP</span><em>→</em><span>MikroTik ${UI.escapeHtml(AppData.mikrotik.model)}</span><em>→</em><span>CAPsMAN</span>
        </div>
        <div class="field mt-14"><label>Sub Vendo</label><input value="${UI.escapeHtml(v.name)}" disabled></div>
        <div class="field mt-10"><label>ESP32 MAC</label><input class="mono" value="${UI.escapeHtml(v.mac || "—")}" disabled></div>
        <div class="field mt-10"><label>Access Point</label>
          <select id="vendo-ap">${apOptions(v.apId || "")}</select>
        </div>
      `,
      actions: `<button type="button" class="btn btn-ghost" data-action="close-modal">Cancel</button>
                ${v.mikrotikBound ? `<button type="button" class="btn btn-ghost" id="do-unbind">Unbind</button>` : ""}
                <button type="button" class="btn btn-primary" id="do-bind">Bind via MikroTik</button>`,
    });
    const unbind = document.getElementById("do-unbind");
    if (unbind) {
      unbind.onclick = () => {
        v.apId = "";
        v.mikrotikBound = false;
        v.bindStatus = "unbound";
        UI.closeModal();
        UI.toast(v.name + " unbound from MikroTik / AP", "warning");
        renderPage();
      };
    }
    $("#do-bind").onclick = () => {
      const apId = $("#vendo-ap").value;
      const ap = AppData.accessPoints.find((a) => a.id === apId);
      if (!ap) {
        UI.toast("Select an access point", "warning");
        return;
      }
      simulateVendoBind(v, ap);
    };
  }

  function simulateVendoBind(v, ap) {
    UI.modal({
      title: "Binding through MikroTik…",
      body: `<p class="muted sm">${UI.escapeHtml(v.name)} → ${UI.escapeHtml(AppData.mikrotik.model)} → ${UI.escapeHtml(ap.identity)}</p>
        <div class="steps mt-14" id="vendo-bind-steps">
          <div class="step run" data-step="0"><span class="mark"></span> Connecting to MikroTik hEX</div>
          <div class="step" data-step="1"><span class="mark"></span> Confirming ESP32 Wi-Fi association on the AP</div>
          <div class="step" data-step="2"><span class="mark"></span> Registering the station in CAPsMAN</div>
          <div class="step" data-step="3"><span class="mark"></span> Binding ESP32 to this CAP</div>
        </div>
        <p class="muted sm mt-14">Owner console does not show RouterOS commands. The technician path stays on the MikroTik.</p>`,
      actions: `<button type="button" class="btn btn-ghost" data-action="close-modal">Hide</button>`,
    });
    let i = 0;
    const timer = setInterval(() => {
      const steps = document.querySelectorAll("#vendo-bind-steps .step");
      if (!steps.length) { clearInterval(timer); return; }
      if (i > 0) {
        steps[i - 1].classList.remove("run");
        steps[i - 1].classList.add("done");
      }
      if (i < steps.length) steps[i].classList.add("run");
      i += 1;
      if (i > steps.length) {
        clearInterval(timer);
        v.apId = ap.id;
        v.mikrotikBound = true;
        v.bindStatus = "bound";
        if (v.status === "offline") v.status = "online";
        UI.closeModal();
        UI.toast(v.name + " bound to " + ap.identity + " via MikroTik", "success");
        renderPage();
      }
    }, 700);
  }

  function planClientForm(existing, planId) {
    const plan = AppData.plans.find((p) => p.id === (existing ? existing.planId : planId));
    if (!plan) return;
    const esc = UI.escapeHtml;
    UI.modal({
      title: existing ? "Edit Client" : "Add Client — " + plan.name,
      width: "520px",
      body: `
        <p class="muted sm">${plan.name} · ${plan.download} Mbps · ${UI.peso(plan.price)}</p>
        <div class="form-grid mt-14">
          <div class="field"><label>House name <span class="req">*</span></label>
            <input id="cli-house" value="${existing ? esc(existing.houseName) : ""}" placeholder="Basera Family"></div>
          <div class="field"><label>House number <span class="req">*</span></label>
            <input id="cli-number" value="${existing ? esc(existing.houseNumber) : ""}" placeholder="12"></div>
        </div>
        <div class="form-grid mt-14">
          <div class="field"><label>Contact number <span class="req">*</span></label>
            <input id="cli-contact" type="tel" value="${existing ? esc(existing.contact) : ""}" placeholder="0917 000 0000"></div>
          <div class="field"><label>FB <span class="opt-label">(optional)</span></label>
            <input id="cli-fb" value="${existing ? esc(existing.facebook || "") : ""}" placeholder="facebook.com/name or username"></div>
        </div>
        <div class="field mt-10"><label>Deployed access point <span class="req">*</span></label>
          <select id="cli-ap">${apOptions(existing ? existing.apId : "")}</select>
        </div>
      `,
      actions: `<button type="button" class="btn btn-ghost" data-action="close-modal">Cancel</button>
                <button type="button" class="btn btn-primary" id="save-plan-client">Save</button>`,
    });
    $("#save-plan-client").onclick = () => {
      const houseName = ($("#cli-house").value || "").trim();
      const houseNumber = ($("#cli-number").value || "").trim();
      const contact = ($("#cli-contact").value || "").trim();
      const facebook = ($("#cli-fb").value || "").trim();
      const apId = $("#cli-ap").value;
      if (!houseName || !houseNumber || !contact || !apId) {
        UI.toast("House name, house number, contact, and AP are required", "warning");
        return;
      }
      if (!AppData.planClients) AppData.planClients = [];
      const row = {
        houseName,
        houseNumber,
        contact,
        facebook,
        apId,
        planId: plan.id,
        status: existing ? existing.status : "active",
        availedOn: existing ? existing.availedOn : new Date().toLocaleDateString("en-US", { month: "short", day: "2-digit", year: "numeric" }),
      };
      if (existing) {
        Object.assign(existing, row);
        AppData.devices.forEach((d) => {
          if (d.clientId === existing.id) {
            d.apId = apId;
            d.planId = plan.id;
          }
        });
      } else {
        const created = { id: "cli-" + Date.now(), ...row };
        AppData.planClients.push(created);
        AppData.devices.forEach((d) => {
          if (d.apId === apId && !d.clientId) {
            d.clientId = created.id;
            d.planId = plan.id;
          }
        });
      }
      const ap = AppData.accessPoints.find((a) => a.id === apId);
      if (ap) {
        ap.downloadLimit = plan.download;
        ap.uploadLimit = plan.upload;
        ap.speedProfile = "Custom";
      }
      UI.closeModal();
      UI.toast(existing ? "Client updated" : houseName + " added on " + apId, "success");
      renderPage();
    };
  }

  function simulateApRestart(ap) {
    UI.modal({
      title: "Restarting AP…",
      body: `<div class="steps" id="ap-restart-steps">
        <div class="step run" data-step="0"><span class="mark"></span> Sending restart request</div>
        <div class="step" data-step="1"><span class="mark"></span> Waiting for AP</div>
        <div class="step" data-step="2"><span class="mark"></span> Reconnecting</div>
        <div class="step" data-step="3"><span class="mark"></span> Verifying status</div>
      </div>`,
      actions: `<button class="btn btn-ghost" data-action="close-modal">Hide</button>`,
    });
    const labels = ["Sending restart request", "Waiting for AP", "Reconnecting", "Verifying status"];
    let i = 0;
    const timer = setInterval(() => {
      const steps = document.querySelectorAll("#ap-restart-steps .step");
      if (!steps.length) { clearInterval(timer); return; }
      if (i > 0) steps[i - 1].classList.remove("run"), steps[i - 1].classList.add("done");
      if (i < steps.length) steps[i].classList.add("run");
      i += 1;
      if (i > labels.length) {
        clearInterval(timer);
        ap.status = "online";
        ap.capsmamStatus = "connected";
        UI.closeModal();
        UI.toast(ap.identity + " · ONLINE. Restart completed successfully.", "success");
        renderPage();
      }
    }, 700);
  }

  function runOta() {
    const host = document.getElementById("ota-progress");
    const bar = document.getElementById("ota-bar");
    const stage = document.getElementById("ota-stage");
    if (!host) return;
    host.hidden = false;
    const steps = [
      [15, "Downloading…"],
      [48, "Installing…"],
      [78, "Rebooting…"],
      [100, "Completed"],
    ];
    let i = 0;
    function tick() {
      const [pct, label] = steps[i];
      bar.style.width = pct + "%";
      stage.textContent = label;
      if (label === "Completed") {
        AppData.ota.current = AppData.ota.latest;
        AppData.ota.status = "healthy";
        UI.toast("System updated to " + AppData.ota.latest, "success");
        setTimeout(renderPage, 900);
        return;
      }
      i += 1;
      setTimeout(tick, 900);
    }
    tick();
  }

  document.addEventListener("click", (e) => {
    const t = e.target.closest("[data-action]");
    if (!t) {
      if (!e.target.closest(".rel")) closeMenus();
      return;
    }
    const action = t.dataset.action;
    const id = t.dataset.id;
    const route = t.dataset.route;

    if (action === "goto") {
      e.preventDefault();
      goto(route);
      return;
    }
    if (action === "toggle-sidebar") {
      $("#sidebar").classList.toggle("open");
      $("#sidebar-overlay").classList.toggle("show");
    }
    if (action === "close-sidebar") closeSidebar();
    if (action === "close-modal") UI.closeModal();
    if (action === "close-drawer") UI.closeDrawer();

    if (action === "toggle-notifs") {
      e.stopPropagation();
      const dd = $("#notif-dd");
      const open = !dd.classList.contains("show");
      closeMenus();
      if (open) {
        dd.innerHTML = AppData.notifications.map((n) => `
          <button class="dropdown-item" data-action="read-notif" data-id="${n.id}">
            <strong>${n.title}</strong>
            <small>${n.body} · ${n.time}</small>
          </button>
        `).join("");
        dd.classList.add("show");
      }
    }

    if (action === "read-notif") {
      const n = AppData.notifications.find((x) => x.id === id);
      if (n) n.unread = false;
      renderHeader();
      closeMenus();
    }

    if (action === "toggle-profile") {
      e.stopPropagation();
      const dd = $("#profile-dd");
      const open = !dd.classList.contains("show");
      closeMenus();
      if (open) {
        dd.innerHTML = `
          <button class="dropdown-item" data-action="goto" data-route="settings">Account settings</button>
          <button class="dropdown-item" data-action="logout">Logout</button>
        `;
        dd.classList.add("show");
      }
    }

    if (action === "filter-sales") {
      state.salesFilter = t.dataset.filter;
      state.salesPage = 1;
      renderPage();
    }
    if (action === "sales-page") {
      state.salesPage = Number(t.dataset.page) || 1;
      renderPage();
    }
    if (action === "reset-sales") {
      UI.confirmDialog({
        title: "Reset sales data?",
        message: "This clears recorded transactions for the selected period in this console. Totals will be recalculated. This cannot be undone.",
        confirmText: "Reset",
        danger: true,
        onConfirm: () => {
          const f = state.salesFilter;
          const keep = {
            today: (x) => x.day !== "today",
            yesterday: (x) => x.day !== "yesterday",
            week: (x) => x.day === "month",
            month: () => false,
          }[f] || ((x) => x.day !== "today");
          AppData.sales = AppData.sales.filter(keep);
          if (f === "today" || f === "month") {
            AppData.kpis.todaysSales = 0;
            (AppData.subVendos || []).forEach((v) => { v.sales = 0; });
          }
          if (f === "week" || f === "month") AppData.kpis.weekSales = 0;
          if (f === "month") {
            AppData.kpis.monthSales = 0;
            AppData.kpis.totalTransactions = AppData.sales.length;
          } else {
            AppData.kpis.totalTransactions = AppData.sales.length;
          }
          state.salesPage = 1;
          UI.toast("Sales data reset for this period", "warning");
          renderPage();
        },
      });
    }
    if (action === "tab-sessions") {
      state.sessionTab = t.dataset.tab;
      renderPage();
    }

    if (action === "view-device") {
      const d = findDevice(id);
      if (d) deviceDrawer(d);
    }
    if (action === "view-session") {
      UI.closeDrawer();
      UI.closeModal();
      const s = findSession(id);
      if (s) sessionDrawer(s);
    }
    if (action === "disconnect-device" || action === "disconnect-session") {
      UI.closeDrawer();
      UI.closeModal();
      UI.confirmDialog({
        title: "Disconnect client?",
        message: "The device will lose internet access until it purchases a new session.",
        confirmText: "Disconnect",
        danger: true,
        onConfirm: () => UI.toast("Client disconnected (simulated)", "warning"),
      });
    }
    if (action === "block-device" || action === "block-session") {
      UI.closeDrawer();
      UI.closeModal();
      UI.confirmDialog({
        title: "Block device?",
        message: "This device will be denied access on the customer network until unblocked.",
        confirmText: "Block",
        danger: true,
        onConfirm: () => UI.toast("Device blocked (simulated)", "danger"),
      });
    }
    if (action === "extend-session" || action === "extend-device") {
      UI.closeDrawer();
      UI.closeModal();
      UI.modal({
        title: "Extend Session",
        body: `<div class="field"><label>Add time</label>
          <select id="ext-time"><option>15 minutes</option><option selected>30 minutes</option><option>1 Hour</option></select>
        </div>`,
        actions: `<button class="btn btn-ghost" data-action="close-modal">Cancel</button>
                  <button class="btn btn-primary" id="do-ext">Extend</button>`,
      });
      $("#do-ext").onclick = () => {
        UI.closeModal();
        UI.toast("Session extended (simulated)", "success");
      };
    }

    if (action === "add-coin-rate") rateForm(null);
    if (action === "edit-coin-rate") rateForm(AppData.coinRates.find((r) => r.id === id));
    if (action === "toggle-coin-rate") {
      const r = AppData.coinRates.find((x) => x.id === id);
      r.status = r.status === "active" ? "disabled" : "active";
      UI.toast(r.status === "active" ? "Rate enabled" : "Rate disabled", "info");
      renderPage();
    }
    if (action === "delete-coin-rate") {
      const r = AppData.coinRates.find((x) => x.id === id);
      UI.confirmDialog({
        title: "Delete coin rate?",
        message: r ? `${UI.peso(r.coin)} · ${r.label} will be removed.` : "This rate will be removed.",
        confirmText: "Delete",
        danger: true,
        onConfirm: () => {
          AppData.coinRates = AppData.coinRates.filter((x) => x.id !== id);
          UI.toast("Coin rate removed", "warning");
          renderPage();
        },
      });
    }

    if (action === "generate-vouchers") {
      UI.modal({
        title: "Generate Vouchers",
        body: `
          <div class="field"><label>Number of Vouchers</label><input id="v-count" type="number" value="100"></div>
          <div class="field mt-10"><label>Plan</label>
            <select id="v-plan"><option>5 Minutes</option><option selected>1 Hour</option><option>3 Hours</option><option>12 Hours</option></select>
          </div>
          <div class="field mt-10"><label>Speed profile</label>
            <select id="v-speed">${speedSelect("Standard")}</select>
          </div>
          ${customSpeedFields(null)}
          <div class="field mt-10"><label>Prefix</label><input id="v-prefix" value="KSK"></div>
        `,
        actions: `<button class="btn btn-ghost" data-action="close-modal">Cancel</button>
                  <button class="btn btn-primary" id="do-gen">Generate</button>`,
      });
      bindSpeedSelect("v-speed");
      $("#do-gen").onclick = () => {
        const count = Number($("#v-count").value) || 1;
        const plan = $("#v-plan").value;
        const prefix = $("#v-prefix").value || "KSK";
        const extra = speedPayload($("#v-speed").value);
        for (let i = 0; i < Math.min(count, 8); i++) {
          AppData.vouchers.unshift({
            code: prefix + "-" + Math.random().toString(16).slice(2, 7).toUpperCase(),
            plan,
            duration: plan,
            created: "Aug 24, 2026",
            used: "—",
            status: "available",
            ...extra,
          });
        }
        UI.closeModal();
        UI.toast(`${count} vouchers generated (previewing first batch)`, "success");
        renderPage();
      };
    }
    if (action === "import-vouchers") UI.toast("Import is simulated in this UI phase", "info");
    if (action === "export-vouchers") UI.toast("Export file prepared (simulated)", "success");
    if (action === "vouchers-select-all") {
      document.querySelectorAll(".v-check").forEach((c) => { c.checked = t.checked; });
      syncVoucherBulk();
    }
    if (action === "voucher-check") syncVoucherBulk();
    if (action === "delete-voucher") {
      UI.confirmDialog({
        title: "Delete voucher?",
        message: id + " will be removed and can no longer be redeemed.",
        confirmText: "Delete",
        danger: true,
        onConfirm: () => {
          AppData.vouchers = AppData.vouchers.filter((v) => v.code !== id);
          UI.toast("Voucher deleted", "warning");
          renderPage();
        },
      });
    }
    if (action === "delete-vouchers-selected") {
      const codes = selectedVoucherCodes();
      if (!codes.length) {
        UI.toast("Select at least one voucher", "info");
        return;
      }
      UI.confirmDialog({
        title: "Delete selected vouchers?",
        message: codes.length + " voucher" + (codes.length === 1 ? "" : "s") + " will be removed.",
        confirmText: "Delete",
        danger: true,
        onConfirm: () => {
          const set = new Set(codes);
          AppData.vouchers = AppData.vouchers.filter((v) => !set.has(v.code));
          UI.toast(codes.length + " voucher" + (codes.length === 1 ? "" : "s") + " deleted", "warning");
          renderPage();
        },
      });
    }
    if (action === "view-voucher") {
      const v = AppData.vouchers.find((x) => x.code === id);
      if (!v) return;
      const speed = v.speed === "Custom" ? `Custom (${v.download}/${v.upload} Mbps)` : (v.speed || "—");
      UI.modal({
        title: "Voucher Details",
        width: "520px",
        body: `<div class="voucher-ticket" id="print-root">
          <div class="voucher-ticket-top">
            <div class="voucher-brand">
              <span class="voucher-mark">K</span>
              <div>
                <strong>KonekSik-fi</strong>
                <span>Access Voucher</span>
              </div>
            </div>
            ${UI.badge(v.status)}
          </div>
          <div class="voucher-ticket-mid">
            ${voucherQr(v.code)}
            <div class="voucher-code-block">
              <span class="muted sm">Voucher code</span>
              <div class="code">${v.code}</div>
              <button type="button" class="btn btn-ghost btn-sm" data-action="copy-voucher" data-id="${v.code}">Copy code</button>
            </div>
          </div>
          <div class="voucher-meta">
            <div><span>Plan</span><strong>${v.plan}</strong></div>
            <div><span>Duration</span><strong>${v.duration}</strong></div>
            <div><span>Speed</span><strong>${speed}</strong></div>
            <div><span>Created</span><strong>${v.created}</strong></div>
            <div><span>Used</span><strong>${v.used}</strong></div>
            <div><span>Status</span><strong>${UI.titleCase(v.status)}</strong></div>
          </div>
          <p class="voucher-hint">Enter this code on the captive portal or present it at the Piso WiFi kiosk. One-time use unless disabled by the owner.</p>
        </div>`,
        actions: `<button type="button" class="btn btn-ghost" data-action="close-modal">Close</button>
                  <button type="button" class="btn btn-primary" data-action="print-voucher" data-id="${v.code}">Print</button>`,
      });
    }
    if (action === "copy-voucher") {
      const code = id;
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(code).then(() => UI.toast("Voucher code copied", "success"));
      } else {
        UI.toast(code, "info");
      }
    }
    if (action === "print-voucher") {
      const v = AppData.vouchers.find((x) => x.code === id);
      if (!v) return;
      const speed = v.speed === "Custom" ? `Custom (${v.download}/${v.upload} Mbps)` : (v.speed || "—");
      const w = window.open("", "print-voucher", "width=480,height=640");
      if (!w) {
        UI.toast("Allow pop-ups to print vouchers", "warning");
        return;
      }
      w.document.write(`<!DOCTYPE html><html><head><title>${v.code}</title>
        <style>
          @page { margin: 12mm; }
          body{font-family:Segoe UI,sans-serif;padding:24px;color:#1a2332;background:#fff}
          .ticket{border:1px solid #e4e8ee;border-radius:12px;overflow:hidden;max-width:420px;margin:0 auto}
          .top{display:flex;justify-content:space-between;align-items:center;padding:16px 18px;background:#0f172a;color:#fff}
          .mark{width:32px;height:32px;border-radius:8px;background:#2563eb;display:inline-grid;place-items:center;font-weight:800;margin-right:10px}
          .brand{display:flex;align-items:center}
          .brand span{display:block;font-size:11px;opacity:.75}
          .mid{display:flex;gap:16px;align-items:center;padding:20px 18px}
          .code{font-size:26px;font-weight:750;letter-spacing:.12em;margin:6px 0 0}
          .meta{display:grid;grid-template-columns:1fr 1fr;gap:10px 16px;padding:0 18px 16px;border-top:1px dashed #e4e8ee;padding-top:14px}
          .meta span{display:block;font-size:11px;color:#64748b}
          .hint{font-size:12px;color:#64748b;padding:0 18px 18px;margin:0}
          svg{width:88px;height:88px;flex-shrink:0}
        </style></head><body>
        <div class="ticket">
          <div class="top">
            <div class="brand"><span class="mark">K</span><div><strong>KonekSik-fi</strong><span>Access Voucher</span></div></div>
            <span>${v.status}</span>
          </div>
          <div class="mid">
            ${voucherQr(v.code)}
            <div><div style="font-size:12px;color:#64748b">Voucher code</div><div class="code">${v.code}</div></div>
          </div>
          <div class="meta">
            <div><span>Plan</span><strong>${v.plan}</strong></div>
            <div><span>Duration</span><strong>${v.duration}</strong></div>
            <div><span>Speed</span><strong>${speed}</strong></div>
            <div><span>Created</span><strong>${v.created}</strong></div>
          </div>
          <p class="hint">CONNECT · ACCESS · ENJOY · Enter this code on the captive portal.</p>
        </div>
        <script>window.onload=function(){window.print();}</script>
      </body></html>`);
      w.document.close();
    }

    if (action === "add-plan") planForm(null);
    if (action === "view-plan") {
      state.planId = id;
      renderPage();
      const host = document.getElementById("page-content");
      if (host) host.scrollTop = 0;
    }
    if (action === "plan-back") {
      state.planId = null;
      renderPage();
    }
    if (action === "add-plan-client") planClientForm(null, id || state.planId);
    if (action === "edit-plan-client") {
      const c = (AppData.planClients || []).find((x) => x.id === id);
      if (c) planClientForm(c, c.planId);
    }
    if (action === "delete-plan-client") {
      const c = (AppData.planClients || []).find((x) => x.id === id);
      if (!c) return;
      UI.confirmDialog({
        title: "Remove client?",
        message: `${UI.escapeHtml(c.houseName)} will be removed from this plan. Connected devices stay on the AP.`,
        confirmText: "Remove",
        danger: true,
        onConfirm: () => {
          AppData.planClients = AppData.planClients.filter((x) => x.id !== id);
          AppData.devices.forEach((d) => {
            if (d.clientId === id) d.clientId = "";
          });
          UI.toast(c.houseName + " removed", "warning");
          renderPage();
        },
      });
    }
    if (action === "adjust-ap-speed") {
      const ap = AppData.accessPoints.find((a) => a.id === id);
      if (!ap) return;
      UI.modal({
        title: "Adjust AP Speed — " + ap.identity,
        width: "460px",
        body: `
          <p class="muted sm">Quick action for this access point. Maps to a preconfigured queue profile later.</p>
          <div class="field mt-10"><label>Speed profile</label>
            <select id="ap-speed-profile">${speedSelect(ap.speedProfile || "Standard")}</select>
          </div>
          ${customSpeedFields({ speed: ap.speedProfile, download: ap.downloadLimit, upload: ap.uploadLimit })}
          <div class="field mt-10"><label>Download (Mbps)</label><input id="ap-dl" type="number" value="${ap.downloadLimit || 10}"></div>
          <div class="field mt-10"><label>Upload (Mbps)</label><input id="ap-ul" type="number" value="${ap.uploadLimit || 5}"></div>
        `,
        actions: `<button type="button" class="btn btn-ghost" data-action="close-modal">Cancel</button>
                  <button type="button" class="btn btn-primary" id="save-ap-speed">Apply</button>`,
      });
      bindSpeedSelect("ap-speed-profile");
      const sync = () => {
        const extra = speedPayload(document.getElementById("ap-speed-profile").value);
        if (extra.speed !== "Custom") {
          const prof = AppData.bandwidthProfiles.find((x) => x.name === extra.speed);
          if (prof) {
            document.getElementById("ap-dl").value = prof.download;
            document.getElementById("ap-ul").value = prof.upload;
          }
        } else {
          document.getElementById("ap-dl").value = extra.download;
          document.getElementById("ap-ul").value = extra.upload;
        }
      };
      document.getElementById("ap-speed-profile").addEventListener("change", sync);
      document.getElementById("save-ap-speed").onclick = () => {
        ap.speedProfile = document.getElementById("ap-speed-profile").value;
        ap.downloadLimit = Number(document.getElementById("ap-dl").value) || ap.downloadLimit;
        ap.uploadLimit = Number(document.getElementById("ap-ul").value) || ap.uploadLimit;
        UI.closeModal();
        UI.toast(ap.identity + " speed set to " + ap.downloadLimit + "/" + ap.uploadLimit + " Mbps", "success");
        renderPage();
      };
    }
    if (action === "edit-plan") planForm(AppData.plans.find((p) => p.id === id));
    if (action === "toggle-plan") {
      const p = AppData.plans.find((x) => x.id === id);
      p.status = p.status === "active" ? "disabled" : "active";
      UI.toast("Plan updated", "info");
      renderPage();
    }
    if (action === "delete-plan") {
      const p = AppData.plans.find((x) => x.id === id);
      UI.confirmDialog({
        title: "Delete plan?",
        message: (p ? p.name + " — " : "") + "Households on this plan will be unassigned. Existing sessions keep their current speed until they expire.",
        confirmText: "Delete",
        danger: true,
        onConfirm: () => {
          AppData.plans = AppData.plans.filter((x) => x.id !== id);
          AppData.planClients = (AppData.planClients || []).filter((c) => c.planId !== id);
          if (state.planId === id) state.planId = null;
          UI.toast("Plan removed", "warning");
          renderPage();
        },
      });
    }

    if (action === "view-ap") {
      const apId = id || t.getAttribute("data-id");
      if (!apId) return;
      state.planId = null;
      state.apId = apId;
      state.route = "access-points";
      if (currentRoute() !== "access-points") location.hash = "access-points";
      renderSidebar();
      renderPage();
      const host = document.getElementById("page-content");
      if (host) host.scrollTop = 0;
    }
    if (action === "ap-back") {
      state.apId = null;
      renderPage();
    }
    if (action === "filter-ap") {
      state.apFilter = t.dataset.filter;
      renderPage();
    }
    if (action === "ap-view") {
      state.apView = t.dataset.view;
      renderPage();
    }
    if (action === "ap-refresh" || action === "ap-retry") {
      AppData.apApiError = false;
      state.apLoading = true;
      renderPage();
      setTimeout(() => {
        AppData.apLastUpdated = new Date().toLocaleTimeString("en-GB", { hour12: false });
        state.apLoading = false;
        UI.toast("Access point data refreshed", "success");
        renderPage();
      }, 700);
    }
    if (action === "restart-ap") {
      const ap = AppData.accessPoints.find((a) => a.id === id);
      UI.confirmDialog({
        title: "Restart Access Point?",
        message: `${ap.identity} will temporarily disconnect all wireless clients. The AP should return online automatically after reboot.`,
        confirmText: "Restart AP",
        danger: true,
        onConfirm: () => simulateApRestart(ap),
      });
    }
    if (action === "ap-diagnostics") {
      const ap = AppData.accessPoints.find((a) => a.id === id);
      UI.modal({
        title: "AP Diagnostics — " + ap.identity,
        body: Object.entries({
          capsmam: "CAPsMAN Connection",
          ip: "IP Connectivity",
          ethernet: "Ethernet Link",
          radio24: "2.4 GHz Radio",
          radio5: "5 GHz Radio",
        }).map(([k, l]) => `<div class="health-row"><span>${l}</span>${UI.badge(ap.diagnostics[k])}</div>`).join("") +
          `<p class="muted sm mt-10">Simulated results. RouterOS commands are not shown to the owner.</p>`,
        actions: `<button class="btn btn-primary" data-action="close-modal">Done</button>`,
      });
    }
    if (action === "view-ap-client") {
      const ap = AppData.accessPoints.find((a) => a.id === t.dataset.ap);
      const c = ap && ap.clients.find((x) => x.id === id);
      if (!c) return;
      const session = c.sessionId ? AppData.sessions.find((s) => s.id === c.sessionId) : null;
      UI.modal({
        title: "Client Details",
        width: "520px",
        body: UI.dl([
          ["Device", c.device],
          ["IP Address", `<span class="mono">${c.ip}</span>`],
          ["MAC Address", `<span class="mono">${c.mac}</span>`],
          ["Access Point", ap.identity],
          ["Radio", c.radio],
          ["Signal", c.signal],
          ["Connection Time", c.uptime],
          ["Authentication", session ? UI.badge("authenticated") : UI.badge("unauthenticated")],
        ]) + (session ? `<h2 class="mt-14" style="margin-bottom:10px">Piso Session</h2>` + UI.dl([
          ["Plan", `${session.plan} / ${session.duration}`],
          ["Started", session.start],
          ["Remaining", session.remaining],
          ["Status", UI.badge(session.status)],
        ]) : `<p class="muted mt-14">No matching Piso WiFi session.</p>`),
        actions: `
          <button type="button" class="btn btn-ghost" data-action="close-modal">Close</button>
          <button type="button" class="btn btn-ghost" data-action="disconnect-device" data-id="dev-1">Disconnect</button>
          <button type="button" class="btn btn-danger" data-action="block-device" data-id="dev-1">Block Device</button>
          ${session ? `<button type="button" class="btn btn-primary" data-action="view-session" data-id="${session.id}">View Session</button>` : ""}
        `,
      });
    }

    if (action === "test-connection") {
      t.disabled = true;
      t.textContent = "Testing…";
      setTimeout(() => {
        t.disabled = false;
        t.textContent = "Test Connection";
        UI.toast("Internet path healthy · 18 ms", "success");
      }, 900);
    }

    if (action === "add-profile") profileForm(null);
    if (action === "edit-profile") profileForm(AppData.bandwidthProfiles.find((p) => p.id === id));
    if (action === "toggle-profile") {
      const p = AppData.bandwidthProfiles.find((x) => x.id === id);
      p.status = p.status === "active" ? "disabled" : "active";
      renderPage();
      UI.toast("Profile updated", "info");
    }
    if (action === "delete-profile") {
      UI.confirmDialog({
        title: "Delete profile?",
        message: "Existing sessions using this profile will keep their current speed until they expire.",
        confirmText: "Delete",
        danger: true,
        onConfirm: () => {
          AppData.bandwidthProfiles = AppData.bandwidthProfiles.filter((p) => p.id !== id);
          UI.toast("Profile removed", "warning");
          renderPage();
        },
      });
    }

    if (action === "toggle-isolation") {
      AppData.security.isolationEnabled = !AppData.security.isolationEnabled;
      AppData.security.clientIsolation = AppData.security.isolationEnabled ? "active" : "disabled";
      renderPage();
      UI.toast("Client isolation " + (AppData.security.isolationEnabled ? "enabled" : "disabled"), "info");
    }
    if (action === "toggle-filter") {
      const f = AppData.contentFiltering.find((x) => x.id === id);
      f.enabled = !f.enabled;
      renderPage();
      UI.toast(f.label + (f.enabled ? " on" : " off"), "info");
    }
    if (action === "unblock-device") {
      AppData.blockedDevices = AppData.blockedDevices.filter((b) => b.id !== id);
      UI.toast("Device unblocked", "success");
      renderPage();
    }
    if (action === "block-device-new") {
      UI.modal({
        title: "Block Device",
        body: `
          <div class="field"><label>MAC address</label><input id="blk-mac" placeholder="XX:XX:XX:XX:XX:XX"></div>
          <div class="field mt-10"><label>Reason</label><input id="blk-reason" value="Manual block"></div>
        `,
        actions: `<button class="btn btn-ghost" data-action="close-modal">Cancel</button>
                  <button class="btn btn-danger" id="do-blk">Block</button>`,
      });
      $("#do-blk").onclick = () => {
        AppData.blockedDevices.unshift({
          id: "blk-" + Date.now(),
          device: "Unknown",
          hostname: "manual",
          mac: $("#blk-mac").value || "XX:XX:XX:XX:XX:XX",
          date: "Aug 24, 2026",
          reason: $("#blk-reason").value || "Manual block",
          status: "blocked",
        });
        UI.closeModal();
        UI.toast("Device blocked", "danger");
        renderPage();
      };
    }

    if (action === "toggle-compact") {
      AppData.settings.compactMode = !AppData.settings.compactMode;
      applyDisplayPrefs();
      renderPage();
    }
    if (action === "toggle-notif") {
      AppData.settings.notifications[id] = !AppData.settings.notifications[id];
      renderPage();
    }
    if (action === "save-settings") {
      AppData.settings.systemName = $("#set-name")?.value || AppData.settings.systemName;
      AppData.settings.locationName = $("#set-loc")?.value || AppData.settings.locationName;
      AppData.settings.theme = $("#set-theme")?.value || "light";
      applyDisplayPrefs();
      UI.toast("Settings saved", "success");
    }
    if (action === "pick-login-logo") document.getElementById("login-logo-file")?.click();
    if (action === "pick-nav-logo") document.getElementById("nav-logo-file")?.click();
    if (action === "clear-login-logo") {
      if (!window.KskBrand) return;
      KskBrand.clearLogin();
      UI.toast("Login logo reset", "info");
      renderPage();
    }
    if (action === "clear-nav-logo") {
      if (!window.KskBrand) return;
      KskBrand.clearNav();
      UI.toast("Navbar logo reset", "info");
      renderPage();
    }

    if (action === "enable-remote") {
      AppData.remoteAccess.enabled = true;
      AppData.remoteAccess.status = "connected";
      UI.toast("Remote access enabled", "success");
      renderPage();
    }
    if (action === "disable-remote") {
      AppData.remoteAccess.enabled = false;
      AppData.remoteAccess.status = "disabled";
      UI.toast("Remote access disabled", "warning");
      renderPage();
    }
    if (action === "test-remote") UI.toast("Secure tunnel reachable", "success");

    if (action === "add-vendo") {
      UI.modal({
        title: "Add Sub Vendo",
        width: "480px",
        body: `
          <p class="muted sm">ESP32 unit. It joins the AP over Wi-Fi. Binding (which AP it belongs to) is recorded on MikroTik CAPsMAN.</p>
          <div class="field mt-14"><label>Unit name</label><input id="v-name" placeholder="KonekSik-fi #004"></div>
          <div class="field mt-10"><label>Location</label><input id="v-loc" placeholder="Branch name"></div>
          <div class="field mt-10"><label>ESP32 MAC <span class="opt-label">(optional)</span></label><input id="v-mac" class="mono" placeholder="24:6F:28:AA:10:04"></div>
          <div class="field mt-10"><label>Bind to AP via MikroTik <span class="opt-label">(optional)</span></label>
            <select id="v-ap">${apOptions("")}</select>
          </div>
        `,
        actions: `<button class="btn btn-ghost" data-action="close-modal">Cancel</button>
                  <button class="btn btn-primary" id="do-vendo">Add</button>`,
      });
      $("#do-vendo").onclick = () => {
        const apId = $("#v-ap").value;
        const created = {
          id: "vendo-" + Date.now(),
          name: $("#v-name").value || "KonekSik-fi #004",
          type: "ESP32",
          deviceId: "KSK-ESP-" + String(AppData.subVendos.length + 1).padStart(3, "0"),
          mac: ($("#v-mac").value || "").trim(),
          status: "offline",
          users: 0,
          waiting: 0,
          sessions: 0,
          sales: 0,
          uptime: "—",
          location: $("#v-loc").value || "Unassigned",
          apId: "",
          mikrotikBound: false,
          bindStatus: "unbound",
        };
        AppData.subVendos.push(created);
        UI.closeModal();
        if (apId) {
          const ap = AppData.accessPoints.find((a) => a.id === apId);
          if (ap) {
            simulateVendoBind(created, ap);
            return;
          }
        }
        UI.toast("Sub vendo added", "success");
        renderPage();
      };
    }
    if (action === "bind-vendo") {
      const v = AppData.subVendos.find((x) => x.id === id);
      if (v) bindVendoForm(v);
    }
    if (action === "view-vendo" || action === "monitor-vendo") {
      const v = AppData.subVendos.find((x) => x.id === id);
      const ap = AppData.accessPoints.find((a) => a.id === v.apId);
      const bound = v.mikrotikBound && ap;
      UI.modal({
        title: (action === "monitor-vendo" ? "Monitor — " : "") + v.name,
        width: "520px",
        body: UI.dl([
          ["Hardware", "ESP32"],
          ["Device ID", `<span class="mono">${v.deviceId || v.id}</span>`],
          ["MAC", `<span class="mono">${v.mac || "—"}</span>`],
          ["Status", UI.badge(v.status)],
          ["Location", v.location],
          ["Connection", "Wi-Fi station on the AP"],
          ["MikroTik", bound ? UI.badge("connected") + " " + AppData.mikrotik.model : UI.badge("unbound", "Not bound")],
          ["Access Point", bound ? ap.identity + " · " + ap.model : "Unassigned"],
          ["Bind path", bound ? "ESP32 Wi-Fi → " + ap.identity + " → MikroTik CAPsMAN" : "Not bound through MikroTik"],
          ["Users", String(v.users || 0)],
          ["Waiting for access", String(v.waiting || 0)],
          ["Active sessions", String(v.sessions || 0)],
          ["Today's sales", UI.peso(v.sales || 0)],
          ["Uptime", v.uptime],
        ]),
        actions: `
          <button type="button" class="btn btn-ghost" data-action="close-modal">Close</button>
          <button type="button" class="btn btn-primary" data-action="bind-vendo" data-id="${v.id}">${bound ? "Change AP" : "Bind AP"}</button>
        `,
      });
    }
    if (action === "rename-vendo") {
      const v = AppData.subVendos.find((x) => x.id === id);
      UI.modal({
        title: "Rename unit",
        body: `<div class="field"><label>Name</label><input id="rn" value="${v.name}"></div>`,
        actions: `<button class="btn btn-ghost" data-action="close-modal">Cancel</button>
                  <button class="btn btn-primary" id="do-rn">Save</button>`,
      });
      $("#do-rn").onclick = () => {
        v.name = $("#rn").value;
        UI.closeModal();
        renderPage();
        UI.toast("Unit renamed", "success");
      };
    }
    if (action === "disable-vendo") {
      const v = AppData.subVendos.find((x) => x.id === id);
      v.status = v.status === "disabled" ? "online" : "disabled";
      renderPage();
      UI.toast("Unit status updated", "info");
    }

    if (action === "ota-update") {
      UI.confirmDialog({
        title: "Install update v1.4.3?",
        message: "The controller will download, install, and reboot. Active users may briefly lose connectivity.",
        confirmText: "Update Now",
        onConfirm: runOta,
      });
    }

    if (action === "reboot") {
      UI.confirmDialog({
        title: "Restart KonekSik-fi?",
        message: "Active users may temporarily lose their connection.",
        confirmText: "Restart",
        danger: true,
        onConfirm: () => {
          const ov = $("#boot-overlay");
          ov.classList.add("show");
          setTimeout(() => {
            ov.classList.remove("show");
            UI.toast("Controller restarted (simulated)", "success");
          }, 2200);
        },
      });
    }

    if (action === "logout") {
      closeMenus();
      UI.confirmDialog({
        title: "Logout?",
        message: "You will be signed out of the KonekSik-fi Admin Console.",
        confirmText: "Logout",
        danger: true,
        onConfirm: () => {
          sessionStorage.removeItem(AUTH_KEY);
          if (window.KskAuth) window.KskAuth.showLogin();
          else window.location.replace("index.html");
        },
      });
    }
  });

  document.addEventListener("input", (e) => {
    if (e.target.id !== "ap-search") return;
    state.apQuery = e.target.value;
    const pos = e.target.selectionStart;
    renderPage({ quiet: true });
    const el = document.getElementById("ap-search");
    if (el) {
      el.focus();
      try { el.setSelectionRange(pos, pos); } catch (err) {}
    }
  });

  document.addEventListener("change", (e) => {
    if (e.target.id === "set-theme") {
      AppData.settings.theme = e.target.value;
      applyDisplayPrefs();
    }
    if (e.target.id === "device-filter") {
      state.deviceFilter = e.target.value;
      renderPage();
    }
    if (e.target.id === "login-logo-file" || e.target.id === "nav-logo-file") {
      const file = e.target.files && e.target.files[0];
      e.target.value = "";
      if (!file || !window.KskBrand) return;
      const kind = e.target.id === "nav-logo-file" ? "nav" : "login";
      KskBrand.fromFile(file, kind).then((dataUrl) => {
        if (kind === "nav") KskBrand.saveNav(dataUrl);
        else KskBrand.saveLogin(dataUrl);
        UI.toast(kind === "nav" ? "Navbar logo updated" : "Login logo updated", "success");
        renderPage();
      }).catch((err) => {
        UI.toast(err.message || "Could not upload that image", "warning");
      });
    }
  });

  function currentRoute() {
    return location.hash.replace(/^#\/?/, "") || "dashboard";
  }

  window.addEventListener("hashchange", () => {
    const r = currentRoute();
    if (Pages[r] || r === "dashboard") {
      if (r !== "access-points") state.apId = null;
      if (r !== "plans") state.planId = null;
      state.route = r;
      renderSidebar();
      renderPage();
      closeSidebar();
    }
  });

  window.addEventListener("resize", () => UI.initCharts());

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      UI.closeModal();
      UI.closeDrawer();
      closeMenus();
      closeSidebar();
    }
    if (e.key === "Enter" && e.target.classList && e.target.classList.contains("row-select")) {
      e.preventDefault();
      e.target.click();
    }
  });

  function init() {
    applyDisplayPrefs();
    if (window.KskBrand) window.KskBrand.apply();
    state.route = currentRoute();
    renderSidebar();
    renderPage();
    booted = true;
    if (window.KskMikroTik) window.KskMikroTik.start();
    window.addEventListener("ksk-mikrotik-updated", () => {
      if (state.route === "dashboard" || state.route === "network") renderPage({ quiet: true });
    });
    if (!window._kskApTimer) {
      window._kskApTimer = setInterval(() => {
        const el = document.getElementById("ap-updated");
        if (!el) return;
        AppData.apLastUpdated = new Date().toLocaleTimeString("en-GB", { hour12: false });
        el.textContent = AppData.apLastUpdated;
      }, (AppData.settings.apRefreshSeconds || 10) * 1000);
    }
  }

  return { init, AUTH_KEY };
})();
