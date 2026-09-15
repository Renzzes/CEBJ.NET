#!/usr/bin/env python3
"""Offline KonekSik OEM ReyeeOS firmware package validator.

Usage:
  python tools/validate-oem-firmware.py path/to/EW_3.0(...)_encrypto.tar.gz
  python tools/validate-oem-firmware.py path/to/rgos.bin
"""
from __future__ import annotations

import argparse
import hashlib
import io
import struct
import sys
import tarfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from oem_reyee_crypto import MAGIC, decrypt_installer  # noqa: E402

EXPECTED_PRODUCT_IDS = {0x60010081, 0x60010082, 0x60010085}
TARGET_PRODUCT_ID = 0x60010085
FIRMWARE_MTD_SIZE = 0xF70000
KNOWN_GOOD_SHA256 = {
    "d2256fc6b4ec45c2cc40ab5f63abe7011313e8b5b45c58d9b42f9d00e528fe2e": "ReyeeOS 1.313.2406 rgos.bin",
}
UIMAGE_MAGIC = 0x27051956
MAX_UPLOAD = 32 * 1024 * 1024


class Result:
    def __init__(self):
        self.checks = []
        self.meta = {}
        self.rgos = None
        self.ok = True

    def add(self, name, passed, evidence=""):
        self.checks.append((name, "PASS" if passed else "FAIL", evidence))
        if not passed:
            self.ok = False


def md5_bytes(b: bytes) -> str:
    return hashlib.md5(b).hexdigest()


def sha256_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def parse_product_ini(text: str):
    ids = set()
    for part in text.replace("\n", ",").split(","):
        part = part.strip()
        if "sup_list=" in part:
            v = part.split("=", 1)[1].strip()
            ids.add(int(v, 0))
    return ids


def support_pids_ok(text: str) -> bool:
    t = text.upper()
    return "EW1200G-PRO" in t


def validate_uimage(rgos: bytes, res: Result):
    if len(rgos) < 64:
        res.add("uImage", False, "too small")
        return
    magic = struct.unpack(">I", rgos[0:4])[0]
    res.add("uImage magic", magic == UIMAGE_MAGIC, f"0x{magic:08x}")
    ih_size = struct.unpack(">I", rgos[12:16])[0]
    name = rgos[32:64].split(b"\0", 1)[0].decode("ascii", "replace")
    res.meta["kernel_name"] = name
    res.meta["ih_size"] = ih_size
    arch = rgos[29]
    # IH_ARCH_MIPS = 5
    res.add("MIPS arch", arch == 5, f"ih_arch={arch}")
    res.add("kernel name", "MIPS" in name and "Linux" in name, name)
    off = 64 + ih_size
    if off + 4 <= len(rgos):
        sq = rgos[off:off + 4]
        res.add("SquashFS marker", sq == b"hsqs", repr(sq))
    else:
        res.add("SquashFS marker", False, "truncated")
    # Reject OpenWrt sysupgrade metadata tail as OEM flash payload confusion
    if b"supported_devices" in rgos[-8192:]:
        res.add("not OpenWrt sysupgrade meta", False, "OpenWrt metadata present — use KonekSik path")
    else:
        res.add("not OpenWrt sysupgrade meta", True, "no fwtool metadata tail")


def validate_rgos(rgos: bytes, res: Result):
    res.rgos = rgos
    res.meta["image_size"] = len(rgos)
    res.add("image size", 0 < len(rgos) <= FIRMWARE_MTD_SIZE, f"{len(rgos)} <= {FIRMWARE_MTD_SIZE}")
    validate_uimage(rgos, res)
    digest = sha256_bytes(rgos)
    res.meta["sha256"] = digest
    if digest in KNOWN_GOOD_SHA256:
        res.add("SHA256 known-good", True, KNOWN_GOOD_SHA256[digest])
    else:
        res.add("SHA256 known-good", True, f"{digest} (not in pin list — structural checks apply)")


def validate_tar_gz(data: bytes, res: Result):
    res.add("Package format", data[:2] == b"\x1f\x8b", "gzip magic" if data[:2] == b"\x1f\x8b" else "not gzip")
    if data[:2] != b"\x1f\x8b":
        return
    try:
        tf = tarfile.open(fileobj=io.BytesIO(data), mode="r:gz")
    except Exception as e:
        res.add("tar parse", False, str(e))
        return
    members = {m.name.split("/")[-1]: m for m in tf.getmembers() if m.isfile()}
    # path traversal
    for m in tf.getmembers():
        n = m.name.replace("\\", "/")
        if n.startswith("/") or ".." in n.split("/"):
            res.add("path traversal", False, m.name)
            return
    res.add("path traversal", True, "safe member names")

    def find_suffix(suf):
        for name, m in members.items():
            if name.endswith(suf):
                return name, m
        return None, None

    checks = {
        "product.ini": ".product.ini",
        "support_pids": ".support_pids",
        "version": ".version",
        "md5": ".md5",
        "encrypted installer": "_install_encypto.bin",
    }
    files = {}
    for label, suf in checks.items():
        name, m = find_suffix(suf)
        ok = m is not None
        res.add(f"member {label}", ok, name or "MISSING")
        if ok:
            files[label] = tf.extractfile(m).read()

    if "product.ini" in files:
        ids = parse_product_ini(files["product.ini"].decode("utf-8", "replace"))
        res.meta["product_ids"] = sorted(hex(i) for i in ids)
        res.add("Product ID list", TARGET_PRODUCT_ID in ids, f"ids={sorted(hex(i) for i in ids)}")
        res.add("Product ID set known", ids <= EXPECTED_PRODUCT_IDS or TARGET_PRODUCT_ID in ids, "family check")
    if "support_pids" in files:
        txt = files["support_pids"].decode("utf-8", "replace")
        res.meta["support_pids"] = txt.strip()
        res.add("Support PID EW1200G-PRO", support_pids_ok(txt), txt[:80])
    if "version" in files:
        ver = files["version"].decode("utf-8", "replace").strip()
        res.meta["version"] = ver
        res.add("version present", bool(ver), ver)
    if "md5" in files and "encrypted installer" in files:
        md5_text = files["md5"].decode("utf-8", "replace")
        # verify each listed file
        md5_ok = True
        details = []
        for line in md5_text.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) < 2:
                md5_ok = False
                details.append("malformed line")
                continue
            expect, fname = parts[0], parts[1]
            # find member
            blob = None
            for name, m in members.items():
                if name.endswith(fname) or name == fname or name.split("/")[-1] == fname:
                    blob = tf.extractfile(m).read()
                    break
            if blob is None:
                md5_ok = False
                details.append(f"missing {fname}")
                continue
            got = md5_bytes(blob)
            if got != expect.lower():
                md5_ok = False
                details.append(f"{fname} mismatch")
            else:
                details.append(f"{fname}=ok")
        res.add("MD5", md5_ok, "; ".join(details))
    if "encrypted installer" in files:
        blob = files["encrypted installer"]
        res.add("crypto magic", blob.startswith(MAGIC), MAGIC.decode())
        try:
            rgos = decrypt_installer(blob)
            res.add("Decryption", True, f"rgos.bin {len(rgos)} bytes")
            validate_rgos(rgos, res)
        except Exception as e:
            res.add("Decryption", False, str(e))


def classify(data: bytes) -> str:
    if data[:2] == b"\x1f\x8b":
        return "reyee_oem_tar_gz"
    if data.startswith(MAGIC):
        return "reyee_encrypted_installer"
    if len(data) >= 4 and struct.unpack(">I", data[:4])[0] == UIMAGE_MAGIC:
        if b"supported_devices" in data[-8192:]:
            return "openwrt_sysupgrade"
        return "reyee_rgos_uimage"
    return "unknown"


def validate(path: Path) -> Result:
    res = Result()
    data = path.read_bytes()
    res.add("File exists", True, str(path))
    res.add("File size", 100 * 1024 <= len(data) <= MAX_UPLOAD, f"{len(data)} bytes")
    kind = classify(data)
    res.meta["package_type"] = kind
    res.add("Package type recognized", kind != "unknown", kind)
    if kind == "openwrt_sysupgrade":
        res.add("OEM path refuses OpenWrt image", False, "use KonekSik Firmware upload")
        return res
    if kind == "reyee_oem_tar_gz":
        validate_tar_gz(data, res)
    elif kind == "reyee_encrypted_installer":
        res.add("encrypted installer alone", True, "accepted with crypto checks")
        try:
            rgos = decrypt_installer(data)
            res.add("Decryption", True, f"{len(rgos)} bytes")
            validate_rgos(rgos, res)
        except Exception as e:
            res.add("Decryption", False, str(e))
    elif kind == "reyee_rgos_uimage":
        validate_rgos(data, res)
    return res


def print_report(res: Result, path: Path):
    print("=" * 50)
    print("KONEKSIK OEM FIRMWARE VALIDATION")
    print("=" * 50)
    print(f"Package:\n  {path}")
    print(f"\nPackage type:\n  {res.meta.get('package_type', '?')}")
    if "version" in res.meta:
        print(f"\nVersion:\n  {res.meta['version']}")
    if "product_ids" in res.meta:
        print(f"\nProduct IDs:\n  {', '.join(res.meta['product_ids'])}")
    if "image_size" in res.meta:
        print(f"\nImage size:\n  {res.meta['image_size']}")
        print(f"\nFirmware partition:\n  {FIRMWARE_MTD_SIZE}")
    if "kernel_name" in res.meta:
        print(f"\nKernel:\n  {res.meta['kernel_name']}")
    if "sha256" in res.meta:
        print(f"\nSHA256:\n  {res.meta['sha256']}")
    print("\nChecks:")
    for name, status, evidence in res.checks:
        print(f"  [{status}] {name}: {evidence}")
    print("\nOverall:")
    print("  PASS" if res.ok else "  FAIL")
    print("=" * 50)
    return 0 if res.ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    args = ap.parse_args()
    path = Path(args.path)
    if not path.is_file():
        print("FAIL: file not found", path)
        return 2
    res = validate(path)
    return print_report(res, path)


if __name__ == "__main__":
    raise SystemExit(main())
