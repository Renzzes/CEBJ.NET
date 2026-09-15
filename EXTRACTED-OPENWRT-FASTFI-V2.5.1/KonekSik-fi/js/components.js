/**
 * KonekSik-fi Admin Console — reusable UI primitives
 */
(function (global) {
  const root = () => document.getElementById("ui-root");

  function el(html) {
    const t = document.createElement("template");
    t.innerHTML = html.trim();
    return t.content.firstElementChild;
  }

  const Icons = {
    check: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12l5 5L20 7"/></svg>`,
    x: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 6l12 12M18 6L6 18"/></svg>`,
    bell: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M6 8a6 6 0 1 1 12 0c0 7 3 8 3 8H3s3-1 3-8"/><path d="M10 19a2 2 0 0 0 4 0"/></svg>`,
    menu: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M4 12h16M4 17h16"/></svg>`,
    search: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3-3"/></svg>`,
  };

  function badge(status, label) {
    const map = {
      online: "success",
      connected: "success",
      active: "success",
      healthy: "success",
      successful: "success",
      completed: "success",
      available: "success",
      running: "success",
      enabled: "success",
      passed: "success",
      normal: "success",
      authenticated: "success",
      warning: "warning",
      updating: "warning",
      pending: "warning",
      limited: "warning",
      unauthenticated: "warning",
      offline: "danger",
      failed: "danger",
      blocked: "danger",
      critical: "danger",
      expired: "danger",
      disconnected: "danger",
      disabled: "neutral",
      inactive: "neutral",
      unknown: "neutral",
      used: "neutral",
      "not available": "neutral",
    };
    const kind = map[String(status).toLowerCase()] || "neutral";
    const text = label || titleCase(status);
    return `<span class="badge badge-${kind}"><span class="dot"></span>${escapeHtml(text)}</span>`;
  }

  function statusRow(label, status, extra) {
    return `<div class="status-row">
      <span class="muted">${escapeHtml(label)}</span>
      <span>${badge(status)}${extra ? `<span class="muted sm">${escapeHtml(extra)}</span>` : ""}</span>
    </div>`;
  }

  function progressBar(value, tone) {
    const v = Math.max(0, Math.min(100, Number(value) || 0));
    return `<div class="bar"><span class="bar-fill tone-${tone || "blue"}" style="width:${v}%"></span></div>`;
  }

  function toggle(id, checked, action) {
    return `<button type="button" class="switch ${checked ? "on" : ""}" role="switch" aria-checked="${checked}" data-action="${action || "toggle"}" data-id="${id}"></button>`;
  }

  function kpi(value, label, hint) {
    return `<article class="card kpi-card">
      <div class="kpi-value">${value}</div>
      <div class="kpi-label">${escapeHtml(label)}</div>
      ${hint ? `<div class="kpi-hint">${hint}</div>` : ""}
    </article>`;
  }

  function emptyState(title, body) {
    return `<div class="empty">
      <div class="empty-icon">∅</div>
      <h3>${escapeHtml(title)}</h3>
      <p>${escapeHtml(body || "")}</p>
    </div>`;
  }

  function table(headers, rowsHtml, opts = {}) {
    return `<div class="table-wrap">
      <table class="table">
        <thead><tr>${headers.map((h) => `<th>${h}</th>`).join("")}</tr></thead>
        <tbody>${rowsHtml || `<tr><td colspan="${headers.length}">${emptyState("No records", "Nothing to show yet.").replace("empty", "empty compact")}</td></tr>`}</tbody>
      </table>
    </div>`;
  }

  function toast(message, type = "info") {
    let host = document.querySelector(".toasts");
    if (!host) {
      host = el(`<div class="toasts"></div>`);
      document.body.appendChild(host);
    }
    const t = el(`<div class="toast toast-${type}">
      <span class="toast-dot"></span>
      <span>${escapeHtml(message)}</span>
    </div>`);
    host.appendChild(t);
    requestAnimationFrame(() => t.classList.add("show"));
    setTimeout(() => {
      t.classList.remove("show");
      setTimeout(() => t.remove(), 280);
    }, 2800);
  }

  function modal({ title, body, actions, width }) {
    closeModal();
    const overlay = el(`<div class="modal-overlay" role="presentation">
      <div class="modal" style="${width ? `max-width:${width}` : ""}" role="dialog" aria-modal="true">
        <div class="modal-head">
          <h3>${escapeHtml(title)}</h3>
          <button type="button" class="icon-btn" data-action="close-modal" aria-label="Close">${Icons.x}</button>
        </div>
        <div class="modal-body">${body}</div>
        ${actions ? `<div class="modal-foot">${actions}</div>` : ""}
      </div>
    </div>`);
    overlay.addEventListener("click", (e) => {
      if (e.target === overlay) {
        e.preventDefault();
        closeModal();
      }
    });
    overlay.querySelectorAll("[data-action='close-modal']").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        closeModal();
      });
    });
    document.body.appendChild(overlay);
    requestAnimationFrame(() => overlay.classList.add("show"));
    enhanceSelects(overlay);
    return overlay;
  }

  function closeModal() {
    closeSelectMenus();
    document.querySelectorAll(".modal-overlay").forEach((n) => {
      n.classList.remove("show");
      n.style.pointerEvents = "none";
      setTimeout(() => n.remove(), 200);
    });
  }

  function confirmDialog({ title, message, confirmText = "Confirm", danger = false, onConfirm }) {
    modal({
      title,
      body: `<p class="confirm-copy">${message}</p>`,
      actions: `
        <button type="button" class="btn btn-ghost" data-action="close-modal">Cancel</button>
        <button class="btn ${danger ? "btn-danger" : "btn-primary"}" id="confirm-ok">${escapeHtml(confirmText)}</button>
      `,
      width: "420px",
    });
    document.getElementById("confirm-ok").onclick = () => {
      closeModal();
      if (onConfirm) onConfirm();
    };
  }

  function drawer({ title, body, actions }) {
    closeDrawer();
    const overlay = el(`<div class="drawer-overlay"></div>`);
    const panel = el(`<aside class="drawer" role="dialog" aria-modal="true">
      <div class="drawer-head">
        <h3>${escapeHtml(title)}</h3>
        <button type="button" class="icon-btn" data-action="close-drawer" aria-label="Close">${Icons.x}</button>
      </div>
      <div class="drawer-body">${body}</div>
      ${actions ? `<div class="drawer-foot">${actions}</div>` : ""}
    </aside>`);
    overlay.addEventListener("click", (e) => {
      e.preventDefault();
      closeDrawer();
    });
    panel.querySelectorAll("[data-action='close-drawer']").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        closeDrawer();
      });
    });
    document.body.appendChild(overlay);
    document.body.appendChild(panel);
    requestAnimationFrame(() => {
      overlay.classList.add("show");
      panel.classList.add("show");
    });
  }

  function closeDrawer() {
    document.querySelectorAll(".drawer").forEach((n) => {
      n.classList.remove("show");
      n.style.pointerEvents = "none";
      setTimeout(() => n.remove(), 250);
    });
    document.querySelectorAll(".drawer-overlay").forEach((n) => {
      n.classList.remove("show");
      n.style.pointerEvents = "none";
      setTimeout(() => n.remove(), 250);
    });
  }

  function dl(pairs) {
    return `<dl class="kv">${pairs
      .map(
        ([k, v]) =>
          `<div><dt>${escapeHtml(k)}</dt><dd>${typeof v === "string" ? v : v}</dd></div>`
      )
      .join("")}</dl>`;
  }

  function peso(n) {
    return "₱" + Number(n).toLocaleString("en-PH");
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function titleCase(s) {
    return String(s).replace(/[-_]/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  }

  function drawSparkline(canvas, data, color) {
    if (!canvas || !data || !data.length) return;
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth || 160;
    const h = canvas.clientHeight || 40;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    const ctx = canvas.getContext("2d");
    ctx.scale(dpr, dpr);
    const min = Math.min(...data);
    const max = Math.max(...data);
    const span = max - min || 1;
    ctx.beginPath();
    data.forEach((v, i) => {
      const x = (i / (data.length - 1)) * (w - 2) + 1;
      const y = h - ((v - min) / span) * (h - 6) - 3;
      i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    });
    ctx.strokeStyle = color || "#2563eb";
    ctx.lineWidth = 1.6;
    ctx.stroke();
    ctx.lineTo(w - 1, h);
    ctx.lineTo(1, h);
    ctx.closePath();
    ctx.fillStyle = (color || "#2563eb") + "18";
    ctx.fill();
  }

  function drawLineChart(canvas, series) {
    if (!canvas) return;
    const dpr = window.devicePixelRatio || 1;
    const w = canvas.clientWidth || 420;
    const h = canvas.clientHeight || 160;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    const ctx = canvas.getContext("2d");
    ctx.scale(dpr, dpr);
    const pad = { l: 36, r: 10, t: 10, b: 22 };
    const all = series.flatMap((s) => s.data);
    const min = 0;
    const max = Math.max(...all) * 1.15 || 1;
    ctx.strokeStyle = "rgba(148,163,184,0.35)";
    ctx.lineWidth = 1;
    for (let i = 0; i <= 3; i++) {
      const y = pad.t + ((h - pad.t - pad.b) * i) / 3;
      ctx.beginPath();
      ctx.moveTo(pad.l, y);
      ctx.lineTo(w - pad.r, y);
      ctx.stroke();
      ctx.fillStyle = "#94a3b8";
      ctx.font = "10px Segoe UI, sans-serif";
      const val = Math.round(max - (max * i) / 3);
      ctx.fillText(String(val), 4, y + 3);
    }
    series.forEach((s) => {
      ctx.beginPath();
      s.data.forEach((v, i) => {
        const x = pad.l + (i / (s.data.length - 1)) * (w - pad.l - pad.r);
        const y = pad.t + (1 - v / max) * (h - pad.t - pad.b);
        i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      });
      ctx.strokeStyle = s.color;
      ctx.lineWidth = 1.8;
      ctx.stroke();
    });
  }

  function closeSelectMenus() {
    document.querySelectorAll(".c-select-menu").forEach((n) => n.remove());
    document.querySelectorAll(".c-select.open").forEach((n) => n.classList.remove("open"));
    document.querySelectorAll(".c-select-btn[aria-expanded='true']").forEach((b) => {
      b.setAttribute("aria-expanded", "false");
    });
  }

  function positionSelectMenu(btn, menu) {
    const r = btn.getBoundingClientRect();
    const maxH = 260;
    menu.style.minWidth = Math.max(r.width, 180) + "px";
    menu.style.width = Math.max(r.width, 180) + "px";
    menu.style.left = Math.min(r.left, window.innerWidth - r.width - 8) + "px";
    const below = window.innerHeight - r.bottom;
    if (below < maxH && r.top > below) {
      menu.style.top = "auto";
      menu.style.bottom = (window.innerHeight - r.top + 6) + "px";
      menu.style.maxHeight = Math.min(maxH, r.top - 12) + "px";
    } else {
      menu.style.bottom = "auto";
      menu.style.top = (r.bottom + 6) + "px";
      menu.style.maxHeight = Math.min(maxH, below - 12) + "px";
    }
  }

  function openSelectMenu(sel, wrap, btn) {
    closeSelectMenus();
    wrap.classList.add("open");
    btn.setAttribute("aria-expanded", "true");
    const menu = document.createElement("div");
    menu.className = "c-select-menu";
    menu.setAttribute("role", "listbox");
    [...sel.options].forEach((opt, i) => {
      const item = document.createElement("button");
      item.type = "button";
      item.className = "c-select-opt" + (opt.selected ? " selected" : "");
      item.setAttribute("role", "option");
      item.setAttribute("aria-selected", opt.selected ? "true" : "false");
      item.disabled = opt.disabled;
      item.textContent = opt.textContent;
      item.addEventListener("mousedown", (e) => e.preventDefault());
      item.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (opt.disabled) return;
        sel.selectedIndex = i;
        sel.dispatchEvent(new Event("change", { bubbles: true }));
        closeSelectMenus();
      });
      menu.appendChild(item);
    });
    document.body.appendChild(menu);
    positionSelectMenu(btn, menu);
    const selected = menu.querySelector(".c-select-opt.selected");
    if (selected) selected.scrollIntoView({ block: "nearest" });
  }

  function enhanceSelects(scope) {
    const root = scope || document;
    root.querySelectorAll("select").forEach((sel) => {
      if (sel.dataset.enhanced === "1") return;
      sel.dataset.enhanced = "1";
      const wrap = document.createElement("div");
      wrap.className = "c-select" + (sel.classList.contains("filter-select") ? " c-select-inline" : "");
      sel.classList.add("c-select-native");
      sel.parentNode.insertBefore(wrap, sel);
      wrap.appendChild(sel);
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "c-select-btn";
      btn.setAttribute("aria-haspopup", "listbox");
      btn.setAttribute("aria-expanded", "false");
      btn.disabled = sel.disabled;
      btn.innerHTML = `<span class="c-select-label"></span>
        <svg class="c-select-caret" viewBox="0 0 20 20" fill="none" aria-hidden="true">
          <path d="M5 7.5l5 5 5-5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>`;
      wrap.appendChild(btn);
      const sync = () => {
        const opt = sel.options[sel.selectedIndex];
        btn.querySelector(".c-select-label").textContent = opt ? opt.textContent : "Select";
        btn.disabled = sel.disabled;
      };
      sync();
      sel.addEventListener("change", sync);
      btn.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        if (sel.disabled) return;
        if (wrap.classList.contains("open")) closeSelectMenus();
        else openSelectMenu(sel, wrap, btn);
      });
    });
    if (!window._kskSelectUi) {
      window._kskSelectUi = true;
      document.addEventListener("click", (e) => {
        if (!e.target.closest(".c-select") && !e.target.closest(".c-select-menu")) closeSelectMenus();
      });
      document.addEventListener("keydown", (e) => {
        if (e.key === "Escape") closeSelectMenus();
      });
      window.addEventListener("resize", closeSelectMenus);
      document.addEventListener("scroll", closeSelectMenus, true);
    }
  }

  function initCharts(scope) {
    enhanceSelects(scope);
    (scope || document).querySelectorAll("canvas[data-spark]").forEach((c) => {
      const key = c.getAttribute("data-spark");
      const data = key.split(".").reduce((o, k) => o && o[k], AppData);
      drawSparkline(c, data, c.getAttribute("data-color") || "#2563eb");
    });
    (scope || document).querySelectorAll("canvas[data-line]").forEach((c) => {
      const kind = c.getAttribute("data-line");
      if (kind === "sales") {
        drawLineChart(c, [{ data: AppData.salesTrend, color: "#2563eb" }]);
      }
      if (kind === "traffic") {
        drawLineChart(c, [
          { data: AppData.trafficHistory.download, color: "#2563eb" },
          { data: AppData.trafficHistory.upload, color: "#0ea5e9" },
        ]);
      }
    });
  }

  global.UI = {
    Icons,
    badge,
    statusRow,
    progressBar,
    toggle,
    kpi,
    emptyState,
    table,
    toast,
    modal,
    closeModal,
    confirmDialog,
    drawer,
    closeDrawer,
    dl,
    peso,
    escapeHtml,
    titleCase,
    initCharts,
    enhanceSelects,
    closeSelectMenus,
    el,
  };
})(window);
