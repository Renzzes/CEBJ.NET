/**
 * Validate terminate on captive portal + admin paths.
 * Runs static checks and a live demo CGI exercise.
 *
 * Usage: node validate-terminate.mjs
 */
import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const workspace = join(here, "..");
const rootfs = join(workspace, "EXTRACTED-OPENWRT-FASTFI-V2.5.1", "rootfs");
const PORT = 4191;

const checks = [];
function ok(name, detail) {
  checks.push({ name, pass: true, detail });
  console.log("OK: " + name + (detail ? " — " + detail : ""));
}
function fail(name, detail) {
  checks.push({ name, pass: false, detail });
  console.log("FAIL: " + name + (detail ? " — " + detail : ""));
}

function read(p) {
  return existsSync(p) ? readFileSync(p, "utf8") : "";
}

async function sleep(ms) {
  await new Promise((r) => setTimeout(r, ms));
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
  return { status: res.status, data };
}

async function main() {
  console.log("=== Terminate validation (portal + admin) ===");

  const portalLua = read(join(rootfs, "usr/lib/lua/fastfi/api/routes/portal.lua"));
  const routerLua = read(join(rootfs, "usr/lib/lua/fastfi/api/router.lua"));
  const sessionsLua = read(join(rootfs, "usr/lib/lua/fastfi/api/routes/sessions.lua"));
  const adminJs = read(join(rootfs, "www/admin.js"));
  const portalApp = read(join(here, "renzfi-app.js"));
  const cgiClient = read(join(here, "fastfi-cgi.js"));
  const demo = read(join(here, "demo-server.mjs"));

  if (/function\s+M\.terminate\s*\(/.test(portalLua)) {
    ok("firmware portal.lua M.terminate");
  } else {
    fail("firmware portal.lua M.terminate", "handler missing");
  }

  if (/terminate\s*=\s*portal_routes\.terminate/.test(routerLua) && /terminate\s*=\s*true/.test(routerLua)) {
    ok("firmware router public terminate route");
  } else {
    fail("firmware router public terminate route");
  }

  if (/function\s+M\.deauth_client\s*\(/.test(sessionsLua) && /client_deauth\s*=\s*session_routes\.deauth_client/.test(routerLua)) {
    ok("firmware admin client_deauth route");
  } else {
    fail("firmware admin client_deauth route");
  }

  if (adminJs.includes("action=client_deauth") && adminJs.includes("function kickClient")) {
    ok("admin.js kickClient → client_deauth");
  } else {
    fail("admin.js kickClient → client_deauth");
  }

  if (adminJs.includes('data.status!=="ok"') || adminJs.includes("data.status!==\"ok\"")) {
    ok("admin.js terminate checks API status");
  } else {
    fail("admin.js terminate checks API status", "still fire-and-forget success toast?");
  }

  if (cgiClient.includes('cgiGet("terminate"') && portalApp.includes(".terminate(")) {
    ok("captive portal terminateSessionAPI → action=terminate");
  } else {
    fail("captive portal terminateSessionAPI → action=terminate");
  }

  if (portalApp.includes("canTerminate: remaining > 0") || portalApp.includes("canTerminate:remaining>0")) {
    ok("captive portal enables Terminate button when session active");
  } else if (portalApp.includes("canTerminate: true") || /canTerminate:\s*remaining\s*>\s*0/.test(portalApp)) {
    ok("captive portal enables Terminate button when session active");
  } else {
    fail("captive portal enables Terminate button when session active");
  }

  if (demo.includes('case "terminate"') && demo.includes('case "client_deauth"')) {
    ok("demo-server mocks terminate + client_deauth");
  } else {
    fail("demo-server mocks terminate + client_deauth");
  }

  // Live CGI exercise against demo-server
  const child = spawn(process.execPath, [join(here, "demo-server.mjs")], {
    env: { ...process.env, KONEKSIK_PORTAL_PORT: String(PORT), KONEKSIK_PORTAL_NO_OPEN: "1" },
    stdio: ["ignore", "pipe", "pipe"],
  });

  let booted = false;
  try {
    for (let i = 0; i < 40; i++) {
      try {
        const probe = await getJson(`http://127.0.0.1:${PORT}/cgi-bin/api?action=getMac`);
        if (probe.status === 200 && probe.data && probe.data.mac) {
          booted = true;
          break;
        }
      } catch {
        /* retry */
      }
      await sleep(100);
    }
    if (!booted) {
      fail("demo-server boot", "did not answer getMac");
    } else {
      ok("demo-server boot");

      const mac = "aa:bb:cc:dd:ee:ff";
      // Grant time via updateDevice
      const grant = await getJson(
        `http://127.0.0.1:${PORT}/cgi-bin/api?action=updateDevice&mac=${mac}&time=600&coin=1&device_id=demo`,
      );
      if (grant.data && grant.data.status === "ok") ok("seed session via updateDevice", "600s");
      else fail("seed session via updateDevice", JSON.stringify(grant.data));

      const before = await getJson(
        `http://127.0.0.1:${PORT}/cgi-bin/api?action=session_status&mac=${mac}&device_id=demo`,
      );
      if (before.data && Number(before.data.remaining) > 0) ok("session active before terminate", String(before.data.remaining));
      else fail("session active before terminate", JSON.stringify(before.data));

      const term = await getJson(
        `http://127.0.0.1:${PORT}/cgi-bin/api?action=terminate&mac=${mac}&device_id=demo`,
      );
      if (term.data && term.data.status === "ok" && Number(term.data.remaining) === 0) {
        ok("portal terminate CGI", term.data.message || "ok");
      } else {
        fail("portal terminate CGI", JSON.stringify(term.data));
      }

      const after = await getJson(
        `http://127.0.0.1:${PORT}/cgi-bin/api?action=session_status&mac=${mac}&device_id=demo`,
      );
      if (after.data && Number(after.data.remaining || 0) === 0 && after.data.status !== "active") {
        ok("session cleared after portal terminate", after.data.status);
      } else {
        fail("session cleared after portal terminate", JSON.stringify(after.data));
      }

      // Re-seed and admin-style client_deauth
      await getJson(
        `http://127.0.0.1:${PORT}/cgi-bin/api?action=updateDevice&mac=${mac}&time=300&coin=1&device_id=demo`,
      );
      const kick = await getJson(
        `http://127.0.0.1:${PORT}/cgi-bin/api?action=client_deauth&mac=${mac}`,
      );
      if (kick.data && kick.data.status === "ok") ok("admin client_deauth CGI", kick.data.message || "ok");
      else fail("admin client_deauth CGI", JSON.stringify(kick.data));

      const afterKick = await getJson(
        `http://127.0.0.1:${PORT}/cgi-bin/api?action=session_status&mac=${mac}&device_id=demo`,
      );
      if (afterKick.data && Number(afterKick.data.remaining || 0) === 0) {
        ok("session cleared after admin deauth");
      } else {
        fail("session cleared after admin deauth", JSON.stringify(afterKick.data));
      }
    }
  } finally {
    child.kill("SIGTERM");
  }

  const failed = checks.filter((c) => !c.pass);
  console.log(failed.length ? "RESULT: FAIL" : "RESULT: PASS");
  console.log(`Checks: ${checks.length - failed.length}/${checks.length} passed`);
  process.exit(failed.length ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  console.log("RESULT: FAIL");
  process.exit(1);
});
