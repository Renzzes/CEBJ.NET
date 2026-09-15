#!/usr/bin/env python3
"""Headless verify: imports, crypto, UI construct/destroy for all 3 apps."""
from __future__ import annotations

import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

pass_n = 0
fail_n = 0


def check(name: str, ok: bool, detail: str = "") -> None:
    global pass_n, fail_n
    if ok:
        pass_n += 1
        print(f"PASS  {name}" + (f" — {detail}" if detail else ""))
    else:
        fail_n += 1
        print(f"FAIL  {name}" + (f" — {detail}" if detail else ""))


def main() -> int:
    # --- Crypto path used by Generator + Flasher ---
    from app.crypto_license import (
        ensure_keypair,
        export_replacement_bundle,
        issue_license,
        load_replacement_bundle,
        license_to_provision_line,
        verify_license,
    )

    td = Path(tempfile.mkdtemp())
    priv, pub = ensure_keypair(td / "a.pem", td / "b.pem")
    lic = issue_license(
        private_key_path=priv,
        chip_id="VERIFYCHIP01",
        mac="AA:BB:CC:DD:EE:01",
        plan="standard",
        issuer="verify",
    )
    check("crypto issue+verify", verify_license(lic, pub) and str(lic.get("license_id", "")).startswith("KSK-"))
    bundle = export_replacement_bundle(lic, td / "t.ksk")
    lic2 = load_replacement_bundle(bundle)
    check("crypto .ksk roundtrip", lic2.get("license_id") == lic["license_id"])
    line = license_to_provision_line(lic)
    check("serial provision line", line.startswith("KSK_LICENSE_WRITE ") and len(line) > 40)

    # --- Module imports ---
    from app import boards, flasher, serial_provision, ui_theme  # noqa: F401
    from app.main import ProvisionerApp
    from app.license_generator_app import LicenseGeneratorApp
    from app.buyer_replacement_app import BuyerReplacementApp

    check("boards profiles", len(boards.list_profiles()) >= 1)
    check("serial list_ports callable", callable(serial_provision.list_serial_ports))
    check("flash_firmware callable", callable(flasher.flash_firmware))

    # --- UI construct (withdraw) for each app ---
    for name, Cls in (
        ("UI ESP Flasher", ProvisionerApp),
        ("UI License Generator", LicenseGeneratorApp),
        ("UI Buyer Replacement", BuyerReplacementApp),
    ):
        try:
            app = Cls()
            app.withdraw()
            # Force a geometry update so widgets realize
            app.update_idletasks()
            title = app.title()
            kids = app.winfo_children()
            app.destroy()
            check(name, len(kids) >= 1, title)
        except Exception as e:
            check(name, False, str(e))

    # --- Buyer can load sealed bundle without private key ---
    try:
        loaded = load_replacement_bundle(bundle)
        check("buyer load sealed only", "sig_b64" in loaded or "sig" in loaded)
    except Exception as e:
        check("buyer load sealed only", False, str(e))

    print("----------------------------------------")
    print(f"Verify: {pass_n}/{pass_n + fail_n} passed")
    return 0 if fail_n == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
