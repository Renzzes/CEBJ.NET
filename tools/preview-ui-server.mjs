/**
 * Dev preview server — serves live admin + guest portal with no-cache.
 * Admin preview is generated from admin.html on every request (always fresh).
 * Guest portal is the KonekSik-fi Captive Portal package + FastFi CGI mock.
 *
 * Usage: node tools/preview-ui-server.mjs
 */
import { spawn } from "node:child_process";
import {
  createReadStream,
  existsSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import http from "node:http";
import { dirname, extname, join, normalize, sep } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const workspace = join(here, "..");
const wwwRoot = join(workspace, "EXTRACTED-OPENWRT-FASTFI-V2.5.1", "rootfs", "www");
const guestRoot = join(workspace, "KonekSik-fi Captive Portal");
const PORT = Number(process.env.KONEKSIK_PREVIEW_PORT || 8777);

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".mjs": "application/javascript; charset=utf-8",
  ".json": "application/json",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".ico": "image/x-icon",
  ".mp3": "audio/mpeg",
  ".svg": "image/svg+xml",
  ".webp": "image/webp",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".map": "application/json",
};

function noCache(res, type) {
  res.writeHead(200, {
    "Content-Type": type,
    "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
    Pragma: "no-cache",
    Expires: "0",
  });
}

function safeJoin(root, urlPath) {
  const decoded = decodeURIComponent((urlPath || "/").split("?")[0]);
  let rel = decoded.replace(/^\/+/, "");
  if (!rel || rel.endsWith("/")) rel += "index.html";
  const full = normalize(join(root, rel));
  const rootNorm = normalize(root + sep);
  if (full !== normalize(root) && !full.startsWith(rootNorm)) return null;
  return full;
}

function buildAdminPreviewHtml() {
  const adminPath = join(wwwRoot, "admin.html");
  let html = readFileSync(adminPath, "utf8");
  // Local preview: disable anti-devtools + inject API mock
  html = html.replace(/<title>.*?<\/title>/i, "<title>CEBJ.NET Admin</title>");
  html = html.replace(/<script>window\.FASTFI_DDT_MODE=['"]admin['"];?<\/script>\s*/i, "<!-- preview: anti-devtools disabled -->\n");
  html = html.replace(/<script src="\.\/lib\/disable-devtool[^"]*"><\/script>\s*/gi, "");
  html = html.replace(/<script src="\.\/lib\/devtool-guard[^"]*"><\/script>\s*/gi, "");
  // Inject ui-preview.js before admin.js (absolute or relative)
  if (!html.includes("ui-preview.js")) {
    html = html.replace(
      /(<script src="\/?admin\.js[^"]*"><\/script>)/i,
      '<script src="./ui-preview.js?v=dev"></script>\n    $1',
    );
  }
  // Cache-bust asset query on each serve so CSS/JS edits show immediately
  const bust = Date.now();
  html = html.replace(
    /(href|src)="(\.\/[^"]+\.(?:css|js))(?:\?[^"]*)?"/gi,
    `$1="$2?v=dev-${bust}"`,
  );
  html = html.replace(
    /(href|src)="(\/[^"]+\.(?:css|js))(?:\?[^"]*)?"/gi,
    `$1="$2?v=dev-${bust}"`,
  );
  return html;
}

function hubHtml() {
  const bust = Date.now();
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta http-equiv="Cache-Control" content="no-store" />
  <title>CEBJ.NET Dev Preview</title>
  <style>
    body{font-family:Segoe UI,system-ui,sans-serif;margin:0;background:#07111f;color:#e8f1ff;min-height:100vh;display:grid;place-items:center}
    .card{width:min(560px,92vw);background:#0d1b2e;border:1px solid rgba(0,168,255,.35);border-radius:12px;padding:28px 24px;box-shadow:0 0 24px rgba(0,140,255,.15)}
    h1{margin:0 0 8px;font-size:1.35rem}
    p{margin:0 0 18px;color:#9bb4d0;font-size:14px;line-height:1.45}
    a{display:block;margin:0 0 10px;padding:14px 16px;border-radius:8px;text-decoration:none;font-weight:700;letter-spacing:.02em}
    .admin{background:#008cff;color:#fff}
    .guest{background:#12324f;color:#7fd0ff;border:1px solid rgba(0,168,255,.45)}
    .meta{margin-top:16px;font-size:12px;color:#7a93b0}
    code{color:#7fd0ff}
  </style>
</head>
<body>
  <div class="card">
    <h1>CEBJ.NET Dev Preview</h1>
    <p>Live files from disk — <strong>no cache</strong>. Edit admin/captive portal sources and refresh the browser.</p>
    <a class="admin" href="/admin-preview.html?t=${bust}">Open Admin Dashboard</a>
    <a class="guest" href="/guest/login.html?t=${bust}">Open Captive Portal (guest)</a>
    <p class="meta">Admin source: <code>rootfs/www/admin.html</code> (served live)<br/>
    Guest source: <code>KonekSik-fi Captive Portal/</code><br/>
    Stop: Ctrl+C in the preview window</p>
  </div>
</body>
</html>`;
}

/* —— Minimal guest CGI mock (mirrors demo-server FastFi actions used by UI) —— */
let portalCustomBanner = false;
function json(res, obj, status = 200) {
  noCache(res, "application/json");
  res.end(JSON.stringify(obj));
}

function handleCgi(u, res) {
  const action = u.searchParams.get("action") || "";
  const t = Date.now();
  switch (action) {
    case "getMac":
      return json(res, { mac: "aa:bb:cc:dd:ee:ff", ip: "10.20.0.50" });
    case "get_portal_media":
      return json(res, {
        status: "ok",
        has_custom_banner: portalCustomBanner ? 1 : 0,
        banner_url: portalCustomBanner
          ? `/image/banner.jpg?t=${t}`
          : `/image/Default-Banner.png?t=${t}`,
        default_banner_url: "/image/Default-Banner.png",
        music_url: "/audio/insert.mp3",
        bg_music_url: "/audio/insert.mp3",
        coin_url: "/audio/coin.mp3",
        success_url: "/audio/success.mp3",
        banner_text: "Insert coin or enter voucher to start",
        brand_name: "CEBJ.NET",
      });
    case "rates":
      return json(res, {
        status: "ok",
        data: [
          { price: 1, time: 300, download_mb: 0, upload_mb: 0, paused_limit: 3 },
          { price: 5, time: 1800, download_mb: 0, upload_mb: 0, paused_limit: 3 },
          { price: 10, time: 3600, download_mb: 0, upload_mb: 0, paused_limit: 3 },
        ],
      });
    case "checkDevice":
      return json(res, {
        status: "ok",
        mac: "aa:bb:cc:dd:ee:ff",
        ip: "10.20.0.50",
        time: 0,
        internet: 0,
        paused_limit: 3,
      });
    case "session_status":
      return json(res, { status: "inactive", remaining: 0, active: 0, paused: 0 });
    case "list_esp_devices":
      return json(res, {
        esp_devices: [{ id: 1, slot_mac: "aa:11:22:33:44:55", status: "online", license_status: "licensed" }],
      });
    case "lockcoin":
      return json(res, { status: "ok" });
    case "fetchcoin":
      return json(res, { coin: 0, status: "ok" });
    case "unlockcoin":
    case "clearcredit":
      return json(res, { status: "ok" });
    case "upload_banner":
      portalCustomBanner = true;
      return json(res, { status: "ok", message: "Banner uploaded successfully!", custom: 1 });
    case "restore_default_banner":
      portalCustomBanner = false;
      return json(res, { status: "ok", message: "Restored Default-Banner.png", custom: 0 });
    default:
      return json(res, { status: "ok", message: "preview-mock:" + action });
  }
}

function sendFile(res, filePath) {
  const type = MIME[extname(filePath).toLowerCase()] || "application/octet-stream";
  noCache(res, type);
  createReadStream(filePath).pipe(res);
}

const server = http.createServer((req, res) => {
  const u = new URL(req.url || "/", `http://127.0.0.1:${PORT}`);

  if (u.pathname === "/cgi-bin/api") {
    handleCgi(u, res);
    return;
  }

  if (u.pathname === "/favicon.ico" || u.pathname === "/CEBJ_ICON.png") {
    const icon = join(guestRoot, "CEBJ_ICON.png");
    if (existsSync(icon)) {
      sendFile(res, icon);
      return;
    }
  }

  if (u.pathname === "/" || u.pathname === "/index.html") {
    noCache(res, "text/html; charset=utf-8");
    res.end(hubHtml());
    return;
  }

  // Always rebuild from live admin.html so CSS/JS/section edits appear after refresh
  if (u.pathname === "/admin-preview.html" || u.pathname === "/admin.html") {
    try {
      const html = buildAdminPreviewHtml();
      // Also write a stale-synced copy for tools that open the file directly
      try {
        writeFileSync(join(wwwRoot, "admin-preview.html"), html, "utf8");
      } catch {
        /* ignore write failures on locked files */
      }
      noCache(res, "text/html; charset=utf-8");
      res.end(html);
    } catch (err) {
      res.writeHead(500, { "Content-Type": "text/plain" });
      res.end(String(err && err.message ? err.message : err));
    }
    return;
  }

  // Guest captive portal package
  if (u.pathname === "/guest" || u.pathname === "/guest/") {
    res.writeHead(302, { Location: "/guest/login.html", "Cache-Control": "no-store" });
    res.end();
    return;
  }
  if (u.pathname.startsWith("/guest/")) {
    const rel = u.pathname.slice("/guest".length);
    // Map FastFi media aliases into package files
    let mapped = rel;
    if (mapped === "/image/Default-Banner.png" || mapped === "/Default-Banner.png") mapped = "/Default-Banner.png";
    if (mapped === "/image/banner.jpg") mapped = "/Default-Banner.png";
    if (mapped === "/audio/insert.mp3") mapped = "/bg_music.mp3";
    if (mapped === "/audio/coin.mp3") mapped = "/coin.mp3";
    if (mapped === "/audio/success.mp3") mapped = "/success.mp3";
    const filePath = safeJoin(guestRoot, mapped === "/" ? "/login.html" : mapped);
    if (!filePath || !existsSync(filePath) || statSync(filePath).isDirectory()) {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("Not found: " + u.pathname);
      return;
    }
    sendFile(res, filePath);
    return;
  }

  // Admin www static — fall back to Captive Portal package for guest assets
  let filePath = safeJoin(wwwRoot, u.pathname);
  if ((!filePath || !existsSync(filePath)) && u.pathname.startsWith("/image/")) {
    if (u.pathname.includes("Default-Banner")) {
      const def = join(guestRoot, "Default-Banner.png");
      if (existsSync(def)) filePath = def;
    }
  }
  if (!filePath || !existsSync(filePath) || (existsSync(filePath) && statSync(filePath).isDirectory())) {
    const guestTry = safeJoin(guestRoot, u.pathname);
    if (guestTry && existsSync(guestTry) && !statSync(guestTry).isDirectory()) {
      filePath = guestTry;
    }
  }
  if (!filePath || !existsSync(filePath) || statSync(filePath).isDirectory()) {
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("Not found: " + u.pathname);
    return;
  }
  sendFile(res, filePath);
});

server.listen(PORT, "127.0.0.1", () => {
  const hub = `http://127.0.0.1:${PORT}/`;
  const admin = `http://127.0.0.1:${PORT}/admin-preview.html`;
  const guest = `http://127.0.0.1:${PORT}/guest/login.html`;
  console.log("");
  console.log("============================================");
  console.log(" KonekSik-fi LIVE Dev Preview (no-cache)");
  console.log("============================================");
  console.log(" Hub:    " + hub);
  console.log(" Admin:  " + admin);
  console.log(" Guest:  " + guest);
  console.log(" Edit files → refresh browser (Ctrl+F5)");
  console.log(" Stop:   Ctrl+C");
  console.log("============================================");
  console.log("");
  if (process.env.KONEKSIK_PREVIEW_NO_OPEN !== "1") {
    const openCmd =
      process.platform === "win32"
        ? `start "" "${hub}"`
        : process.platform === "darwin"
          ? `open "${hub}"`
          : `xdg-open "${hub}"`;
    spawn(openCmd, { shell: true, stdio: "ignore", detached: true }).unref();
  }
});

server.on("error", (err) => {
  console.error("[preview-ui-server]", err.message || err);
  process.exit(1);
});
