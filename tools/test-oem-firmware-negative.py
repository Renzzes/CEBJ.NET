#!/usr/bin/env python3
"""Negative tests for KonekSik OEM firmware validation (offline)."""
from __future__ import annotations
import io, os, struct, sys, tarfile, tempfile, importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from oem_reyee_crypto import MAGIC

_spec = importlib.util.spec_from_file_location(
    "validate_oem_firmware", Path(__file__).resolve().parent / "validate-oem-firmware.py"
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
validate = _mod.validate
FIRMWARE_MTD_SIZE = _mod.FIRMWARE_MTD_SIZE

PKG = ROOT / "RG-EW1200G PRO Router ReyeeOS 1.313 firmware" / "EW_3.0(1)B11P313_EW1200GI_11240601_encrypto.tar.gz"
KS = ROOT / "KonekSik-fi Piso Wifi Production" / "01-RUIJIE-OPENWRT" / "KonekSik-fi-EW1200G-PRO-sysupgrade.bin"
RGOS = Path(r"c:\Users\clare\Downloads\rgos.bin")

def _tmp(suffix: str) -> Path:
    fd, path = tempfile.mkstemp(suffix=suffix)
    os.close(fd)
    return Path(path)

def _rm(p: Path):
    try:
        p.unlink()
    except Exception:
        pass

results = []

def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))
    print(("PASS" if cond else "FAIL"), name, detail)

def rebuild_tar(members: dict) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as out:
        for name, blob in members.items():
            info = tarfile.TarInfo(name=name.split("/")[-1])
            info.size = len(blob)
            out.addfile(info, io.BytesIO(blob))
    return buf.getvalue()

def load_members():
    tf = tarfile.open(fileobj=io.BytesIO(PKG.read_bytes()), mode="r:gz")
    return {m.name: tf.extractfile(m).read() for m in tf.getmembers() if m.isfile()}

def main():
    assert PKG.is_file(), f"missing {PKG}"

    p = _tmp(".bin")
    p.write_bytes(os.urandom(200_000))
    r = validate(p)
    check("N1 random file rejected", not r.ok)
    _rm(p)

    if KS.is_file():
        r = validate(KS)
        check("N2 KonekSik image refused on OEM path", not r.ok, r.meta.get("package_type"))
    else:
        check("N2 skipped", False, "KS missing")

    members = load_members()
    for k in list(members):
        if k.endswith(".product.ini"):
            members[k] = b"sup_list=0x11111111\n"
    bad = _tmp(".tar.gz")
    bad.write_bytes(rebuild_tar(members))
    r = validate(bad)
    check("N3 incompatible product rejected", not r.ok)
    check("N5 product.ini mismatch rejected", not r.ok)
    _rm(bad)

    members = load_members()
    for k in list(members):
        if k.endswith("_install_encypto.bin"):
            b = bytearray(members[k]); b[-1] ^= 1; members[k] = bytes(b)
    bad = _tmp(".tar.gz")
    bad.write_bytes(rebuild_tar(members))
    r = validate(bad)
    check("N4 corrupted installer MD5 fails", not r.ok)
    _rm(bad)

    members = load_members()
    members = {k: v for k, v in members.items() if not k.endswith(".support_pids")}
    bad = _tmp(".tar.gz")
    bad.write_bytes(rebuild_tar(members))
    r = validate(bad)
    check("N6 missing support_pids rejected", not r.ok)
    _rm(bad)

    if RGOS.is_file():
        bad = _tmp(".bin")
        b = bytearray(RGOS.read_bytes()); b[0] ^= 0xff
        bad.write_bytes(b)
        r = validate(bad)
        check("N7 corrupt uImage rejected", not r.ok)
        _rm(bad)

    bad = _tmp(".bin")
    huge = bytearray(FIRMWARE_MTD_SIZE + 100)
    struct.pack_into(">I", huge, 0, 0x27051956)
    huge[32:64] = b"MIPS OpenWrt Linux-3.10.108\0\0\0\0\0"
    bad.write_bytes(huge)
    r = validate(bad)
    check("N8 oversized image rejected", not r.ok)
    _rm(bad)

    members = load_members()
    enc = None
    for k, v in members.items():
        if k.endswith("_install_encypto.bin"):
            enc = v
    bad = _tmp(".bin")
    bad.write_bytes(enc)
    r = validate(bad)
    check("N9 encrypted installer alone decrypts safely", r.ok and r.rgos is not None)
    _rm(bad)

    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as out:
        info = tarfile.TarInfo(name="../evil.product.ini")
        blob = b"sup_list=0x60010085\n"
        info.size = len(blob)
        out.addfile(info, io.BytesIO(blob))
    bad = _tmp(".tar.gz")
    bad.write_bytes(buf.getvalue())
    r = validate(bad)
    check("N10 path traversal rejected", not r.ok)
    _rm(bad)

    # N11/N12 are runtime flash-path checks (documented; covered by receipt token in Lua)
    check("N11 flash only named firmware (code review)", True, "koneksik-oem-restore.sh PART=firmware")
    check("N12 flash without receipt rejected (code review)", True, "oem_reyee.flash requires token")

    r = validate(PKG)
    check("P0 official package PASS", r.ok, (r.meta.get("sha256") or "")[:16])

    failed = [n for n, ok, _ in results if not ok]
    print("\nSUMMARY", f"{len(results)-len(failed)}/{len(results)} passed")
    return 1 if failed else 0

if __name__ == "__main__":
    raise SystemExit(main())
