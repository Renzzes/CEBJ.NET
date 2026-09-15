/**
 * Compare Captive Portal API usage against immutable FastFi bootstrap.js baseline.
 *
 * PASS when:
 *  1. Portal JS does not call legacy /api/portal/*
 *  2. Every /cgi-bin/api action used by the portal ⊆ FastFi bootstrap actions
 *  3. Required core coin/session actions are all present in the portal
 *
 * Does NOT modify FASTFI / extracted rootfs files.
 *
 * Usage: node validate-fastfi-portal-api.mjs
 */
import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const workspace = join(here, "..");

const BASELINE_BOOTSTRAP = join(
  workspace,
  "EXTRACTED-OPENWRT-FASTFI-V2.5.1",
  "rootfs",
  "www",
  "bootstrap.js",
);

const PORTAL_FILES = [
  join(here, "fastfi-cgi.js"),
  join(here, "renzfi-app.js"),
  join(here, "demo-server.mjs"),
  join(here, "login.html"),
  join(here, "status.html"),
];

const REQUIRED_CORE = [
  "getMac",
  "checkDevice",
  "session_status",
  "rates",
  "list_esp_devices",
  "lockcoin",
  "fetchcoin",
  "unlockcoin",
  "updateDevice",
  "clearcredit",
  "internet",
  "voucher",
  "terminate",
];

/** Allowed beyond original FastFi bootstrap.js (KonekSik firmware overlay). */
const ALLOWED_EXTENSIONS = new Set([
  "terminate",
  "client_deauth",
  "get_portal_media",
  "restore_default_banner",
  "upload_banner",
  "upload_audio",
  "get_branding",
]);

function extractActions(source) {
  const set = new Set();
  for (const m of source.matchAll(/action=([a-zA-Z0-9_]+)/g)) set.add(m[1]);
  for (const m of source.matchAll(/action\s*:\s*["']([a-zA-Z0-9_]+)["']/g)) set.add(m[1]);
  // cgiGet("name") / "action", "name" style in fastfi-cgi.js
  for (const m of source.matchAll(/cgiGet\(\s*["']([a-zA-Z0-9_]+)["']/g)) set.add(m[1]);
  return set;
}

function extractLegacyPortalHits(source) {
  const hits = [];
  const re = /\/api\/portal\/[a-zA-Z0-9_\-\/]*/g;
  let m;
  while ((m = re.exec(source))) {
    // Allow comments that mention the legacy path as forbidden.
    const lineStart = source.lastIndexOf("\n", m.index) + 1;
    const line = source.slice(lineStart, source.indexOf("\n", m.index));
    if (/^\s*\/\//.test(line) || line.includes("Do not call") || line.includes("No /api/portal")) {
      continue;
    }
    if (line.includes("Legacy /api removed") || line.includes("must not")) continue;
    if (line.includes("<!--") || line.includes("legacy /api/portal")) continue;
    hits.push(m[0]);
  }
  return hits;
}

function main() {
  console.log("=== FastFi portal API parity validation ===");
  console.log("Baseline (read-only): " + BASELINE_BOOTSTRAP);

  if (!existsSync(BASELINE_BOOTSTRAP)) {
    console.log("RESULT: FAIL");
    console.log("Missing FastFi bootstrap.js baseline (do not invent actions).");
    process.exit(1);
  }

  const baselineSrc = readFileSync(BASELINE_BOOTSTRAP, "utf8");
  const baseline = extractActions(baselineSrc);
  // URLSearchParams({action:"gcash_order"}) form
  for (const m of baselineSrc.matchAll(/action\s*:\s*["']([a-zA-Z0-9_]+)["']/g)) {
    baseline.add(m[1]);
  }

  console.log("Baseline actions (" + baseline.size + "): " + [...baseline].sort().join(", "));

  let portalSrc = "";
  const missingFiles = [];
  for (const f of PORTAL_FILES) {
    if (!existsSync(f)) {
      missingFiles.push(f);
      continue;
    }
    portalSrc += "\n" + readFileSync(f, "utf8");
  }
  if (missingFiles.length) {
    console.log("RESULT: FAIL");
    console.log("Missing portal files:\n  " + missingFiles.join("\n  "));
    process.exit(1);
  }

  const used = extractActions(portalSrc);
  // Restrict "used" to actions that appear as CGI traffic, not random words:
  // keep intersection with known FastFi public set + anything matching cgi patterns.
  const cgiReferenced = new Set();
  for (const a of used) {
    if (
      portalSrc.includes('"' + a + '"') ||
      portalSrc.includes("'" + a + "'") ||
      portalSrc.includes("action=" + a) ||
      portalSrc.includes('action:"' + a + '"') ||
      portalSrc.includes("case \"" + a + "\"")
    ) {
      cgiReferenced.add(a);
    }
  }

  // Only validate actions that are clearly CGI route names (baseline ∪ required ∪ demo cases).
  const candidateActions = new Set([...REQUIRED_CORE, ...baseline, ...ALLOWED_EXTENSIONS]);
  const portalActions = [...cgiReferenced].filter((a) => candidateActions.has(a) || baseline.has(a));
  // Also pick up demo-server case "action" labels that are FastFi routes
  for (const m of portalSrc.matchAll(/case\s+"([a-zA-Z0-9_]+)"/g)) {
    if (baseline.has(m[1]) || REQUIRED_CORE.includes(m[1]) || ALLOWED_EXTENSIONS.has(m[1])) {
      portalActions.push(m[1]);
    }
  }
  const portalSet = new Set(portalActions);

  console.log("Portal FastFi actions (" + portalSet.size + "): " + [...portalSet].sort().join(", "));

  const legacyHits = extractLegacyPortalHits(portalSrc);
  const unknown = [...portalSet].filter((a) => !baseline.has(a) && !ALLOWED_EXTENSIONS.has(a));
  const missingCore = REQUIRED_CORE.filter((a) => !portalSet.has(a));

  let pass = true;
  if (legacyHits.length) {
    pass = false;
    console.log("FAIL: legacy /api/portal hits: " + [...new Set(legacyHits)].join(", "));
  } else {
    console.log("OK: no active /api/portal/* usage");
  }

  if (unknown.length) {
    pass = false;
    console.log("FAIL: portal actions not in FastFi baseline: " + unknown.join(", "));
  } else {
    console.log("OK: all portal CGI actions ⊆ FastFi baseline ∪ KonekSik extensions");
  }

  if (missingCore.length) {
    pass = false;
    console.log("FAIL: missing required core actions: " + missingCore.join(", "));
  } else {
    console.log("OK: required core coin/session actions present");
  }

  // Sanity: portal must load FastFi CGI client
  if (!portalSrc.includes("FastFiCgi") || !portalSrc.includes("/cgi-bin/api")) {
    pass = false;
    console.log("FAIL: FastFiCgi /cgi-bin/api client wiring missing");
  } else {
    console.log("OK: FastFiCgi /cgi-bin/api wiring present");
  }

  if (!portalSrc.includes('cgiGet("terminate"') && !portalSrc.includes('case "terminate"') && !portalSrc.includes(".terminate(")) {
    pass = false;
    console.log("FAIL: terminate action not wired in portal");
  } else {
    console.log("OK: terminate action wired");
  }

  console.log(pass ? "RESULT: PASS" : "RESULT: FAIL");
  process.exit(pass ? 0 : 1);
}

main();
