/**
 * KonekSik-fi Captive Portal — local demo server (FastFi CGI baseline)
 *
 * Serves the UI and mocks /cgi-bin/api?action=… exactly like FastFi
 * EXTRACTED-OPENWRT-FASTFI-V2.5.1/rootfs/www/bootstrap.js expects.
 * Does not implement legacy /api/portal/* routes.
 *
 * Usage: double-click preview.bat  OR  node demo-server.mjs
 */
import {
  existsSync,
  readFileSync,
  statSync,
} from "node:fs";
import http from "node:http";
import { dirname, extname, join, normalize, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { exec } from "node:child_process";

const root = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.KONEKSIK_PORTAL_PORT || 4180);
const INSERT_TIMEOUT = 60;
const PESO_PER_PULSE = 1;

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".ico": "image/x-icon",
  ".mp3": "audio/mpeg",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
};

/** FastFi-shaped rates: time is seconds (minutes × 60), matching rates.lua. */
const RATES = [
  { price: 1, time: 5 * 60, download_mb: 0, upload_mb: 0, paused_limit: 3, validity_minutes: 0, data_limit_mb: 0 },
  { price: 5, time: 30 * 60, download_mb: 0, upload_mb: 0, paused_limit: 3, validity_minutes: 0, data_limit_mb: 0 },
  { price: 10, time: 60 * 60, download_mb: 0, upload_mb: 0, paused_limit: 3, validity_minutes: 0, data_limit_mb: 0 },
  { price: 20, time: 180 * 60, download_mb: 0, upload_mb: 0, paused_limit: 3, validity_minutes: 0, data_limit_mb: 0 },
];

const DEMO_SLOT = "AA:11:22:33:44:55";

/** Demo portal media state (mirrors firmware .custom_banner marker). */
const portalMedia = {
  hasCustomBanner: false,
  customBannerPath: "", // relative under root when set
};

/** @type {Map<string, object>} */
const sessions = new Map();

let slotLockedBy = "";
let slotCoin = 0;
let slotStartedAt = 0;

function json(res, obj, status = 200) {
  res.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" });
  res.end(JSON.stringify(obj));
}

function keyFrom(mac, deviceId) {
  return String(mac || deviceId || "demo-device").toLowerCase();
}

function getOrCreate(mac, deviceId, ip) {
  const key = keyFrom(mac, deviceId);
  if (!sessions.has(key)) {
    sessions.set(key, {
      mac: mac || "AA:BB:CC:DD:EE:FF",
      ip: ip || "10.20.0.50",
      deviceId: deviceId || "",
      remaining: 0,
      paused: 0,
      active: 0,
      internet: 0,
      pause_count: 0,
      paused_limit: 3,
      session_end: 0,
    });
  }
  return sessions.get(key);
}

function tickSession(s) {
  const now = Math.floor(Date.now() / 1000);
  if (s.active === 1 && s.paused !== 1 && s.session_end > 0) {
    s.remaining = Math.max(0, s.session_end - now);
    if (s.remaining <= 0) {
      s.active = 0;
      s.internet = 0;
      s.session_end = 0;
    }
  }
  return s;
}

function tickSlot() {
  if (!slotLockedBy) return;
  const elapsed = Math.floor((Date.now() - slotStartedAt) / 1000);
  // Demo: auto-insert ₱1 every ~4s while locked (mirrors old demo UX).
  const pulsesWanted = Math.min(10, Math.floor(elapsed / 4));
  if (pulsesWanted > slotCoin) slotCoin = pulsesWanted;
}

function parseUrl(req) {
  return new URL(req.url || "/", `http://127.0.0.1:${PORT}`);
}

function handleCgi(req, res, u) {
  const action = u.searchParams.get("action") || "";
  const mac = (u.searchParams.get("mac") || "").toLowerCase();
  const deviceId = u.searchParams.get("device_id") || "";
  const ip = u.searchParams.get("ip") || "";
  const s = getOrCreate(mac || "aa:bb:cc:dd:ee:ff", deviceId, ip);
  tickSession(s);

  switch (action) {
    case "getMac":
      return json(res, { mac: s.mac, ip: s.ip });

    case "checkDevice":
      return json(res, {
        status: "ok",
        mac: s.mac,
        ip: s.ip,
        time: s.remaining,
        download: 0,
        upload: 0,
        internet: s.internet,
        paused_limit: s.paused_limit,
        pause_count: s.pause_count,
        data_limit_mb: 0,
        data_remaining_mb: 0,
        coin: 0,
        reconnect: 0,
      });

    case "session_status": {
      tickSession(s);
      let status = "inactive";
      if (s.paused === 1 && s.remaining > 0) status = "paused";
      else if (s.active === 1 && s.remaining > 0) status = "active";
      return json(res, {
        status,
        active: s.active,
        paused: s.paused,
        time_left: s.remaining,
        remaining: s.remaining,
      });
    }

    case "rates":
      return json(res, { status: "ok", data: RATES });

    case "list_esp_devices":
      return json(res, {
        router_mac: "aa:bb:cc:dd:ee:00",
        total_esp_slots: 1,
        available_licenses: 1,
        used_licenses: 0,
        esp_devices: [{
          id: 1,
          slot_name: "Demo Slot",
          slot_mac: DEMO_SLOT,
          status: "online",
          license_status: "licensed",
          last_seen: Math.floor(Date.now() / 1000),
          ap_id: 0,
        }],
      });

    case "lockcoin": {
      const slotMac = u.searchParams.get("slot_mac") || DEMO_SLOT;
      if (slotLockedBy && slotLockedBy !== mac) {
        return json(res, { status: "error", message: "Coin Slot Busy" });
      }
      slotLockedBy = mac || "locked";
      slotCoin = 0;
      slotStartedAt = Date.now();
      return json(res, { status: "ok", slot_mac: slotMac, message: "locked" });
    }

    case "fetchcoin": {
      tickSlot();
      return json(res, { coin: slotCoin, status: "ok" });
    }

    case "unlockcoin":
      slotLockedBy = "";
      slotCoin = 0;
      slotStartedAt = 0;
      return json(res, { status: "ok" });

    case "clearcredit":
      slotCoin = 0;
      return json(res, { status: "ok" });

    case "updateDevice": {
      const time = Number(u.searchParams.get("time") || 0);
      const coin = Number(u.searchParams.get("coin") || 0);
      if (time <= 0 && coin <= 0) {
        return json(res, { status: "error", message: "No time granted" });
      }
      const now = Math.floor(Date.now() / 1000);
      const add = time > 0 ? time : 0;
      s.remaining = Math.max(0, s.remaining) + add;
      s.session_end = now + s.remaining;
      s.active = 1;
      s.paused = 0;
      s.internet = 1;
      slotLockedBy = "";
      slotCoin = 0;
      return json(res, { status: "ok", result: "success", message: "Session updated", remaining: s.remaining });
    }

    case "internet": {
      const status = Number(u.searchParams.get("status"));
      if (status === 0) {
        if (s.remaining <= 0) return json(res, { status: "error", message: "Session expired" });
        if (s.pause_count >= s.paused_limit) {
          return json(res, { status: "error", message: "Pause limit reached" });
        }
        tickSession(s);
        s.paused = 1;
        s.internet = 0;
        s.pause_count += 1;
        s.session_end = 0;
        return json(res, { status: "success", message: "Session Paused", paused: 1 });
      }
      if (status === 1) {
        if (s.remaining <= 0) return json(res, { status: "error", message: "No time left" });
        const now = Math.floor(Date.now() / 1000);
        s.paused = 0;
        s.active = 1;
        s.internet = 1;
        s.session_end = now + s.remaining;
        return json(res, { status: "success", message: "Session Resumed", paused: 0 });
      }
      return json(res, {
        status: s.internet ? "connected" : "disconnected",
        internet: s.internet,
      });
    }

    case "voucher": {
      const code = String(u.searchParams.get("code") || "").trim().toUpperCase();
      if (!code) return json(res, { status: "error", message: "Enter a voucher code" });
      if (code === "INVALID") return json(res, { status: "error", message: "Invalid voucher code" });
      let minutes = 15;
      if (code === "DEMO60") minutes = 60;
      else if (code === "DEMO5") minutes = 5;
      const now = Math.floor(Date.now() / 1000);
      s.remaining = Math.max(0, s.remaining) + minutes * 60;
      s.session_end = now + s.remaining;
      s.active = 1;
      s.paused = 0;
      s.internet = 1;
      return json(res, { status: "ok", message: "Voucher redeemed", remaining: s.remaining });
    }

    case "check_coin_lock": {
      tickSlot();
      if (!slotLockedBy || (mac && slotLockedBy !== mac)) {
        return json(res, { locked: false });
      }
      const elapsed = Math.floor((Date.now() - slotStartedAt) / 1000);
      const remaining = Math.max(0, INSERT_TIMEOUT - elapsed);
      return json(res, {
        locked: true,
        slot_mac: DEMO_SLOT,
        coin: slotCoin,
        remaining_timer: remaining,
        insert_timer: INSERT_TIMEOUT,
      });
    }

    case "terminate": {
      // Demo: self-service terminate (real firmware also checks ARP MAC match).
      s.remaining = 0;
      s.timerRunning = false;
      s.active = 0;
      s.paused = 0;
      s.internet = 0;
      s.session_end = 0;
      slotLockedBy = "";
      slotCoin = 0;
      return json(res, {
        status: "ok",
        message: "Session terminated",
        mac: s.mac,
        remaining: 0,
        time_left: 0,
        active: 0,
        paused: 0,
        internet: 0,
      });
    }

    case "client_deauth": {
      // Demo stand-in for admin terminate (real route requires admin session).
      const target = (u.searchParams.get("mac") || mac || "").toLowerCase();
      if (!target) return json(res, { status: "error", message: "Missing or invalid MAC" });
      const victim = getOrCreate(target, "", "");
      victim.remaining = 0;
      victim.active = 0;
      victim.paused = 0;
      victim.internet = 0;
      victim.session_end = 0;
      return json(res, { status: "ok", message: "Client deauthenticated", mac: target });
    }

    case "gcash_public_config":
      return json(res, { status: "ok", enabled: 0 });

    case "gcash_order":
      return json(res, { status: "error", message: "GCash demo disabled" });

    case "gcash_freewindow":
      return json(res, { status: "ok", active: 0 });

    case "get_portal_media": {
      const t = Date.now();
      const defaultBanner = "/image/Default-Banner.png";
      const hasCustom = portalMedia.hasCustomBanner;
      return json(res, {
        status: "ok",
        has_custom_banner: hasCustom ? 1 : 0,
        banner_url: hasCustom
          ? `/image/banner.jpg?t=${t}`
          : `${defaultBanner}?t=${t}`,
        default_banner_url: defaultBanner,
        has_custom_music: 1,
        music_url: `/audio/insert.mp3?t=${t}`,
        bg_music_url: `/audio/insert.mp3?t=${t}`,
        coin_url: `/audio/coin.mp3?t=${t}`,
        success_url: `/audio/success.mp3?t=${t}`,
        banner_text: "Insert coin or enter voucher to start",
        brand_name: "KonekSik-fi",
        shop_name: "KonekSik-fi",
      });
    }

    case "restore_default_banner":
      portalMedia.hasCustomBanner = false;
      return json(res, {
        status: "ok",
        message: "Restored Default-Banner.png",
        custom: 0,
        default_banner_url: "/image/Default-Banner.png",
      });

    case "upload_banner":
      // Demo: mark custom without writing bytes (HEAD/GET still serves Default unless custom flag).
      portalMedia.hasCustomBanner = true;
      return json(res, { status: "ok", message: "Banner uploaded successfully!", custom: 1 });

    default:
      return json(res, { status: "error", message: "API Route Not Found: " + action }, 404);
  }
}

function safeFile(urlPath) {
  const decoded = decodeURIComponent((urlPath || "/").split("?")[0]);
  let rel = decoded.replace(/^\/+/, "");
  if (!rel || rel.endsWith("/")) rel += "index.html";

  // FastFi-aligned aliases for captive portal media paths.
  const aliases = {
    "image/Default-Banner.png": "Default-Banner.png",
    "Default-Banner.png": "Default-Banner.png",
    "image/banner.jpg": portalMedia.hasCustomBanner ? "Default-Banner.png" : "Default-Banner.png",
    "audio/insert.mp3": "bg_music.mp3",
    "audio/coin.mp3": "coin.mp3",
    "audio/success.mp3": "success.mp3",
  };
  if (aliases[rel]) rel = aliases[rel];

  const full = normalize(join(root, rel));
  const rootNorm = normalize(root + sep);
  if (full !== normalize(root) && !full.startsWith(rootNorm)) return null;
  return full;
}

const server = http.createServer(async (req, res) => {
  const u = parseUrl(req);

  if (u.pathname === "/cgi-bin/api") {
    try {
      handleCgi(req, res, u);
    } catch (err) {
      json(res, { status: "error", message: String(err && err.message ? err.message : err) }, 500);
    }
    return;
  }

  // Legacy RenzFi paths must not be used — return clear 404 for validation.
  if (u.pathname.startsWith("/api/")) {
    json(res, { status: "error", message: "Legacy /api removed — use /cgi-bin/api (FastFi baseline)" }, 404);
    return;
  }

  let filePath = safeFile(u.pathname === "/" ? "/login.html" : u.pathname);
  if (!filePath || !existsSync(filePath) || statSync(filePath).isDirectory()) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not found: " + u.pathname);
    return;
  }
  const type = MIME[extname(filePath).toLowerCase()] || "application/octet-stream";
  res.writeHead(200, { "Content-Type": type, "Cache-Control": "no-store" });
  res.end(readFileSync(filePath));
});

server.listen(PORT, "127.0.0.1", () => {
  const url = `http://127.0.0.1:${PORT}/login.html`;
  console.log("");
  console.log("============================================");
  console.log(" KonekSik-fi Captive Portal (FastFi CGI demo)");
  console.log("============================================");
  console.log(" Open:     " + url);
  console.log(" API:      /cgi-bin/api?action=…");
  console.log(" Rates:    View Rates (FastFi price/minutes)");
  console.log(" Coins:    Insert Coin — demo auto ₱1 / ~4s");
  console.log(" Voucher:  DEMO5 / DEMO60 (or any code = 15 min)");
  console.log(" Stop:     Ctrl+C");
  console.log("============================================");
  console.log("");
  const openCmd =
    process.platform === "win32"
      ? `start "" "${url}"`
      : process.platform === "darwin"
        ? `open "${url}"`
        : `xdg-open "${url}"`;
  if (process.env.KONEKSIK_PORTAL_NO_OPEN !== "1") {
    exec(openCmd, () => {});
  }
});

server.on("error", (err) => {
  console.error("[demo-server]", err.message || err);
  process.exit(1);
});
