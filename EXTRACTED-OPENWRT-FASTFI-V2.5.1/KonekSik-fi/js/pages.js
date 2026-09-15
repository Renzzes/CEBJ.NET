/**
 * Page renderers — each function returns HTML from AppData.
 */
window.Pages = (function () {
  const { badge, statusRow, progressBar, toggle, kpi, peso, escapeHtml } = UI;

  function vendoPairs() {
    return (AppData.subVendos || []).map((v) => {
      const ap = AppData.accessPoints.find((a) => a.id === v.apId);
      return {
        vendo: v,
        ap,
        connected: Number(v.users) || 0,
        waiting: Number(v.waiting) || 0,
        sessions: Number(v.sessions) || 0,
        sales: Number(v.sales) || 0,
      };
    });
  }

  function siteTotals() {
    return vendoPairs()
      .filter((row) => row.vendo.status !== "disabled")
      .reduce((acc, row) => ({
        connected: acc.connected + row.connected,
        waiting: acc.waiting + row.waiting,
        sessions: acc.sessions + row.sessions,
        sales: acc.sales + row.sales,
      }), { connected: 0, waiting: 0, sessions: 0, sales: 0 });
  }

  function planHouseholds(planId) {
    return (AppData.planClients || []).filter((c) => c.planId === planId);
  }

  function clientDevices(clientId) {
    return AppData.devices.filter((d) => d.clientId === clientId);
  }

  function facebookCell(fb) {
    if (!fb) return `<span class="muted">—</span>`;
    const handle = String(fb).replace(/^@/, "");
    const href = /^https?:\/\//i.test(handle) ? handle : `https://facebook.com/${handle}`;
    return `<a class="linkish" href="${escapeHtml(href)}" target="_blank" rel="noopener">${escapeHtml(handle)}</a>`;
  }

  const meta = {
    dashboard: ["Dashboard", "Overview of your KonekSik-fi system"],
    sales: ["Sales", "Coin and voucher transaction history"],
    "coin-rates": ["Coin Rates", "Piso WiFi pricing and time allocations"],
    plans: ["Plans", "Custom plan rates mapped to speed tiers"],
    sessions: ["Sessions", "Active, expired, and historical client sessions"],
    vouchers: ["Vouchers", "Generate and manage access vouchers"],
    network: ["Network Overview", "MikroTik and internet infrastructure status"],
    "access-points": ["Access Points", "Monitor connected MikroTik access points and wireless clients."],
    devices: ["Connected Devices", "Clients on the customer network"],
    bandwidth: ["Bandwidth", "Speed profiles and current traffic"],
    security: ["Security", "Protection status, filtering, and blocked devices"],
    settings: ["Settings", "General KonekSik-fi console preferences"],
    "remote-access": ["Remote Access", "Secure tunnel and remote support status"],
    "sub-vendo": ["Sub Vendo", "ESP32 units bound to Access Points through MikroTik"],
    ota: ["OTA Update", "Controller firmware and system updates"],
  };

  function storageOverview(mt) {
    const slices = mt.storageSlices || [];
    const total = mt.storageTotalMb || 128;
    const used = slices.reduce((s, x) => s + x.mb, 0);
    const free = Math.max(0, total - used);
    const usedPct = total ? (used / total) * 100 : 0;
    const size = 220;
    const sw = 36;
    const r = (size - sw) / 2 - 2;
    const C = 2 * Math.PI * r;
    const gap = 8;
    let offset = 0;
    const arcs = slices.map((slice) => {
      const raw = (slice.mb / total) * C;
      const len = raw <= 0 ? 0 : Math.max(2.5, raw - gap);
      const dashOffset = -offset;
      offset += raw;
      if (len <= 0) return "";
      return `<circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${slice.color}" stroke-width="${sw}"
        stroke-linecap="butt" stroke-dasharray="${len.toFixed(2)} ${C.toFixed(2)}" stroke-dashoffset="${dashOffset.toFixed(2)}"
        transform="rotate(-90 ${size / 2} ${size / 2})"></circle>`;
    }).join("");
    const fmt = (n) => {
      const v = Math.round(n * 10) / 10;
      return `${v % 1 === 0 ? v.toFixed(0) : v.toFixed(1)} MB`;
    };
    return `
      <div class="sto">
        <div class="sto-head">
          <h3>Storage Overview</h3>
          <span class="sto-src ${mt.storageLive ? "live" : "sample"}">${mt.storageLive ? "Live" : "Sample"}</span>
        </div>
        <div class="sto-body">
          <div class="sto-donut">
            <svg viewBox="0 0 ${size} ${size}" aria-hidden="true">
              <circle class="sto-track" cx="${size / 2}" cy="${size / 2}" r="${r}" stroke-width="${sw}"></circle>
              ${arcs}
            </svg>
            <div class="sto-center">
              <strong>${usedPct.toFixed(1)}%</strong>
              <span>USED</span>
            </div>
          </div>
          <ul class="sto-legend">
            ${slices.map((slice) => {
              const pct = used ? (slice.mb / used) * 100 : 0;
              return `<li>
                <span class="sto-dot" style="background:${slice.color}"></span>
                <span class="sto-name">${escapeHtml(slice.label)}</span>
                <span class="sto-vals"><strong>${fmt(slice.mb)}</strong><em>${pct.toFixed(1)}%</em></span>
              </li>`;
            }).join("")}
          </ul>
        </div>
        <div class="sto-foot">
          <div><span>Total Storage</span><strong>${fmt(total)}</strong></div>
          <div><span>Used Storage</span><strong>${fmt(used)}</strong></div>
          <div><span>Available Storage</span><strong>${fmt(free)}</strong></div>
          <div><span>Temperature</span><strong>${mt.temperature == null ? "N/A" : mt.temperature + "°C"}</strong></div>
        </div>
      </div>`;
  }

  const ICO_WIFI = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">
    <path class="wifi-arc a3" d="M4.8 10.8a10.2 10.2 0 0 1 14.4 0"/>
    <path class="wifi-arc a2" d="M7.6 13.8a6.2 6.2 0 0 1 8.8 0"/>
    <path class="wifi-arc a1" d="M10.2 16.7a2.4 2.4 0 0 1 3.6 0"/>
    <circle class="wifi-dot" cx="12" cy="19.4" r="1.25" fill="currentColor" stroke="none"/>
  </svg>`;

  function dashboard() {
    const d = AppData;
    const tot = siteTotals();
    const pairs = vendoPairs().filter((row) => row.ap && row.vendo.mikrotikBound && row.vendo.status !== "disabled");
    const recent = d.sessions.slice(0, 4);
    const users = d.devices.filter((x) => x.status === "online" && x.auth === "authenticated");
    return `
      <div class="grid grid-4">
        ${kpi(peso(tot.sales), "Today's Sales")}
        ${kpi(peso(d.kpis.weekSales), "Weekly Sales")}
        ${kpi(peso(d.kpis.monthSales), "Monthly Sales")}
        ${kpi(`${tot.sessions} / ${tot.connected}`, "Connected Sessions / Active Users")}
      </div>
      <article class="card mt-14">
        <div class="card-h"><h2>Per AP + ESP32</h2><span class="muted sm">Dashboard KPIs are the sum of these rows. Sub Vendo still shows each unit separately.</span></div>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>Access Point</th><th>ESP32</th><th>Connected</th><th>Waiting</th><th>Sessions</th><th>Today's sales</th></tr></thead>
          <tbody>${pairs.length ? pairs.map((row) => `<tr>
            <td>${escapeHtml(row.ap.identity)}</td>
            <td>${escapeHtml(row.vendo.name)}</td>
            <td>${row.connected}</td>
            <td>${row.waiting}</td>
            <td>${row.sessions}</td>
            <td>${peso(row.sales)}</td>
          </tr>`).join("") : `<tr><td colspan="6">${UI.emptyState("No bound units", "Bind an ESP32 to an AP in Sub Vendo.")}</td></tr>`}
          <tr>
            <td colspan="2"><strong>Total</strong></td>
            <td><strong>${tot.connected}</strong></td>
            <td><strong>${tot.waiting}</strong></td>
            <td><strong>${tot.sessions}</strong></td>
            <td><strong>${peso(tot.sales)}</strong></td>
          </tr>
          </tbody>
        </table></div>
      </article>

      <div class="grid grid-2 mt-14">
        <article class="card">
          <div class="card-h"><h2>Network Status</h2></div>
          <div class="status-list">
            ${statusRow("Internet", d.status.internet)}
            ${statusRow("MikroTik", d.status.mikrotik === "online" ? "connected" : d.status.mikrotik)}
            ${statusRow("KonekSik-fi Controller", d.status.controller === "online" ? "connected" : d.status.controller)}
            ${statusRow("Access Point", d.status.accessPoint)}
          </div>
          <div class="metrics">
            <div class="metric"><dt>Latency</dt><dd>${d.networkHealth.latencyMs} ms</dd></div>
            <div class="metric"><dt>Packet Loss</dt><dd>${d.networkHealth.packetLoss}%</dd></div>
            <div class="metric"><dt>Download</dt><dd>${d.networkHealth.downloadMbps} Mbps</dd></div>
            <div class="metric"><dt>Upload</dt><dd>${d.networkHealth.uploadMbps} Mbps</dd></div>
          </div>
          <canvas class="spark" data-spark="networkHealth.sparkline"></canvas>
        </article>

        <article class="card mk-card">
          <div class="mk-head">
            <div class="mk-title">
              <span class="mk-mark ${d.mikrotik.connection === "connected" || d.status.mikrotik === "online" ? "live" : "off"}" title="${d.mikrotik.connection === "connected" || d.status.mikrotik === "online" ? "Live — MikroTik connected" : "MikroTik offline"}">${ICO_WIFI}</span>
              <h2>MikroTik Router</h2>
            </div>
            ${badge(d.mikrotik.connection)}
          </div>
          <div class="mk-facts">
            <div><span>Model</span><strong>${escapeHtml(d.mikrotik.model)}</strong></div>
            <div><span>RouterOS</span><strong>${escapeHtml(d.mikrotik.routeros)}</strong></div>
            <div><span>Uptime</span><strong>${escapeHtml(d.mikrotik.uptime)}</strong></div>
            <div><span>Connection</span><strong class="ok">Connected</strong></div>
            <div><span>CPU</span><strong>${d.mikrotik.cpu}%</strong></div>
            <div><span>Memory</span><strong>${d.mikrotik.memory}%</strong></div>
          </div>
          ${storageOverview(d.mikrotik)}
        </article>
      </div>

      <article class="card blocked-card mt-14">
        <div class="blocked-head">
          <div>
            <h2>Blocked Devices</h2>
            <p class="muted sm">Denied on the customer network</p>
          </div>
          <div class="blocked-count">${d.blockedDevices.length}</div>
        </div>
        <div class="blocked-grid">
          ${d.blockedDevices.map((b, i) => `<div class="blocked-tile ${i === 0 ? "latest" : ""}">
            <div class="blocked-tile-h">
              <strong>${escapeHtml(b.device)}</strong>
              ${i === 0 ? `<span class="chip-lite">Latest</span>` : badge("blocked")}
            </div>
            <p class="mono sm">${escapeHtml(b.hostname)}</p>
            <p class="mono sm muted">${escapeHtml(b.mac)}</p>
            <p class="blocked-reason">${escapeHtml(b.reason)}</p>
            <p class="muted sm">${escapeHtml(b.date)}</p>
          </div>`).join("")}
        </div>
        <div class="blocked-foot">
          <button class="btn btn-ghost" data-action="goto" data-route="security">Manage Blocked Devices</button>
        </div>
      </article>

      <article class="card mt-14">
        <div class="card-h">
          <h2>Recent Sessions</h2>
          <button class="btn btn-ghost btn-sm" data-action="goto" data-route="sessions">View All Sessions</button>
        </div>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>Device</th><th>Plan</th><th>Duration</th><th>Status</th></tr></thead>
          <tbody>${recent.map((s) => `<tr>
            <td>${s.type}</td><td>${s.plan}</td><td>${s.remainingMin ? s.remaining : s.duration}</td>
            <td>${badge(s.status)}</td>
          </tr>`).join("")}</tbody>
        </table></div>
      </article>

      <article class="card mt-14">
        <div class="card-h"><h2>Connected Users</h2></div>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>Device</th><th>IP Address</th><th>Plan</th><th>Remaining Time</th><th>Status</th><th>Action</th></tr></thead>
          <tbody>${users.map((u) => `<tr>
            <td>${u.hostname}</td>
            <td class="mono">${u.ip}</td>
            <td>${u.plan}</td>
            <td>${u.remaining}</td>
            <td>${badge(u.status)}</td>
            <td class="row-actions">
              <button class="linkish" data-action="view-device" data-id="${u.id}">View</button>
              <button class="linkish" data-action="disconnect-device" data-id="${u.id}">Disconnect</button>
              <button class="linkish danger" data-action="block-device" data-id="${u.id}">Block</button>
            </td>
          </tr>`).join("")}</tbody>
        </table></div>
      </article>
    `;
  }

  function sales(filter, page) {
    const f = filter || "today";
    const PAGE = 6;
    const map = {
      today: (t) => t.day === "today",
      yesterday: (t) => t.day === "yesterday",
      week: (t) => t.day === "today" || t.day === "yesterday" || t.day === "week",
      month: () => true,
    };
    const all = AppData.sales.filter(map[f] || map.today);
    const pages = Math.max(1, Math.ceil(all.length / PAGE));
    const p = Math.min(Math.max(1, page || 1), pages);
    const rows = all.slice((p - 1) * PAGE, p * PAGE);
    return `
      <div class="page-sales">
      <div class="filter-row">
        <div class="grid grid-4" style="flex:1">
          ${kpi(peso(siteTotals().sales), "Today's Sales")}
          ${kpi(peso(AppData.kpis.weekSales), "This Week")}
          ${kpi(peso(AppData.kpis.monthSales), "This Month")}
          ${kpi(AppData.kpis.totalTransactions, "Total Transactions")}
        </div>
      </div>
      <article class="card">
        <div class="card-h"><h2>Sales Trend</h2><span class="muted sm">Last 7 days</span></div>
        <canvas class="chart" data-line="sales"></canvas>
      </article>
      <article class="card sales-table-card">
        <div class="card-h">
          <h2>Transactions</h2>
          <button class="btn btn-ghost btn-sm" data-action="reset-sales">Reset</button>
        </div>
        <div class="filter-bar" data-sales-filter="${f}">
          ${["today","yesterday","week","month"].map((k) => {
            const labels = { today: "Today", yesterday: "Yesterday", week: "This Week", month: "This Month" };
            return `<button class="chip ${f===k?"active":""}" data-action="filter-sales" data-filter="${k}">${labels[k]}</button>`;
          }).join("")}
        </div>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>Transaction ID</th><th>Date/Time</th><th>Amount</th><th>Payment Type</th><th>Plan</th><th>Duration</th><th>Status</th></tr></thead>
          <tbody>${rows.length ? rows.map((t) => `<tr>
            <td class="mono">${t.id}</td>
            <td>${t.datetime}</td>
            <td>${peso(t.amount)}</td>
            <td>${t.type}</td>
            <td>${t.plan}</td>
            <td>${t.duration}</td>
            <td>${badge(t.status)}</td>
          </tr>`).join("") : `<tr><td colspan="7">${UI.emptyState("No transactions", "Nothing in this period.")}</td></tr>`}</tbody>
        </table></div>
        <div class="pager">
          <span>Showing ${all.length ? (p - 1) * PAGE + 1 : 0}–${Math.min(p * PAGE, all.length)} of ${all.length}</span>
          <div class="pager-btns">
            <button class="btn btn-ghost btn-sm" data-action="sales-page" data-page="${p - 1}" ${p <= 1 ? "disabled" : ""}>Previous</button>
            <span>Page ${p} of ${pages}</span>
            <button class="btn btn-ghost btn-sm" data-action="sales-page" data-page="${p + 1}" ${p >= pages ? "disabled" : ""}>Next</button>
          </div>
        </div>
      </article>
      </div>
    `;
  }

  function coinRates() {
    return `
      <div class="filter-row section">
        <p class="muted">Piso WiFi coin-to-time mapping. Speed profiles map to preconfigured MikroTik queues later.</p>
        <button class="btn btn-primary" data-action="add-coin-rate">Add Coin Rate</button>
      </div>
      <div class="rate-grid">
        ${AppData.coinRates.length ? AppData.coinRates.map((r) => `
          <article class="card rate-card">
            <div class="amount">${peso(r.coin)}</div>
            <div class="time">${r.label}</div>
            <p class="sm">${r.speed === "Custom" ? `Custom · ${r.download}/${r.upload} Mbps` : r.speed + " profile"}</p>
            <div class="mt-10">${badge(r.status)}</div>
            <div class="row-actions mt-14">
              <button class="btn btn-ghost btn-sm" data-action="edit-coin-rate" data-id="${r.id}">Edit</button>
              <button class="btn btn-ghost btn-sm" data-action="toggle-coin-rate" data-id="${r.id}">${r.status === "active" ? "Disable" : "Enable"}</button>
              <button class="btn btn-ghost btn-sm danger" data-action="delete-coin-rate" data-id="${r.id}">Delete</button>
            </div>
          </article>
        `).join("") : `<article class="card">${UI.emptyState("No coin rates", "Add a coin-to-time mapping.")}</article>`}
      </div>
      <article class="card mt-14">
        <h2>Rate table</h2>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>Coin value</th><th>Time</th><th>Speed profile</th><th>Status</th><th></th></tr></thead>
          <tbody>${AppData.coinRates.map((r) => `<tr>
            <td>${peso(r.coin)}</td><td>${r.label}</td>
            <td>${r.speed === "Custom" ? `Custom (${r.download}/${r.upload} Mbps)` : r.speed}</td>
            <td>${badge(r.status)}</td>
            <td class="row-actions">
              <button class="linkish" data-action="edit-coin-rate" data-id="${r.id}">Edit</button>
              <button class="linkish danger" data-action="delete-coin-rate" data-id="${r.id}">Delete</button>
            </td>
          </tr>`).join("")}</tbody>
        </table></div>
      </article>
    `;
  }

  function plans(planId) {
    if (planId) {
      const p = AppData.plans.find((x) => x.id === planId);
      if (!p) return `<article class="card">${UI.emptyState("Plan not found", "")}<button class="btn btn-ghost" data-action="plan-back">Back</button></article>`;
      const clients = planHouseholds(p.id);
      const devices = AppData.devices.filter((d) => clients.some((c) => c.id === d.clientId));
      const apIds = [...new Set(clients.map((c) => c.apId).filter(Boolean))];
      const aps = apIds.map((id) => AppData.accessPoints.find((a) => a.id === id)).filter(Boolean);
      return `
        <div class="filter-row section">
          <div>
            <button class="linkish" data-action="plan-back">← Plans</button>
            <h2 style="font-size:20px;margin-top:6px">${escapeHtml(p.name)}</h2>
            <p class="muted">${peso(p.price)} · ${p.download}/${p.upload} Mbps · ${p.duration}</p>
          </div>
          <div class="row-actions">
            <button class="btn btn-primary" data-action="add-plan-client" data-id="${p.id}">Add Client</button>
            <button class="btn btn-ghost" data-action="edit-plan" data-id="${p.id}">Edit</button>
            <button class="btn btn-ghost danger" data-action="delete-plan" data-id="${p.id}">Delete</button>
            ${badge(p.status)}
          </div>
        </div>
        <div class="grid grid-3">
          ${kpi(clients.length, "Clients on plan")}
          ${kpi(aps.length, "Access Points")}
          ${kpi(devices.filter((d) => d.status === "online").length, "Devices online")}
        </div>
        <div class="client-stack mt-14">
          ${clients.length ? clients.map((c) => {
            const ap = AppData.accessPoints.find((a) => a.id === c.apId);
            const own = clientDevices(c.id);
            return `<article class="card client-card">
              <div class="card-h">
                <div>
                  <div class="client-kicker">${ap ? escapeHtml(ap.identity) : "No AP"} · House No. ${escapeHtml(c.houseNumber || "—")}</div>
                  <div class="client-title">${escapeHtml(c.houseName)}</div>
                  <p class="client-availed">${escapeHtml(ap ? ap.identity : "Unassigned")} — ${escapeHtml(c.houseName)} availed ${p.download} Mbps for ${peso(p.price)}</p>
                </div>
                ${badge(c.status || "active")}
              </div>
              <dl class="client-meta">
                <div><dt>House name</dt><dd>${escapeHtml(c.houseName)}</dd></div>
                <div><dt>House number</dt><dd>${escapeHtml(c.houseNumber || "—")}</dd></div>
                <div><dt>Contact number</dt><dd>${escapeHtml(c.contact || "—")}</dd></div>
                <div><dt>FB <span class="opt-label">(optional)</span></dt><dd>${facebookCell(c.facebook)}</dd></div>
              </dl>
              <p class="sm muted mt-14">Deployed on ${ap ? `${escapeHtml(ap.identity)} · ${escapeHtml(ap.model)} · ${escapeHtml(ap.ip)}` : "no access point yet"}
                ${ap ? ` · AP speed ${ap.downloadLimit || "—"}/${ap.uploadLimit || "—"} Mbps` : ""}</p>
              <div class="row-actions mt-14">
                <button class="btn btn-ghost btn-sm" data-action="edit-plan-client" data-id="${c.id}">Edit client</button>
                ${ap ? `<button class="btn btn-primary btn-sm" data-action="adjust-ap-speed" data-id="${ap.id}">Adjust Speed</button>
                <button class="btn btn-ghost btn-sm" data-action="view-ap" data-id="${ap.id}">AP Details</button>` : ""}
                <button class="btn btn-ghost btn-sm" data-action="delete-plan-client" data-id="${c.id}">Remove</button>
              </div>
              <div class="nested-table">
                <h3>Connected devices on this client</h3>
                <div class="table-wrap"><table class="table">
                  <thead><tr><th>Device</th><th>Type</th><th>IP</th><th>Usage</th><th>Speed</th><th>Status</th><th></th></tr></thead>
                  <tbody>${own.length ? own.map((d) => `<tr>
                    <td>${escapeHtml(d.hostname)}</td>
                    <td>${escapeHtml(d.type)}</td>
                    <td class="mono">${escapeHtml(d.ip)}</td>
                    <td>${escapeHtml(d.usage)}</td>
                    <td>${escapeHtml(d.speed)}</td>
                    <td>${d.blocked ? badge("blocked") : badge(d.status)}</td>
                    <td class="row-actions">
                      <button class="linkish" data-action="view-device" data-id="${d.id}">View</button>
                      <button class="linkish" data-action="disconnect-device" data-id="${d.id}">Disconnect</button>
                    </td>
                  </tr>`).join("") : `<tr><td colspan="7">${UI.emptyState("No devices", "No stations are associated with this household yet.")}</td></tr>`}</tbody>
                </table></div>
              </div>
            </article>`;
          }).join("") : `<article class="card">${UI.emptyState("No clients yet", "Add a household or location that availed this plan.")}<div class="mt-14"><button class="btn btn-primary" data-action="add-plan-client" data-id="${p.id}">Add Client</button></div></article>`}
        </div>
        <h2 class="mt-14" style="margin-bottom:10px">Access Points where this plan is deployed</h2>
        <div class="ap-grid">
          ${aps.length ? aps.map((ap) => {
            const n = clients.filter((c) => c.apId === ap.id).length;
            const names = clients.filter((c) => c.apId === ap.id).map((c) => c.houseName).join(", ");
            return `<article class="card">
              <div class="card-h">${badge(ap.status)}<span class="muted sm">${escapeHtml(ap.ip)}</span></div>
              <div class="ap-name">${escapeHtml(ap.identity)}</div>
              <p class="muted sm">${escapeHtml(ap.model)}</p>
              <p class="mt-10"><strong>${n}</strong> client${n === 1 ? "" : "s"} · ${escapeHtml(names)}</p>
              <p class="sm muted mt-10">Current AP speed · ${escapeHtml(ap.speedProfile || "Standard")} · ${ap.downloadLimit || "—"}/${ap.uploadLimit || "—"} Mbps</p>
              <div class="row-actions mt-14">
                <button class="btn btn-primary btn-sm" data-action="adjust-ap-speed" data-id="${ap.id}">Adjust Speed</button>
                <button class="btn btn-ghost btn-sm" data-action="view-ap" data-id="${ap.id}">AP Details</button>
              </div>
            </article>`;
          }).join("") : `<article class="card">${UI.emptyState("No AP deployment", "Assign an access point when you add a client.")}</article>`}
        </div>
      `;
    }
    return `
      <div class="filter-row section">
        <p class="muted">Owner plan rates map a peso amount to a speed tier (for example ${peso(600)} → 50 Mbps). Open a plan to record households, AP deployment, and connected devices.</p>
        <button class="btn btn-primary" data-action="add-plan">Add Plan</button>
      </div>
      <div class="grid grid-3">
        ${AppData.plans.map((p) => {
          const n = planHouseholds(p.id).length;
          return `
          <article class="card row-select" data-action="view-plan" data-id="${p.id}" tabindex="0">
            <div class="card-h"><h2>${escapeHtml(p.name)}</h2>${badge(p.status)}</div>
            <div class="kpi-value">${peso(p.price)}</div>
            <p class="muted sm mt-10">${p.download} Mbps down · ${p.upload} Mbps up</p>
            <p class="sm mt-10">${escapeHtml(p.duration)} · ${n} client${n === 1 ? "" : "s"}</p>
            <div class="row-actions mt-14">
              <button class="btn btn-primary btn-sm" data-action="view-plan" data-id="${p.id}">View clients</button>
              <button class="btn btn-ghost btn-sm" data-action="edit-plan" data-id="${p.id}">Edit</button>
              <button class="btn btn-ghost btn-sm" data-action="toggle-plan" data-id="${p.id}">${p.status === "active" ? "Disable" : "Enable"}</button>
              <button class="btn btn-ghost btn-sm danger" data-action="delete-plan" data-id="${p.id}">Delete</button>
            </div>
          </article>`;
        }).join("")}
      </div>
      <article class="card mt-14">
        <h2>Plan table</h2>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>Plan</th><th>Rate</th><th>Download</th><th>Upload</th><th>Duration</th><th>Clients</th><th>Status</th><th></th></tr></thead>
          <tbody>${AppData.plans.map((p) => `<tr>
            <td>${escapeHtml(p.name)}</td>
            <td>${peso(p.price)}</td>
            <td>${p.download} Mbps</td>
            <td>${p.upload} Mbps</td>
            <td>${escapeHtml(p.duration)}</td>
            <td>${planHouseholds(p.id).length}</td>
            <td>${badge(p.status)}</td>
            <td class="row-actions">
              <button class="linkish" data-action="view-plan" data-id="${p.id}">View</button>
              <button class="linkish" data-action="edit-plan" data-id="${p.id}">Edit</button>
              <button class="linkish danger" data-action="delete-plan" data-id="${p.id}">Delete</button>
            </td>
          </tr>`).join("")}</tbody>
        </table></div>
      </article>
    `;
  }

  function sessions(tab) {
    const t = tab || "active";
    const list = AppData.sessions.filter((s) => (t === "all" ? true : s.status === t));
    return `
      <div class="tabs">
        ${["active","expired","all"].map((k) => `<button class="tab ${t===k?"active":""}" data-action="tab-sessions" data-tab="${k}">${UI.titleCase(k)}</button>`).join("")}
      </div>
      <article class="card">
        <div class="table-wrap"><table class="table">
          <thead><tr>
            <th>Session ID</th><th>Device</th><th>IP Address</th><th>MAC Address</th>
            <th>Plan</th><th>Start Time</th><th>Expiration</th><th>Remaining</th><th>Status</th><th>Actions</th>
          </tr></thead>
          <tbody>${list.map((s) => `<tr>
            <td class="mono">${s.id}</td>
            <td>${s.device}</td>
            <td class="mono">${s.ip}</td>
            <td class="mono">${s.mac}</td>
            <td>${s.plan}</td>
            <td>${s.start}</td>
            <td>${s.expires}</td>
            <td>${s.remaining}</td>
            <td>${badge(s.status)}</td>
            <td class="row-actions">
              <button class="linkish" data-action="view-session" data-id="${s.id}">View</button>
              <button class="linkish" data-action="extend-session" data-id="${s.id}">Extend</button>
              <button class="linkish" data-action="disconnect-session" data-id="${s.id}">Disconnect</button>
              <button class="linkish danger" data-action="block-session" data-id="${s.id}">Block</button>
            </td>
          </tr>`).join("") || `<tr><td colspan="10">${UI.emptyState("No sessions", "Nothing in this tab.")}</td></tr>`}</tbody>
        </table></div>
      </article>
    `;
  }

  function vouchers() {
    const speedLabel = (v) => v.speed === "Custom" ? `Custom (${v.download}/${v.upload} Mbps)` : (v.speed || "—");
    return `
      <div class="filter-row section">
        <p class="muted">Codes can later be generated by the controller and redeemed at the Piso WiFi kiosk.</p>
        <div class="actions">
          <button class="btn btn-primary" data-action="generate-vouchers">Generate Vouchers</button>
          <button class="btn btn-ghost" data-action="import-vouchers">Import</button>
          <button class="btn btn-ghost" data-action="export-vouchers">Export</button>
          <button class="btn btn-danger" data-action="delete-vouchers-selected" id="v-bulk-del" disabled>Delete selected</button>
        </div>
      </div>
      <article class="card">
        <div class="card-h">
          <h2>Vouchers</h2>
          <span class="muted sm" id="v-bulk-n"></span>
        </div>
        <div class="table-wrap"><table class="table">
          <thead><tr>
            <th class="check-col"><input type="checkbox" data-action="vouchers-select-all" aria-label="Select all vouchers"></th>
            <th>Code</th><th>Plan</th><th>Duration</th><th>Speed profile</th><th>Created</th><th>Used</th><th>Status</th><th>Actions</th>
          </tr></thead>
          <tbody>${AppData.vouchers.map((v) => `<tr>
            <td class="check-col"><input type="checkbox" class="v-check" data-action="voucher-check" data-id="${escapeHtml(v.code)}" aria-label="Select ${escapeHtml(v.code)}"></td>
            <td class="mono">${escapeHtml(v.code)}</td>
            <td>${escapeHtml(v.plan)}</td>
            <td>${escapeHtml(v.duration)}</td>
            <td>${speedLabel(v)}</td>
            <td>${escapeHtml(v.created)}</td>
            <td>${escapeHtml(v.used)}</td>
            <td>${badge(v.status)}</td>
            <td class="row-actions">
              <button class="linkish" data-action="view-voucher" data-id="${escapeHtml(v.code)}">View</button>
              <button class="linkish danger" data-action="delete-voucher" data-id="${escapeHtml(v.code)}">Delete</button>
            </td>
          </tr>`).join("") || `<tr><td colspan="9">${UI.emptyState("No vouchers", "Generate codes to get started.")}</td></tr>`}</tbody>
        </table></div>
      </article>
    `;
  }

  function network() {
    const n = AppData.networkHealth;
    const m = AppData.mikrotik;
    return `
      <div class="grid grid-2">
        <article class="card">
          <div class="card-h"><h2>Internet Connection</h2>${badge("connected")}</div>
          ${UI.dl([
            ["Internet", badge("connected")],
            ["Connection Type", n.connectionType],
            ["ISP", n.isp],
            ["WAN IP", `<span class="mono">${n.wanIp}</span>`],
            ["Latency", n.latencyMs + " ms"],
            ["Packet Loss", n.packetLoss + "%"],
            ["Uptime", n.uptime],
          ])}
          <p class="muted sm mt-10">PPPoE credentials are not editable here. Status only.</p>
          <div class="mt-10"><button class="btn btn-primary" data-action="test-connection">Test Connection</button></div>
        </article>
        <article class="card">
          <div class="card-h"><h2>MikroTik Information</h2></div>
          <div class="metrics" style="margin:0;padding:0;border:0">
            <div class="metric"><dt>Router</dt><dd>${m.model}</dd></div>
            <div class="metric"><dt>RouterOS</dt><dd>${m.routeros}</dd></div>
            <div class="metric"><dt>CPU</dt><dd>${m.cpu}%</dd></div>
            <div class="metric"><dt>Memory</dt><dd>${m.memory}%</dd></div>
            <div class="metric"><dt>Uptime</dt><dd>${m.uptime}</dd></div>
            <div class="metric"><dt>API</dt><dd>${badge(m.api)}</dd></div>
          </div>
          <div class="mt-14">
            <div class="resource"><div class="resource-top"><span>CPU</span><strong>${m.cpu}%</strong></div>${progressBar(m.cpu)}</div>
            <div class="resource"><div class="resource-top"><span>Memory</span><strong>${m.memory}%</strong></div>${progressBar(m.memory, "teal")}</div>
          </div>
        </article>
      </div>

      <article class="card mt-14">
        <div class="card-h"><h2>Network Interfaces</h2><span class="tech-note">Monitoring only</span></div>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>Interface</th><th>Type</th><th>Status</th><th>Traffic</th></tr></thead>
          <tbody>${AppData.interfaces.map((i) => `<tr>
            <td>${i.name}</td><td>${i.type}</td><td>${badge(i.status)}</td><td>${i.traffic}</td>
          </tr>`).join("")}</tbody>
        </table></div>
      </article>

      <article class="card mt-14">
        <div class="card-h">
          <h2>Network Segments</h2>
          <span class="tech-note">Configured by Technician</span>
        </div>
        <div class="segment-list">
          ${AppData.segments.map((s) => `
            <div class="segment">
              <div>
                <h3>${s.name}</h3>
                <p>${s.vlan} · ${s.cidr}</p>
              </div>
              ${badge(s.status)}
            </div>
          `).join("")}
        </div>
      </article>

      <div class="grid grid-2eq mt-14">
        <article class="card">
          <h2>DHCP Status</h2>
          ${statusRow("DHCP Server", AppData.dhcp.status)}
          <div class="metrics">
            <div class="metric"><dt>Network</dt><dd class="mono">${AppData.dhcp.network}</dd></div>
            <div class="metric"><dt>Active Leases</dt><dd>${AppData.dhcp.activeLeases}</dd></div>
            <div class="metric"><dt>Available Addresses</dt><dd>${AppData.dhcp.available}</dd></div>
          </div>
          <p class="muted sm mt-10">DHCP configuration is not exposed in the owner console.</p>
        </article>
        <article class="card">
          <h2>Active Leases</h2>
          <div class="table-wrap"><table class="table">
            <thead><tr><th>IP</th><th>Device</th><th>MAC</th><th>Lease Status</th><th>Remaining</th></tr></thead>
            <tbody>${AppData.leases.map((l) => `<tr>
              <td class="mono">${l.ip}</td><td>${l.device}</td>
              <td class="mono">${l.mac}</td><td>${badge(l.status)}</td><td>${l.remaining}</td>
            </tr>`).join("")}</tbody>
          </table></div>
        </article>
      </div>
    `;
  }

  function devices(filter) {
    const f = filter || "all";
    const list = AppData.devices.filter((d) => {
      if (f === "all") return true;
      if (f === "online") return d.status === "online";
      if (f === "offline") return d.status === "offline";
      if (f === "blocked") return d.blocked;
      if (f === "authenticated") return d.auth === "authenticated";
      if (f === "unauthenticated") return d.auth === "unauthenticated";
      return true;
    });
    const options = [
      ["all","All"],["online","Online"],["offline","Offline"],
      ["blocked","Blocked"],["authenticated","Authenticated"],["unauthenticated","Unauthenticated"],
    ];
    return `
      <div class="filter-row section">
        <label class="field-label" for="device-filter">Status</label>
        <select id="device-filter" class="filter-select">
          ${options.map(([k,l]) => `<option value="${k}" ${f===k?"selected":""}>${l}</option>`).join("")}
        </select>
      </div>
      <article class="card">
        <div class="table-wrap"><table class="table">
          <thead><tr>
            <th>Device</th><th>IP Address</th><th>MAC Address</th><th>Connection</th>
            <th>Session</th><th>AP</th><th>Usage</th><th>Status</th><th>Action</th>
          </tr></thead>
          <tbody>${list.map((d) => `<tr>
            <td>${d.hostname}</td>
            <td class="mono">${d.ip}</td>
            <td class="mono">${d.mac}</td>
            <td>${d.connection}</td>
            <td>${d.session}</td>
            <td>${d.apId || "—"}</td>
            <td>${d.usage}</td>
            <td>${d.blocked ? badge("blocked") : badge(d.status)}</td>
            <td class="row-actions">
              <button class="linkish" data-action="view-device" data-id="${d.id}">View</button>
              <button class="linkish" data-action="disconnect-device" data-id="${d.id}">Disconnect</button>
              <button class="linkish danger" data-action="block-device" data-id="${d.id}">Block</button>
            </td>
          </tr>`).join("")}</tbody>
        </table></div>
      </article>
    `;
  }

  function bandwidth() {
    return `
      <div class="filter-row section">
        <p class="muted">High-level speed profiles. These will map to preconfigured MikroTik queue profiles later.</p>
        <button class="btn btn-primary" data-action="add-profile">Add Profile</button>
      </div>
      <div class="grid grid-3">
        ${AppData.bandwidthProfiles.map((p) => `
          <article class="card">
            <div class="card-h"><h2>${p.name}</h2>${badge(p.status)}</div>
            <div class="metrics" style="margin:0;padding:0;border:0">
              <div class="metric"><dt>Download</dt><dd>${p.download} Mbps</dd></div>
              <div class="metric"><dt>Upload</dt><dd>${p.upload} Mbps</dd></div>
            </div>
            <div class="row-actions mt-14">
              <button class="btn btn-ghost btn-sm" data-action="edit-profile" data-id="${p.id}">Edit</button>
              <button class="btn btn-ghost btn-sm" data-action="toggle-profile" data-id="${p.id}">${p.status==="active"?"Disable":"Enable"}</button>
              <button class="btn btn-ghost btn-sm" data-action="delete-profile" data-id="${p.id}">Delete</button>
            </div>
          </article>
        `).join("")}
      </div>
      <article class="card mt-14">
        <div class="card-h">
          <h2>Current Traffic</h2>
          <span class="muted sm">Download ${AppData.networkHealth.downloadMbps} Mbps · Upload ${AppData.networkHealth.uploadMbps} Mbps</span>
        </div>
        <canvas class="chart" data-line="traffic"></canvas>
        <div class="legend">
          <span><i style="background:#2563eb"></i>Download</span>
          <span><i style="background:#0ea5e9"></i>Upload</span>
        </div>
      </article>
    `;
  }

  function security() {
    const s = AppData.security;
    return `
      <div class="grid grid-2">
        <article class="card">
          <h2>Security Status</h2>
          <div class="status-list">
            ${statusRow("Firewall", s.firewall)}
            ${statusRow("NAT", s.nat)}
            ${statusRow("Client Isolation", s.clientIsolation)}
            ${statusRow("DNS Protection", s.dnsProtection)}
            ${statusRow("Management Isolation", s.managementIsolation)}
          </div>
        </article>
        <article class="card">
          <div class="card-h">
            <h2>Client Isolation</h2>
            ${toggle("isolation", s.isolationEnabled, "toggle-isolation")}
          </div>
          <p>${badge(s.isolationEnabled ? "enabled" : "disabled")}</p>
          <p class="muted mt-10">Customer devices cannot directly communicate with other customer devices.</p>
        </article>
      </div>
      <article class="card mt-14">
        <h2>Content Filtering</h2>
        <p class="muted sm" style="margin-top:-6px;margin-bottom:8px">Business-friendly controls. Firewall and Layer 7 rules are not exposed.</p>
        ${AppData.contentFiltering.map((c) => `
          <div class="setting-row">
            <div>
              <strong>${c.label}</strong>
              <div class="muted sm">${c.enabled ? "ON" : "OFF"}</div>
            </div>
            ${toggle(c.id, c.enabled, "toggle-filter")}
          </div>
        `).join("")}
      </article>
      <article class="card mt-14">
        <div class="card-h">
          <h2>Blocked Devices</h2>
          <button class="btn btn-primary btn-sm" data-action="block-device-new">Block Device</button>
        </div>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>Device</th><th>MAC</th><th>Date Blocked</th><th>Reason</th><th>Status</th><th></th></tr></thead>
          <tbody>${AppData.blockedDevices.map((b) => `<tr>
            <td>${b.device}<div class="muted sm">${b.hostname}</div></td>
            <td class="mono">${b.mac}</td>
            <td>${b.date}</td>
            <td>${b.reason}</td>
            <td>${badge(b.status)}</td>
            <td><button class="linkish" data-action="unblock-device" data-id="${b.id}">Unblock</button></td>
          </tr>`).join("")}</tbody>
        </table></div>
      </article>
    `;
  }

  function settings() {
    const st = AppData.settings;
    return `
      <div class="grid grid-2eq">
        <article class="card">
          <h2>General</h2>
          <div class="field"><label>System name</label><input id="set-name" value="${st.systemName}"></div>
          <div class="field mt-10"><label>Location name</label><input id="set-loc" value="${st.locationName}"></div>
          <div class="field mt-10"><label>Time zone</label>
            <select id="set-tz"><option selected>${st.timezone}</option><option>UTC</option></select>
          </div>
          <div class="field mt-10"><label>Language</label>
            <select id="set-lang"><option selected>English</option><option>Filipino</option></select>
          </div>
          <div class="field mt-10"><label>Currency</label>
            <select id="set-cur"><option selected>PHP (₱)</option></select>
          </div>
        </article>
        <article class="card">
          <h2>Admin Account</h2>
          <div class="field"><label>Name</label><input id="set-admin" value="${st.adminName}"></div>
          <div class="field mt-10"><label>Username</label><input id="set-user" value="${st.adminUsername}"></div>
          <div class="field mt-10"><label>Password</label><input type="password" value="••••••••"></div>
          <div class="field mt-10"><label>Session timeout</label>
            <select id="set-timeout">
              <option ${st.sessionTimeout==="15 minutes"?"selected":""}>15 minutes</option>
              <option ${st.sessionTimeout==="30 minutes"?"selected":""}>30 minutes</option>
              <option ${st.sessionTimeout==="1 hour"?"selected":""}>1 hour</option>
            </select>
          </div>
        </article>
      </div>
      <div class="grid grid-2eq mt-14">
        <article class="card">
          <h2>Display</h2>
          <div class="field"><label>Theme</label>
            <select id="set-theme">
              <option value="light" ${st.theme==="light"?"selected":""}>Light</option>
              <option value="dark" ${st.theme==="dark"?"selected":""}>Dark</option>
            </select>
          </div>
          <div class="setting-row mt-10">
            <div><strong>Compact mode</strong><div class="muted sm">Denser tables and cards</div></div>
            ${toggle("compact", st.compactMode, "toggle-compact")}
          </div>
          <div class="field mt-10"><label>Dashboard refresh interval</label>
            <select id="set-refresh">
              <option>5 seconds</option>
              <option selected>15 seconds</option>
              <option>30 seconds</option>
              <option>1 minute</option>
            </select>
          </div>
        </article>
        <article class="card">
          <h2>Notifications</h2>
          ${Object.entries({
            internetOffline: "Internet offline",
            mikrotikOffline: "MikroTik offline",
            controllerOffline: "Controller offline",
            apOffline: "AP offline",
            lowStorage: "Low storage",
            otaAvailable: "OTA update available",
          }).map(([k,l]) => `
            <div class="setting-row">
              <span>${l}</span>
              ${toggle(k, st.notifications[k], "toggle-notif")}
            </div>
          `).join("")}
        </article>
      </div>
      <article class="card mt-14">
        <h2>Branding</h2>
        <p class="muted sm">Logos appear on the sign-in screen and in the sidebar. Maximum file size is 3 MB. PNG, JPG, or WEBP.</p>
        <div class="branding-grid mt-14">
          <div class="logo-upload">
            <div class="logo-upload-head">
              <strong>Login page logo</strong>
              <span class="muted sm">Shown above the sign-in form</span>
            </div>
            <div class="logo-preview login-preview">
              <img id="login-logo-preview" src="${escapeHtml((window.KskBrand && (KskBrand.getLoginLogo() || KskBrand.DEFAULT_LOGIN)) || "public/Logo.png")}" alt="Login logo preview">
            </div>
            <div class="upload-note">Remove the background first. Use a transparent PNG so the logo sits cleanly on the login screen. Maximum size is 3 MB.</div>
            <div class="row-actions mt-14">
              <button type="button" class="btn btn-primary btn-sm" data-action="pick-login-logo">Upload login logo</button>
              <button type="button" class="btn btn-ghost btn-sm" data-action="clear-login-logo">Reset to default</button>
            </div>
            <input id="login-logo-file" type="file" accept="image/png,image/jpeg,image/webp" hidden>
          </div>
          <div class="logo-upload">
            <div class="logo-upload-head">
              <strong>Navbar logo</strong>
              <span class="muted sm">Shown in the sidebar next to KonekSik-fi</span>
            </div>
            <div class="logo-preview nav-preview">
              <img id="nav-logo-preview" src="${escapeHtml((window.KskBrand && (KskBrand.getNavLogo() || KskBrand.DEFAULT_NAV)) || "public/navbar.png")}" alt="Navbar logo preview">
            </div>
            <div class="upload-note">Remove the background first. A square transparent PNG works best in the navbar. Maximum size is 3 MB.</div>
            <div class="row-actions mt-14">
              <button type="button" class="btn btn-primary btn-sm" data-action="pick-nav-logo">Upload navbar logo</button>
              <button type="button" class="btn btn-ghost btn-sm" data-action="clear-nav-logo">Reset to default</button>
            </div>
            <input id="nav-logo-file" type="file" accept="image/png,image/jpeg,image/webp" hidden>
          </div>
        </div>
      </article>
      <div class="mt-14"><button class="btn btn-primary" data-action="save-settings">Save Settings</button></div>
    `;
  }

  function remoteAccess() {
    const r = AppData.remoteAccess;
    return `
      <article class="card" style="max-width:640px">
        <div class="card-h"><h2>Remote Access</h2>${badge(r.status)}</div>
        ${UI.dl([
          ["Status", badge(r.status)],
          ["Connection", r.connection],
          ["Last Connected", r.lastConnected],
          ["Device ID", `<span class="mono">${r.deviceId}</span>`],
          ["Remote Support", r.remoteSupport ? badge("enabled") : badge("disabled")],
        ])}
        <p class="muted sm mt-10">VPN technical configuration is not shown in the owner console.</p>
        <div class="actions mt-14">
          <button class="btn btn-primary" data-action="enable-remote">Enable Remote Access</button>
          <button class="btn btn-ghost" data-action="disable-remote">Disable Remote Access</button>
          <button class="btn btn-ghost" data-action="test-remote">Test Connection</button>
        </div>
      </article>
    `;
  }

  function subVendo() {
    const mt = AppData.mikrotik;
    return `
      <div class="filter-row section">
        <p class="muted">Each Sub Vendo is an ESP32 that joins the Access Point over Wi-Fi (station mode). MikroTik CAPsMAN is what binds that ESP32 to the AP — the ESP32 does not configure the AP.</p>
        <button class="btn btn-primary" data-action="add-vendo">Add Sub Vendo</button>
      </div>
      <article class="card">
        <div class="card-h"><h2>Bind path</h2>${badge(mt.connection)}</div>
        <div class="bind-path">
          <span>ESP32 Wi-Fi STA</span>
          <em>→</em>
          <span>Access Point (CAP)</span>
          <em>→</em>
          <span>MikroTik ${UI.escapeHtml(mt.model)}</span>
          <em>→</em>
          <span>CAPsMAN bind</span>
        </div>
        <p class="muted sm mt-10">Wireless hop is ESP32 → AP. Control/bind is AP → hEX. KonekSik-fi only reads that from MikroTik.</p>
      </article>
      <div class="vendo-grid mt-14">
        ${AppData.subVendos.map((v) => {
          const ap = AppData.accessPoints.find((a) => a.id === v.apId);
          const bound = v.mikrotikBound && ap;
          return `
          <article class="card">
            <div class="card-h">
              <h2>${UI.escapeHtml(v.name)}</h2>
              ${badge(v.status)}
            </div>
            <p class="muted sm">ESP32 · ${UI.escapeHtml(v.deviceId || v.id)}</p>
            <p class="sm mt-10">${bound
              ? `Wi-Fi on ${UI.escapeHtml(ap.identity)} · bound via MikroTik`
              : "Not bound to an access point"}</p>
            <p class="muted sm">${UI.escapeHtml(v.location)}</p>
            <div class="stat-mini">
              <div><span>Users</span><strong>${v.users || 0}</strong></div>
              <div><span>Waiting</span><strong>${v.waiting || 0}</strong></div>
              <div><span>Sessions</span><strong>${v.sessions || 0}</strong></div>
              <div><span>Sales</span><strong>${peso(v.sales || 0)}</strong></div>
            </div>
            <div class="row-actions mt-14">
              <button class="btn btn-ghost btn-sm" data-action="view-vendo" data-id="${v.id}">View</button>
              <button class="btn btn-primary btn-sm" data-action="bind-vendo" data-id="${v.id}">${bound ? "Change AP" : "Bind AP"}</button>
              <button class="btn btn-ghost btn-sm" data-action="rename-vendo" data-id="${v.id}">Rename</button>
              <button class="btn btn-ghost btn-sm" data-action="disable-vendo" data-id="${v.id}">${v.status === "disabled" ? "Enable" : "Disable"}</button>
            </div>
          </article>`;
        }).join("")}
      </div>
    `;
  }

  function ota() {
    const o = AppData.ota;
    return `
      <div class="grid grid-2">
        <article class="card">
          <h2>System Update</h2>
          ${UI.dl([
            ["Current Version", o.current],
            ["Latest Version", o.latest],
            ["Status", badge("warning", "Update Available")],
          ])}
          <div class="mt-14"><button class="btn btn-primary" data-action="ota-update">Update Now</button></div>
          <div id="ota-progress" class="mt-14" hidden>
            <p id="ota-stage" class="muted">Preparing…</p>
            <div class="progress-line"><span id="ota-bar"></span></div>
          </div>
        </article>
        <article class="card">
          <h2>Version ${o.notes.version}</h2>
          <div class="ota-box">
            <strong>Improvements</strong>
            <ul>${o.notes.improvements.map((i) => `<li>${i}</li>`).join("")}</ul>
            <strong>Bug Fixes</strong>
            <ul>${o.notes.fixes.map((i) => `<li>${i}</li>`).join("")}</ul>
          </div>
        </article>
      </div>
    `;
  }

  function radioCard(r) {
    return `<article class="card">
      <div class="card-h"><h2>${r.band}</h2>${badge(r.status)}</div>
      ${UI.dl([
        ["Channel", r.channel],
        ["Channel Width", r.width],
        ["Clients", String(r.clients)],
        ["Transmit Power", r.txPower],
        ["Mode", r.mode],
      ])}
    </article>`;
  }

  function accessPoints(opts = {}) {
    if (opts.apId) {
      const ap = AppData.accessPoints.find((a) => a.id === opts.apId);
      return ap ? accessPointDetail(ap, opts) : `<article class="card">${UI.emptyState("Access point not found", "Return to the AP list.")}<button class="btn btn-ghost mt-10" data-action="ap-back">Back</button></article>`;
    }
    if (AppData.apApiError) {
      return `<article class="card" style="text-align:center;padding:40px">
        <h2>Unable to Retrieve Access Point Data</h2>
        <p class="muted mt-10">The KonekSik-fi controller could not retrieve AP information.</p>
        <button class="btn btn-primary mt-14" data-action="ap-retry">Retry</button>
      </article>`;
    }
    if (opts.loading) {
      return `<div class="grid grid-4">${[1,2,3,4].map(() => `<article class="card"><div class="skeleton sk-card"></div></article>`).join("")}</div>
        <article class="card mt-14"><div class="skeleton" style="height:180px"></div></article>`;
    }
    const q = (opts.query || "").toLowerCase();
    const filter = opts.filter || "all";
    const view = opts.view || "list";
    let list = AppData.accessPoints.filter((ap) => {
      if (filter === "online") return ap.status === "online";
      if (filter === "offline") return ap.status === "offline";
      if (filter === "warning") return ap.status === "warning";
      if (filter === "radio24") return ap.radios.some((r) => r.band.startsWith("2.4") && r.status === "active");
      if (filter === "radio5") return ap.radios.some((r) => r.band.startsWith("5") && r.status === "active");
      if (filter === "high-clients") return (ap.radios[0].clients + ap.radios[1].clients) >= 15;
      if (filter === "high-cpu") return ap.cpu >= 70;
      return true;
    });
    if (q) {
      list = list.filter((ap) => [ap.identity, ap.model, ap.ip, ap.baseMac, ap.serial].join(" ").toLowerCase().includes(q));
    }
    const online = AppData.accessPoints.filter((a) => a.status === "online").length;
    const offline = AppData.accessPoints.filter((a) => a.status === "offline").length;
    const clients = AppData.accessPoints.reduce((n, a) => n + a.radios.reduce((s, r) => s + (r.clients || 0), 0), 0);
    const chips = [
      ["all", "All"], ["online", "Online"], ["offline", "Offline"], ["warning", "Warning"],
      ["radio24", "2.4 GHz Active"], ["radio5", "5 GHz Active"], ["high-clients", "High Client Count"], ["high-cpu", "High CPU"],
    ];
    if (!AppData.accessPoints.length) {
      return `<article class="card" style="text-align:center;padding:40px">
        <h2>No Access Points Found</h2>
        <p class="muted mt-10">No MikroTik access points are currently registered with KonekSik-fi.</p>
        <button class="btn btn-primary mt-14" data-action="ap-refresh">Refresh</button>
      </article>`;
    }
    const table = `<article class="card">
      <div class="table-wrap"><table class="table">
        <thead><tr>
          <th>Status</th><th>Access Point</th><th>Model</th><th>IP Address</th>
          <th>Clients</th><th>2.4 GHz</th><th>5 GHz</th><th>Uptime</th><th>RouterOS</th><th>Actions</th>
        </tr></thead>
        <tbody>${list.map((ap) => {
          const r24 = ap.radios.find((r) => r.band.startsWith("2.4"));
          const r5 = ap.radios.find((r) => r.band.startsWith("5"));
          const total = (r24?.clients || 0) + (r5?.clients || 0);
          return `<tr class="row-select" data-action="view-ap" data-id="${ap.id}" tabindex="0">
            <td>${badge(ap.status)}</td>
            <td><strong>${ap.identity}</strong></td>
            <td>${ap.boardName}</td>
            <td class="mono">${ap.ip}</td>
            <td>${ap.status === "offline" ? "0" : total + " Clients"}</td>
            <td>${ap.status === "offline" ? "—" : (r24?.clients ?? "—")}</td>
            <td>${ap.status === "offline" ? `<span class="muted sm">Last seen ${ap.lastSeen}</span>` : (r5?.clients ?? "—")}</td>
            <td>${ap.uptime}</td>
            <td>${ap.routeros}</td>
            <td><button type="button" class="linkish" data-action="view-ap" data-id="${ap.id}">View</button></td>
          </tr>`;
        }).join("") || `<tr><td colspan="10">${UI.emptyState("No matching APs", "Try another filter or search.")}</td></tr>`}</tbody>
      </table></div>
    </article>`;
    const cards = `<div class="ap-grid">${list.map((ap) => {
      const r24 = ap.radios.find((r) => r.band.startsWith("2.4"));
      const r5 = ap.radios.find((r) => r.band.startsWith("5"));
      const total = (r24?.clients || 0) + (r5?.clients || 0);
      return `<article class="card ap-card row-select" data-action="view-ap" data-id="${ap.id}" tabindex="0">
        ${badge(ap.status)}
        <div class="ap-name">${ap.identity}</div>
        <p class="muted sm">${ap.model}</p>
        <p style="font-weight:700;margin-top:10px">${ap.status === "offline" ? "0 Clients" : total + " Clients"}</p>
        <div class="ap-meta">
          <div><span>2.4 GHz</span><strong>${ap.status === "offline" ? "—" : (r24?.clients || 0) + " clients"}</strong></div>
          <div><span>5 GHz</span><strong>${ap.status === "offline" ? "—" : (r5?.clients || 0) + " clients"}</strong></div>
          <div><span>Uptime</span><strong>${ap.uptime}</strong></div>
          <div><span>IP</span><strong class="mono">${ap.ip}</strong></div>
          <div><span>RouterOS</span><strong>${ap.routeros}</strong></div>
        </div>
        ${ap.status === "offline" ? `<p class="muted sm mt-10">Last seen ${ap.lastSeen}</p>` : ""}
        <div class="mt-14"><button type="button" class="btn btn-ghost btn-sm" data-action="view-ap" data-id="${ap.id}">View Details</button></div>
      </article>`;
    }).join("")}</div>`;
    return `
      <div class="grid grid-4">
        ${kpi(AppData.accessPoints.length, "Total Access Points")}
        ${kpi(online, "Online")}
        ${kpi(offline, "Offline")}
        ${kpi(clients, "Wireless Clients")}
      </div>
      <div class="ap-toolbar mt-14">
        <div class="filter-bar" style="margin:0">
          ${chips.map(([k, l]) => `<button class="chip ${filter===k?"active":""}" data-action="filter-ap" data-filter="${k}">${l}</button>`).join("")}
        </div>
        <div class="actions">
          <input class="search" id="ap-search" data-action="search-ap" placeholder="Search name, IP, MAC, model…" value="${UI.escapeHtml(opts.query || "")}">
          <div class="view-toggle">
            <button class="btn btn-sm ${view==="list"?"btn-primary":"btn-ghost"}" data-action="ap-view" data-view="list">List</button>
            <button class="btn btn-sm ${view==="cards"?"btn-primary":"btn-ghost"}" data-action="ap-view" data-view="cards">Cards</button>
          </div>
          <span class="muted sm">Last updated <span id="ap-updated">${AppData.apLastUpdated}</span></span>
          <button class="btn btn-ghost btn-sm" data-action="ap-refresh">Refresh</button>
        </div>
      </div>
      ${view === "cards" ? cards : table}
      <article class="card mt-14">
        <h2>Recent AP Events</h2>
        <div class="timeline">
          ${AppData.apEvents.map((e) => `<div class="tl-item">
            <strong>${e.time}</strong>
            <span class="tl-dot"></span>
            <div><strong>${e.title}</strong><p>${e.detail}</p></div>
          </div>`).join("")}
        </div>
      </article>
    `;
  }

  function accessPointDetail(ap) {
    const r24 = ap.radios.find((r) => r.band.startsWith("2.4"));
    const r5 = ap.radios.find((r) => r.band.startsWith("5"));
    const healthRows = [
      ["CAPsMAN Connection", ap.health.capsmam],
      ["Ethernet Link", ap.health.ethernet],
      ["2.4 GHz Radio", ap.health.radio24],
      ["5 GHz Radio", ap.health.radio5],
      ["Wireless Clients", ap.health.clients],
      ["CPU", ap.health.cpu],
      ["Memory", ap.health.memory],
      ["Temperature", ap.health.temperature],
    ];
    return `
      <div class="filter-row section">
        <div>
          <button class="linkish" data-action="ap-back">← Access Points</button>
          <h2 style="font-size:20px;margin-top:6px">${ap.identity}</h2>
          <p class="muted">${ap.model} · <span class="mono">${ap.ip}</span></p>
        </div>
        <div class="actions">
          ${badge(ap.status)}
          <button class="btn btn-ghost" data-action="ap-refresh">Refresh</button>
          <button class="btn btn-ghost" data-action="restart-ap" data-id="${ap.id}">Restart AP</button>
        </div>
      </div>
      ${ap.status === "offline" ? `<div class="warn-banner">
        <strong>Access Point Offline</strong>
        <p>${ap.identity} · ${ap.model}</p>
        <p class="sm mt-10">Last seen ${ap.lastSeen} · Last known IP ${ap.ip} · CAPsMAN ${ap.capsmamStatus}</p>
        <div class="actions mt-10">
          <button class="btn btn-ghost btn-sm" data-action="ap-refresh">Refresh Status</button>
          <button class="btn btn-ghost btn-sm" data-action="ap-diagnostics" data-id="${ap.id}">View Diagnostics</button>
        </div>
      </div>` : ""}
      <div class="grid grid-2">
        <article class="card">
          <h2>Hardware</h2>
          ${UI.dl([
            ["Model", ap.model],
            ["Board", ap.boardName],
            ["Serial Number", `<span class="mono">${ap.serial}</span>`],
            ["Base MAC", `<span class="mono">${ap.baseMac}</span>`],
            ["RouterOS", ap.routeros],
            ["Uptime", ap.uptime],
            ["IP Address", `<span class="mono">${ap.ip}</span>`],
            ["CAPsMAN", badge(ap.capsmamStatus)],
          ])}
        </article>
        <article class="card">
          <h2>System Resources</h2>
          ${ap.status === "offline" ? `<p class="muted">Not Available while the AP is offline.</p>` : `
            <div class="resource"><div class="resource-top"><span>CPU</span><strong>${ap.cpu}%</strong></div>${progressBar(ap.cpu)}</div>
            <div class="resource"><div class="resource-top"><span>Memory</span><strong>${ap.memory}%</strong></div>${progressBar(ap.memory, "teal")}</div>
            <div class="resource"><div class="resource-top"><span>Storage</span><strong>${ap.storage}%</strong></div>${progressBar(ap.storage, "amber")}</div>
            <div class="resource-top mt-10"><span>Temperature</span><strong>${ap.temperature == null ? "Not Available" : ap.temperature + "°C"}</strong></div>
          `}
        </article>
      </div>
      <div class="grid grid-2eq mt-14">
        <article class="card">
          <h2>CAPsMAN Connection</h2>
          ${ap.capsmamStatus === "connected" ? UI.dl([
            ["Status", badge("connected")],
            ["CAPsMAN Address", `<span class="mono">${ap.capsmamAddress}</span>`],
            ["Connected Since", ap.connectedSince],
            ["Connection Uptime", ap.uptime],
          ]) : UI.dl([
            ["Status", badge("disconnected")],
            ["Last Seen", ap.lastSeen],
            ["Reason", ap.offlineReason || "Connection Lost"],
          ])}
        </article>
        <article class="card">
          <h2>Traffic</h2>
          <p class="muted sm">From the network path through the hEX — not full CAPsMAN client accounting.</p>
          <div class="metrics">
            <div class="metric"><dt>Download</dt><dd>${ap.traffic.download} Mbps</dd></div>
            <div class="metric"><dt>Upload</dt><dd>${ap.traffic.upload} Mbps</dd></div>
          </div>
        </article>
      </div>
      <h2 class="mt-14" style="margin-bottom:10px">Wireless Radios</h2>
      <div class="radio-grid">
        ${radioCard(r24)}
        ${radioCard(r5)}
      </div>
      <article class="card mt-14">
        <h2>AP Health</h2>
        <div class="health-grid">
          ${healthRows.map(([l, s]) => `<div class="health-row"><span>${l}</span>${badge(s)}</div>`).join("")}
        </div>
      </article>
      <article class="card mt-14">
        <div class="card-h"><h2>Connected Wireless Clients</h2></div>
        <div class="table-wrap"><table class="table">
          <thead><tr><th>Device</th><th>IP Address</th><th>MAC Address</th><th>Radio</th><th>Signal</th><th>Uptime</th><th>Status</th></tr></thead>
          <tbody>${ap.clients.length ? ap.clients.map((c) => `<tr data-action="view-ap-client" data-id="${c.id}" data-ap="${ap.id}" style="cursor:pointer">
            <td>${c.device}</td>
            <td class="mono">${c.ip}</td>
            <td class="mono">${c.mac}</td>
            <td>${c.radio}</td>
            <td>${c.signal}</td>
            <td>${c.uptime}</td>
            <td>${badge(c.status)}</td>
          </tr>`).join("") : `<tr><td colspan="7">${UI.emptyState("No wireless clients", "No stations are associated with this AP.")}</td></tr>`}</tbody>
        </table></div>
      </article>
      <article class="card mt-14">
        <div class="card-h">
          <h2>Diagnostics</h2>
          <button class="btn btn-ghost btn-sm" data-action="ap-diagnostics" data-id="${ap.id}">Run Diagnostics</button>
        </div>
        ${Object.entries({ capsmam: "CAPsMAN Connection", ip: "IP Connectivity", ethernet: "Ethernet Link", radio24: "2.4 GHz Radio", radio5: "5 GHz Radio" }).map(([k, l]) => `
          <div class="health-row"><span>${l}</span>${badge(ap.diagnostics[k])}</div>
        `).join("")}
        <p class="muted sm mt-10">Owner diagnostics only. RouterOS commands are not shown.</p>
      </article>
    `;
  }

  return {
    meta,
    dashboard,
    sales,
    "coin-rates": coinRates,
    plans,
    sessions,
    vouchers,
    network,
    "access-points": accessPoints,
    devices,
    bandwidth,
    security,
    settings,
    "remote-access": remoteAccess,
    "sub-vendo": subVendo,
    ota,
  };
})();
