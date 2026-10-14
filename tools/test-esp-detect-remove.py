"""Detect/Remove contract tests. Synthetic keys only. Does not touch seller private key."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "esp-license-provisioner"))

from app.crypto_license import canonical_payload, ensure_keypair, issue_license  # noqa: E402
from app.crypto_license import _load_private  # noqa: E402
import base64


def to_wsl(path: Path) -> str:
    s = str(path.resolve()).replace("\\", "/")
    if len(s) >= 2 and s[1] == ":":
        return "/mnt/" + s[0].lower() + s[2:]
    return s


def dump(directory: Path, name: str, obj: dict) -> None:
    text = json.dumps(obj, separators=(",", ":"))
    (directory / name).write_bytes(text.encode("utf-8"))


def signed_copy(priv: Path, **fields) -> dict:
    body = {k: v for k, v in fields.items() if k not in ("sig", "sig_b64")}
    sig = _load_private(priv).sign(canonical_payload(body))
    body["sig_b64"] = base64.b64encode(sig).decode("ascii")
    return body


def main() -> int:
    prod = ROOT / "esp-license-provisioner" / "keys" / "issuer_ed25519.pem"
    td = Path(tempfile.mkdtemp(prefix="ksk-detect-remove-"))
    try:
        priv = td / "test_ed25519.pem"
        pub = td / "test_ed25519.pub.pem"
        ensure_keypair(priv, pub)
        if prod.exists() and priv.read_bytes() == prod.read_bytes():
            print("FAIL: test key matched the seller private key")
            return 1

        lic = issue_license(
            private_key_path=priv,
            chip_id="AABBCCDDEE10",
            mac="AA:BB:CC:DD:EE:10",
            plan="standard",
            issuer="KonekSik-Fi-Test",
            lifetime_days=0,
            license_id="KSK-TESTAABBCCDDEE10",
        )
        dump(td, "valid.json", lic)

        bad = json.loads(json.dumps(lic))
        sig = bad["sig_b64"]
        bad["sig_b64"] = ("A" if sig[0] != "A" else "B") + sig[1:]
        dump(td, "bad_sig.json", bad)

        past = int(time.time()) - 3600
        expired = signed_copy(
            priv,
            v=1,
            type="esp_coinslot",
            license_id="KSK-TESTAABBCCDDEE10",
            chip_id="AABBCCDDEE10",
            mac="AA:BB:CC:DD:EE:10",
            plan="standard",
            issuer="KonekSik-Fi-Test",
            issued_at=past - 86400,
            expires_at=past,
            grace_max=3,
        )
        dump(td, "expired.json", expired)
        (td / "expired.now").write_bytes((str(past) + "\n").encode("ascii"))

        # Also prove Seller License Generator .ksk wrapper contains signed license fields.
        from app.crypto_license import export_replacement_bundle

        bundle_path = export_replacement_bundle(lic, td / "sample.ksk")
        bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
        inner = bundle.get("license") or {}
        for key in ("license_id", "chip_id", "mac", "type", "expires_at", "grace_max", "sig_b64"):
            if key not in inner:
                print(f"FAIL: .ksk missing {key}")
                return 1
        print("PASS: seller .ksk bundle contains signed license fields")

        # Static UI: Register ID control must be gone; Load→Verify→Bind present.
        admin_html = (
            ROOT
            / "EXTRACTED-OPENWRT-FASTFI-V2.5.1"
            / "rootfs"
            / "www"
            / "admin.html"
        ).read_text(encoding="utf-8", errors="replace")
        admin_ext = (
            ROOT
            / "EXTRACTED-OPENWRT-FASTFI-V2.5.1"
            / "rootfs"
            / "www"
            / "admin-ext.js"
        ).read_text(encoding="utf-8", errors="replace")
        if "Register ID" in admin_html or "addLicenseToPool()" in admin_html:
            print("FAIL: Register ID UI still present in admin.html")
            return 1
        if "btnVerifyEspKsk" not in admin_html or "btnBindEspKsk" not in admin_html:
            print("FAIL: Verify/Bind buttons missing in admin.html")
            return 1
        if "verifyEspKskCompatibility" not in admin_ext or "bindEspKsk" not in admin_ext:
            print("FAIL: verify/bind handlers missing in admin-ext.js")
            return 1
        if "esp_license_verify" not in admin_ext:
            print("FAIL: esp_license_verify not called from admin-ext.js")
            return 1
        if "ff-action-btns" not in admin_ext:
            print("FAIL: action button spacing class missing")
            return 1
        if admin_ext.count("Unbind") < 1 or '">Bind</button>' not in admin_ext:
            # State-aware single actions exist in licensed table renderer
            if "unbindKskLicense" not in admin_ext or "focusBindEspWorkflow" not in admin_ext:
                print("FAIL: state-aware Bind/Unbind helpers missing")
                return 1
        print("PASS: Register ID UI removed; Load->Verify->Bind UI present")

        # Delete lifecycle UI contract (Registered ESP32 Devices path).
        if "delete_esp_device" not in admin_ext:
            print("FAIL: delete_esp_device API missing from admin-ext.js")
            return 1
        if "REQUIRES_UNBIND" not in admin_ext:
            print("FAIL: REQUIRES_UNBIND handling missing from deleteESPDevice")
            return 1
        if "force=1&confirm_unbind=1" not in admin_ext:
            print("FAIL: force+confirm_unbind query missing from deleteESPDevice")
            return 1
        if "Unbind and Delete" not in admin_ext:
            print("FAIL: licensed Unbind-and-Delete confirm copy missing")
            return 1
        if "Delete cancelled — Unbind required" not in admin_ext:
            print("FAIL: cancel toast for REQUIRES_UNBIND missing")
            return 1
        # Success toast only after status===ok; both tables must refresh.
        del_fn_start = admin_ext.find("window.deleteESPDevice")
        del_fn_end = admin_ext.find("window.removeESPDevice", del_fn_start)
        del_body = admin_ext[del_fn_start:del_fn_end] if del_fn_start >= 0 and del_fn_end > del_fn_start else ""
        if 'd.status !== "ok"' not in del_body and "d.status !== 'ok'" not in del_body:
            print("FAIL: deleteESPDevice must gate success on status===ok")
            return 1
        if "loadESPDevices()" not in del_body or "loadLicensePool()" not in del_body:
            print("FAIL: deleteESPDevice must refresh Registered + Licensed tables")
            return 1
        if "looksBound" not in del_body:
            print("FAIL: licensed-row force path (looksBound) missing")
            return 1
        # Button wiring must pass license meta so soft delete is not the first attempt.
        if "deleteESPDevice(" not in admin_ext or "delMeta" not in admin_ext:
            print("FAIL: Registered ESP Delete button must pass delMeta license")
            return 1
        if "?v=46" not in admin_html and "admin-ext.js?v=46" not in admin_html:
            print("FAIL: admin.html must cache-bust admin-ext.js at v=46+")
            return 1
        # Backend must use transactions for multi-record delete/unbind.
        esp_lua = (
            ROOT
            / "EXTRACTED-OPENWRT-FASTFI-V2.5.1"
            / "rootfs"
            / "usr/lib/lua/fastfi/api/routes/esp.lua"
        ).read_text(encoding="utf-8", errors="replace")
        esp_lic_lua = (
            ROOT
            / "EXTRACTED-OPENWRT-FASTFI-V2.5.1"
            / "rootfs"
            / "usr/lib/lua/fastfi/api/routes/esp_license.lua"
        ).read_text(encoding="utf-8", errors="replace")
        sqlite_lua = (
            ROOT
            / "EXTRACTED-OPENWRT-FASTFI-V2.5.1"
            / "rootfs"
            / "usr/lib/lua/fastfi/db/sqlite.lua"
        ).read_text(encoding="utf-8", errors="replace")
        if "sqlite.transaction" not in esp_lua:
            print("FAIL: delete_esp_device must use sqlite.transaction")
            return 1
        if "sqlite.transaction" not in esp_lic_lua:
            print("FAIL: esp_license.unbind must use sqlite.transaction")
            return 1
        if "function M.transaction" not in sqlite_lua or "BEGIN IMMEDIATE" not in sqlite_lua:
            print("FAIL: sqlite.transaction helper missing BEGIN IMMEDIATE")
            return 1
        if "REQUIRES_UNBIND" not in esp_lua:
            print("FAIL: REQUIRES_UNBIND gate missing from delete_esp_device")
            return 1
        print("PASS: Delete lifecycle UI+API contract (force, REQUIRES_UNBIND, txn, dual refresh)")

        lua_src = ROOT / "tools" / "test-esp-detect-remove.lua"
        lua_src.write_bytes(lua_src.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n"))
        for rel in (
            "usr/lib/lua/fastfi/license/ksk_verify.lua",
            "usr/lib/lua/fastfi/api/routes/esp_license.lua",
            "usr/lib/lua/fastfi/api/routes/esp.lua",
            "usr/libexec/fastfi/services/koneksik-ksk-verify.sh",
        ):
            p = ROOT / "EXTRACTED-OPENWRT-FASTFI-V2.5.1" / "rootfs" / rel
            if p.exists():
                p.write_bytes(p.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n"))

        rootfs = ROOT / "EXTRACTED-OPENWRT-FASTFI-V2.5.1" / "rootfs"
        runner = td / "run.sh"
        runner.write_bytes(
            f"""#!/bin/sh
set -e
export PATH="/home/clare/bin:$PATH"
FIX="{to_wsl(td)}"
ROOT="{to_wsl(rootfs)}"
export KSK_FIXTURE_DIR="$FIX"
export LUA_PATH="$ROOT/usr/lib/lua/?.lua;$ROOT/usr/lib/lua/?/init.lua;;"
export KONEKSIK_KSK_PUBKEY="{to_wsl(pub)}"
export KONEKSIK_KSK_VERIFY="{to_wsl(rootfs / 'usr/libexec/fastfi/services/koneksik-ksk-verify.sh')}"
mkdir -p /etc/fastfi 2>/dev/null || true
cd "$FIX"
lua5.1 "{to_wsl(lua_src)}"
""".encode(
                "utf-8"
            )
        )

        proc = subprocess.run(
            ["wsl", "-e", "bash", to_wsl(runner)],
            cwd=str(ROOT),
            capture_output=True,
            text=True,
        )
        sys.stdout.write(proc.stdout or "")
        sys.stderr.write(proc.stderr or "")
        if proc.returncode != 0:
            print(f"FAIL: lua detect/remove tests exit {proc.returncode}")
            return 1
        print("ESP DETECT/REMOVE PYTHON DRIVER PASS")
        return 0
    finally:
        shutil.rmtree(td, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
