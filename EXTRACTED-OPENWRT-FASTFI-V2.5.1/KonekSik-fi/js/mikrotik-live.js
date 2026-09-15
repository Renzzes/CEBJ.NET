/**
 * Prototype helper: tries live MikroTik stats (REST or live/system.json).
 *
 * Production: the browser must NOT talk to RouterOS. The ESP32 proxies
 * GET /api/system and /api/network instead. This file is for early UI demos only.
 */
window.KskMikroTik = (function () {
  const COLORS = {
    ros: "#2D8653",
    admin: "#7F2D37",
    backups: "#B37D26",
    other: "#94A3B8",
  };
  const HEX_NAND = 128 * 1024 * 1024;
  let timer = null;

  function bytesToMb(n) {
    return Math.round((Number(n) / (1024 * 1024)) * 10) / 10;
  }

  function unwrap(data) {
    return Array.isArray(data) ? data[0] : data;
  }

  function parseCpu(v) {
    return parseInt(String(v || "0").replace("%", ""), 10) || 0;
  }

  function memPct(free, total) {
    const t = Number(total);
    const f = Number(free);
    if (!t) return 0;
    return Math.round((1 - f / t) * 100);
  }

  function prettyUptime(raw) {
    const s = String(raw || "");
    const w = +(s.match(/(\d+)w/) || [])[1] || 0;
    const d = +(s.match(/(\d+)d/) || [])[1] || 0;
    const h = +(s.match(/(\d+)h/) || [])[1] || 0;
    const days = w * 7 + d;
    if (days || h) return (days ? days + "d " : "") + h + "h";
    return s || "—";
  }

  function readTemp(health) {
    const rows = Array.isArray(health) ? health : health ? [health] : [];
    for (let i = 0; i < rows.length; i++) {
      const name = String(rows[i].name || "").toLowerCase();
      if (name === "temperature" || name === "cpu-temperature" || name === "board-temperature") {
        const v = parseFloat(rows[i].value);
        if (!isNaN(v)) return Math.round(v);
      }
    }
    return null;
  }

  function bucket(name) {
    const n = String(name || "").replace(/^\/+/, "").toLowerCase();
    if (/\.(backup|rsc)$/.test(n) || n.indexOf("autosupout") !== -1) return "backups";
    if (/(^|\/)(hotspot|admin)(\/|$)/.test(n) || n.indexOf("koneksik") !== -1) return "admin";
    return "other";
  }

  function authHeader() {
    const a = window.AppData && AppData.auth;
    if (!a || !a.username) return {};
    try {
      return { Authorization: "Basic " + btoa(a.username + ":" + (a.password || "")) };
    } catch (e) {
      return {};
    }
  }

  async function getJson(url, withAuth) {
    const headers = { Accept: "application/json" };
    if (withAuth) Object.assign(headers, authHeader());
    const res = await fetch(url, { headers, credentials: "omit" });
    if (!res.ok) throw new Error(String(res.status));
    return res.json();
  }

  async function loadDump() {
    const paths = ["live/system.json", "/live/system.json"];
    for (let i = 0; i < paths.length; i++) {
      try {
        const data = await getJson(paths[i], false);
        if (data && (data.resource || data["total-hdd-space"] || data.files)) return data;
      } catch (e) {}
    }
    return null;
  }

  async function loadRest() {
    if (location.protocol === "file:") return null;
    const origin = location.origin;
    const resource = unwrap(await getJson(origin + "/rest/system/resource", true));
    let files = [];
    let health = [];
    try { files = await getJson(origin + "/rest/file", true); } catch (e) {}
    try { health = await getJson(origin + "/rest/system/health", true); } catch (e) {}
    return { resource, files, health };
  }

  function apply(payload) {
    const resource = unwrap(payload.resource || payload);
    if (!resource || resource["total-hdd-space"] == null && resource["free-hdd-space"] == null) {
      throw new Error("no-resource");
    }
    const files = Array.isArray(payload.files) ? payload.files : [];
    const health = payload.health;
    const totalHdd = Number(resource["total-hdd-space"]) || 0;
    const freeHdd = Number(resource["free-hdd-space"]) || 0;
    const usedHdd = Math.max(0, totalHdd - freeHdd);
    const board = resource["board-name"] || AppData.mikrotik.model;
    const nand = /hex/i.test(board) ? HEX_NAND : (totalHdd || HEX_NAND);
    const rosBytes = Math.max(0, nand - totalHdd);
    const sums = { admin: 0, backups: 0, other: 0 };
    files.forEach(function (f) {
      if (!f || String(f.type).toLowerCase() === "directory") return;
      sums[bucket(f.name)] += Number(f.size) || 0;
    });
    const fileSum = sums.admin + sums.backups + sums.other;
    sums.other += Math.max(0, usedHdd - fileSum);
    const temp = readTemp(health);
    const usedAll = rosBytes + usedHdd;
    AppData.mikrotik.model = board;
    AppData.mikrotik.routeros = resource.version || AppData.mikrotik.routeros;
    AppData.mikrotik.cpu = parseCpu(resource["cpu-load"]);
    AppData.mikrotik.memory = memPct(resource["free-memory"], resource["total-memory"]);
    AppData.mikrotik.storage = nand ? Math.round((usedAll / nand) * 100) : 0;
    if (temp != null) AppData.mikrotik.temperature = temp;
    AppData.mikrotik.uptime = prettyUptime(resource.uptime);
    AppData.mikrotik.connection = "connected";
    AppData.mikrotik.api = "connected";
    AppData.mikrotik.storageTotalMb = bytesToMb(nand);
    AppData.mikrotik.storageSlices = [
      { label: "RouterOS", mb: bytesToMb(rosBytes), color: COLORS.ros },
      { label: "Admin & portal", mb: bytesToMb(sums.admin), color: COLORS.admin },
      { label: "Backups", mb: bytesToMb(sums.backups), color: COLORS.backups },
      { label: "Other", mb: bytesToMb(sums.other), color: COLORS.other },
    ];
    AppData.mikrotik.storageLive = true;
    AppData.status.mikrotik = "online";
    window.dispatchEvent(new CustomEvent("ksk-mikrotik-updated"));
  }

  async function refresh() {
    try {
      const dump = await loadDump();
      if (dump) {
        apply(dump);
        return true;
      }
      const rest = await loadRest();
      if (rest) {
        apply(rest);
        return true;
      }
    } catch (e) {}
    AppData.mikrotik.storageLive = false;
    return false;
  }

  function start() {
    refresh();
    if (timer) clearInterval(timer);
    timer = setInterval(refresh, 30000);
  }

  return { start, refresh };
})();
