/**
 * Captive Portal E2E checklist vs FastFi baseline (banner/music + core APIs).
 *
 * Usage: node validate-captive-portal-checklist.mjs
 * Must print RESULT: PASS
 */
import { spawn } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const workspace = join(here, "..");
const rootfs = join(workspace, "EXTRACTED-OPENWRT-FASTFI-V2.5.1", "rootfs");
const www = join(rootfs, "www");
const PORT = 4192;

const rows = [];
function check(id, title, pass, detail) {
  rows.push({ id, title, pass: !!pass, detail: detail || "" });
  console.log(`${pass ? "PASS" : "FAIL"}  [${id}] ${title}${detail ? " — " + detail : ""}`);
}

function read(p) {
  return existsSync(p) ? readFileSync(p, "utf8") : "";
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function getJson(url) {
  const res = await fetch(url, { cache: "no-store" });
  const text = await res.text();
  let data = null;
  try {
    data = JSON.parse(text);
  } catch {
    data = { _raw: text };
  }
  return { status: res.status, data, ok: res.ok };
}

async function headOk(url) {
  try {
    const res = await fetch(url, { method: "HEAD", cache: "no-store" });
    if (res.ok) return true;
    // Some static servers omit HEAD — try GET range/tiny
    const g = await fetch(url, { cache: "no-store" });
    return g.ok;
  } catch {
    return false;
  }
}

async function main() {
  console.log("=== KonekSik Captive Portal ↔ FastFi checklist ===\n");

  // --- Static / firmware checklist ---
  const defaultBannerWww = join(www, "image", "Default-Banner.png");
  const defaultBannerRoot = join(www, "Default-Banner.png");
  const defaultBannerPkg = join(here, "Default-Banner.png");
  check(
    "B1",
    "Default-Banner.png ships in firmware www/image/",
    existsSync(defaultBannerWww) && statSync(defaultBannerWww).size > 1000,
    existsSync(defaultBannerWww) ? `${statSync(defaultBannerWww).size} bytes` : "missing",
  );
  check(
    "B2",
    "Default-Banner.png present in Captive Portal package",
    existsSync(defaultBannerPkg) && statSync(defaultBannerPkg).size > 1000,
  );
  check(
    "B3",
    "Firmware get_portal_media + restore_default_banner implemented",
    /function\s+M\.get_portal_media/.test(read(join(rootfs, "usr/lib/lua/fastfi/api/routes/ops.lua"))) &&
      /function\s+M\.restore_default_banner/.test(read(join(rootfs, "usr/lib/lua/fastfi/api/routes/ops.lua"))) &&
      /get_portal_media\s*=\s*true/.test(read(join(rootfs, "usr/lib/lua/fastfi/api/router.lua"))),
  );
  check(
    "B4",
    "upload_banner sets .custom_banner marker",
    read(join(rootfs, "usr/lib/lua/fastfi/api/routes/ops.lua")).includes(".custom_banner"),
  );
  check(
    "B5",
    "Admin Captive Portal shows Live Preview column (no factory-default box)",
    !read(join(www, "admin.html")).includes("defaultBannerPreview") &&
      !read(join(www, "admin.html")).includes("Factory default (owner reference)") &&
      read(join(www, "admin.html")).includes("captivePortalLivePreview") &&
      read(join(www, "admin.html")).includes("Portal Configuration") &&
      read(join(www, "admin.html")).includes("Live Preview") &&
      read(join(www, "admin.html")).includes("restoreDefaultBanner"),
  );
  check(
    "B6",
    "Admin-ext + CaptivePortalLivePreview (blob-only banner)",
    read(join(www, "admin-ext.js")).includes("loadPortalBannerPreviews") &&
      read(join(www, "admin-ext.js")).includes("CaptivePortalLivePreview") &&
      existsSync(join(www, "js", "portal-live-preview.js")) &&
      read(join(www, "js", "portal-live-preview.js")).includes("never auto-fetch") &&
      read(join(www, "js", "portal-live-preview.js")).includes("Custom banner active") &&
      existsSync(join(www, "css", "portal-live-preview.css")),
  );
  check(
    "B7",
    "FastFi audio assets exist (insert/coin/success)",
    existsSync(join(www, "audio", "insert.mp3")) &&
      existsSync(join(www, "audio", "coin.mp3")) &&
      existsSync(join(www, "audio", "success.mp3")),
  );
  check(
    "B8",
    "Captive Portal loadBranding uses get_portal_media",
    read(join(here, "renzfi-app.js")).includes("getPortalMedia") &&
      read(join(here, "fastfi-cgi.js")).includes('cgiGet("get_portal_media"'),
  );
  check(
    "B9",
    "Portal HTML defaults to /image/Default-Banner.png",
    read(join(here, "login.html")).includes('/image/Default-Banner.png') &&
      read(join(here, "status.html")).includes('/image/Default-Banner.png'),
  );
  check(
    "B10",
    "Core FastFi CGI actions still wired (coin/session)",
    ["lockcoin", "fetchcoin", "updateDevice", "internet", "voucher", "rates"].every((a) =>
      read(join(here, "fastfi-cgi.js")).includes(`"${a}"`) ||
      read(join(here, "fastfi-cgi.js")).includes(`'${a}'`),
    ),
  );

  // --- Live demo E2E ---
  const child = spawn(process.execPath, [join(here, "demo-server.mjs")], {
    env: { ...process.env, KONEKSIK_PORTAL_PORT: String(PORT), KONEKSIK_PORTAL_NO_OPEN: "1" },
    stdio: ["ignore", "pipe", "pipe"],
  });

  try {
    let up = false;
    for (let i = 0; i < 40; i++) {
      try {
        const p = await getJson(`http://127.0.0.1:${PORT}/cgi-bin/api?action=getMac`);
        if (p.status === 200) {
          up = true;
          break;
        }
      } catch {
        /* retry */
      }
      await sleep(100);
    }
    check("L0", "Demo server boots", up);
    if (!up) throw new Error("demo server did not start");

    const media0 = await getJson(`http://127.0.0.1:${PORT}/cgi-bin/api?action=get_portal_media`);
    check(
      "L1",
      "get_portal_media with no upload → Default-Banner",
      media0.data &&
        Number(media0.data.has_custom_banner) === 0 &&
        String(media0.data.banner_url || "").includes("Default-Banner.png"),
      JSON.stringify({
        has_custom_banner: media0.data && media0.data.has_custom_banner,
        banner_url: media0.data && media0.data.banner_url,
      }),
    );

    check(
      "L2",
      "Default banner image is HTTP-reachable",
      await headOk(`http://127.0.0.1:${PORT}/image/Default-Banner.png`),
    );

    check(
      "L3",
      "Insert/coin/success audio aliases reachable",
      (await headOk(`http://127.0.0.1:${PORT}/audio/insert.mp3`)) &&
        (await headOk(`http://127.0.0.1:${PORT}/audio/coin.mp3`)) &&
        (await headOk(`http://127.0.0.1:${PORT}/audio/success.mp3`)),
    );

    const upBanner = await getJson(`http://127.0.0.1:${PORT}/cgi-bin/api?action=upload_banner`);
    check("L4", "upload_banner marks custom", upBanner.data && upBanner.data.status === "ok");

    const media1 = await getJson(`http://127.0.0.1:${PORT}/cgi-bin/api?action=get_portal_media`);
    check(
      "L5",
      "After upload → custom banner_url (banner.jpg)",
      media1.data &&
        Number(media1.data.has_custom_banner) === 1 &&
        String(media1.data.banner_url || "").includes("banner.jpg"),
      media1.data && media1.data.banner_url,
    );

    const restore = await getJson(
      `http://127.0.0.1:${PORT}/cgi-bin/api?action=restore_default_banner`,
    );
    check("L6", "restore_default_banner ok", restore.data && restore.data.status === "ok");

    const media2 = await getJson(`http://127.0.0.1:${PORT}/cgi-bin/api?action=get_portal_media`);
    check(
      "L7",
      "After restore → back to Default-Banner.png",
      media2.data &&
        Number(media2.data.has_custom_banner) === 0 &&
        String(media2.data.banner_url || "").includes("Default-Banner.png"),
      media2.data && media2.data.banner_url,
    );

    // Core portal session still works
    const rates = await getJson(`http://127.0.0.1:${PORT}/cgi-bin/api?action=rates`);
    check(
      "L8",
      "rates still FastFi-shaped",
      rates.data && rates.data.status === "ok" && Array.isArray(rates.data.data),
    );

    const login = await fetch(`http://127.0.0.1:${PORT}/login.html`);
    const loginHtml = await login.text();
    check(
      "L9",
      "login.html references Default-Banner + FastFi CGI client",
      login.ok &&
        loginHtml.includes("Default-Banner.png") &&
        loginHtml.includes("fastfi-cgi.js"),
    );
  } finally {
    child.kill("SIGTERM");
  }

  const failed = rows.filter((r) => !r.pass);
  console.log("\n----------------------------------------");
  console.log(`Checklist: ${rows.length - failed.length}/${rows.length} passed`);
  if (failed.length) {
    console.log("Failed items:");
    failed.forEach((f) => console.log(`  - [${f.id}] ${f.title}`));
  }
  console.log(failed.length ? "RESULT: FAIL" : "RESULT: PASS");
  process.exit(failed.length ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  console.log("RESULT: FAIL");
  process.exit(1);
});
