#!/usr/bin/env node
/**
 * E2E checklist for KonekSik offline ESP licensing (no cloud pool).
 * Verifies files, UI strings, Lua/API wiring, crypto bundle, grace rules (simulated).
 */
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const www = join(root, "EXTRACTED-OPENWRT-FASTFI-V2.5.1", "rootfs", "www");
const lua = join(root, "EXTRACTED-OPENWRT-FASTFI-V2.5.1", "rootfs", "usr", "lib", "lua", "fastfi");
const prov = join(root, "esp-license-provisioner");
const esp = join(root, "esp-coinslot");

let pass = 0;
let fail = 0;
const rows = [];

function check(id, title, ok, detail = "") {
  if (ok) {
    pass++;
    rows.push(`PASS  [${id}] ${title}${detail ? " — " + detail : ""}`);
  } else {
    fail++;
    rows.push(`FAIL  [${id}] ${title}${detail ? " — " + detail : ""}`);
  }
}

function read(p) {
  return readFileSync(p, "utf8");
}

// --- UI ---
const admin = read(join(www, "admin.html"));
check("U1", "License Pool Manager removed", !admin.includes("License Pool Manager"));
check("U2", "ESP32 Licensed Devices present", admin.includes("ESP32 Licensed Devices"));
check("U3", "Detect ESP32 UI present", admin.includes("Detect ESP32") && admin.includes("detectEspMac"));
check("U4", "Registered ESP32 Devices title", admin.includes("Registered ESP32 Devices"));
check("U5", "How It Works offline / grace copy", admin.includes("Grace (max 3)") && admin.includes("replacement flasher"));
check("U6", "admin-ext detectESP32 override", read(join(www, "admin-ext.js")).includes("window.detectESP32"));

// --- Lua / API ---
const lic = read(join(lua, "api", "routes", "esp_license.lua"));
const espR = read(join(lua, "api", "routes", "esp.lua"));
const router = read(join(lua, "api", "router.lua"));
const initDb = read(join(lua, "db", "init.lua"));
check("L1", "esp_license.detect grace max 3", lic.includes("GRACE_MAX = 3") && lic.includes("function M.detect"));
check("L2", "No FastFi cloud URL in esp_license add", !lic.includes("fastfi.cloud"));
check("L3", "router wires esp_detect", router.includes("esp_detect = esp_license_routes.detect"));
check("L4", "register_esp_slot accepts license_id", espR.includes("license_id") && espR.includes("esp_license.detect"));
check("L5", "DB grace columns migrated", initDb.includes("grace_used") && initDb.includes("live_mac"));
check("L6", "lockcoin still requires licensed", espR.includes('license_status ~= "free"') || espR.includes("Slot not licensed"));

// --- Provisioner apps ---
check("P1", "crypto export/load replacement bundle", read(join(prov, "app", "crypto_license.py")).includes("export_replacement_bundle"));
check("P2", "license_id in issue_license", read(join(prov, "app", "crypto_license.py")).includes("license_id"));
check("P3", "Seller License Generator app", existsSync(join(prov, "app", "license_generator_app.py")));
check("P4", "Buyer Replacement Flasher app", existsSync(join(prov, "app", "buyer_replacement_app.py")));
check("P5", "START-LICENSE-GENERATOR.bat", existsSync(join(prov, "START-LICENSE-GENERATOR.bat")));
check("P6", "START-BUYER-REPLACEMENT-FLASHER.bat", existsSync(join(prov, "START-BUYER-REPLACEMENT-FLASHER.bat")));
check("P7", "Seller flasher exports .ksk bundles", read(join(prov, "app", "main.py")).includes("export_replacement_bundle"));

// --- ESP firmware ---
const mainCpp = read(join(esp, "src", "main.cpp"));
const serialCpp = read(join(esp, "src", "license_serial.cpp"));
check("E1", "ESP gates coin pulses without license", mainCpp.includes("licenseStoreHas()") && mainCpp.includes("return;"));
check("E2", "ESP KSK_LICENSE_ID? command", serialCpp.includes("KSK_LICENSE_ID?"));

// --- Crypto + grace simulation (Python) ---
const py = `
import json, sys, tempfile
from pathlib import Path
sys.path.insert(0, r${JSON.stringify(prov)})
from app.crypto_license import ensure_keypair, issue_license, verify_license, export_replacement_bundle, load_replacement_bundle

td = Path(tempfile.mkdtemp())
priv, pub = ensure_keypair(td/"a.pem", td/"b.pem")
lic = issue_license(private_key_path=priv, chip_id="AABBCCDDEEFF", mac="AA:BB:CC:DD:EE:FF", plan="standard", issuer="test")
assert lic.get("license_id","").startswith("KSK-"), lic
assert verify_license(lic, pub)
b = export_replacement_bundle(lic, td/"x.ksk")
lic2 = load_replacement_bundle(b)
assert lic2["license_id"] == lic["license_id"]
assert lic2["sig_b64"] == lic["sig_b64"]

# Grace rule simulation (mirrors Lua)
def detect(state, mac, lid):
    grace_used = state.get("grace_used", 0)
    grace_max = 3
    live = state.get("live_mac", "")
    if live and live != mac:
        if grace_used >= grace_max:
            return False, grace_used, "limit"
        grace_used += 1
    state["live_mac"] = mac
    state["grace_used"] = grace_used
    state["lid"] = lid
    return True, grace_used, "ok"

st = {}
assert detect(st, "AA:11:22:33:44:01", "KSK-X")[0]
assert detect(st, "AA:11:22:33:44:02", "KSK-X")[1] == 1
assert detect(st, "AA:11:22:33:44:03", "KSK-X")[1] == 2
assert detect(st, "AA:11:22:33:44:04", "KSK-X")[1] == 3
ok, gu, why = detect(st, "AA:11:22:33:44:05", "KSK-X")
assert not ok and why == "limit" and gu == 3
print("CRYPTO_GRACE_OK")
`;

function runPython(code) {
  const candidates =
    process.platform === "win32"
      ? [
          ["py", ["-3", "-c", code]],
          ["python", ["-c", code]],
          ["python3", ["-c", code]],
        ]
      : [
          ["python3", ["-c", code]],
          ["python", ["-c", code]],
        ];
  let last = { status: 1, stdout: "", stderr: "no python launcher found" };
  for (const [bin, args] of candidates) {
    const r = spawnSync(bin, args, { encoding: "utf8", cwd: prov, shell: false });
    last = r;
    if (r.error && r.error.code === "ENOENT") continue;
    if (r.status === 0 && (r.stdout || "").includes("CRYPTO_GRACE_OK")) return r;
    // Prefer a runner that at least started (not missing binary)
    if (!r.error) last = r;
  }
  return last;
}

const pyRun = runPython(py);
check(
  "C1",
  "Crypto bundle + grace≤3 simulation",
  pyRun.status === 0 && (pyRun.stdout || "").includes("CRYPTO_GRACE_OK"),
  pyRun.status !== 0 ? (pyRun.stderr || pyRun.stdout || "").slice(0, 200) : "",
);

// --- Preview mocks ---
const preview = read(join(www, "ui-preview.js"));
check("V1", "ui-preview mocks esp_detect", preview.includes('case "esp_detect"'));
check("V2", "ui-preview mocks esp_license_list", preview.includes('case "esp_license_list"'));

console.log("=== KonekSik ESP offline license checklist ===\n");
rows.forEach((r) => console.log(r));
console.log("\n----------------------------------------");
console.log(`Checklist: ${pass}/${pass + fail} passed`);
console.log(fail === 0 ? "RESULT: PASS" : "RESULT: FAIL");
process.exit(fail === 0 ? 0 : 1);
