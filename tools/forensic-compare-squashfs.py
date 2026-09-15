#!/usr/bin/env python3
"""Compare symlink metadata inside FASTFI vs KonekSik SquashFS images."""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

from PySquashfsImage import SquashFsImage


def find_squashfs(data: bytes, ih_size: int) -> int:
    for off in (ih_size + 64, ih_size, 3193853):
        if off + 4 <= len(data) and data[off : off + 4] == b"hsqs":
            return off
    idx = data.find(b"hsqs")
    if idx < 0:
        raise RuntimeError("squashfs not found")
    return idx


def extract_squash_bytes(bin_path: Path, out_sq: Path) -> Path:
    data = bin_path.read_bytes()
    if data[0:4] != b"\x27\x05\x19\x56":
        raise RuntimeError(f"not uImage: {bin_path}")
    ih_size = struct.unpack(">I", data[12:16])[0]
    off = find_squashfs(data, ih_size)
    out_sq.write_bytes(data[off:])
    print(f"wrote {out_sq} offset={off} bytes={len(data)-off}")
    return out_sq


def collect_nodes(sq_path: Path) -> dict[str, dict]:
    img = SquashFsImage.from_file(str(sq_path))
    out: dict[str, dict] = {}
    try:
        for node in img:
            p = node.path if str(node.path).startswith("/") else "/" + str(node.path)
            if p == "//":
                p = "/"
            info = {
                "is_symlink": bool(node.is_symlink),
                "is_file": bool(node.is_file),
                "is_dir": bool(node.is_dir),
                "size": getattr(node, "size", None),
                "link": None,
                "head": None,
            }
            if node.is_symlink:
                try:
                    link = node.readlink()
                    if isinstance(link, bytes):
                        link = link.decode("utf-8", "replace")
                    info["link"] = link
                except Exception as e:  # noqa: BLE001
                    info["link"] = f"<err:{e}>"
            elif node.is_file and (info["size"] or 0) <= 256:
                try:
                    raw = img.read_file(node.inode) if hasattr(img, "read_file") else None
                    if raw is None and hasattr(node, "read_bytes"):
                        raw = node.read_bytes()
                    if isinstance(raw, str):
                        raw = raw.encode()
                    if raw is not None:
                        info["head"] = raw.decode("utf-8", "replace").strip()[:80]
                except Exception as e:  # noqa: BLE001
                    info["head"] = f"<err:{e}>"
            out[p] = info
    finally:
        img.close()
    return out


def main() -> int:
    base = Path(__file__).resolve().parents[1]
    work = base / "tools" / "_forensic_squash"
    work.mkdir(parents=True, exist_ok=True)

    pairs = {
        "FASTFI": base / "FASTFI-RUIJIE-EW1200G-PRO-V2.5.1.bin",
        "KONEKSIK": base
        / "KonekSik-fi Piso Wifi Production"
        / "01-RUIJIE-OPENWRT"
        / "KonekSik-fi-EW1200G-PRO-sysupgrade.bin",
    }

    nodes = {}
    for label, bp in pairs.items():
        sq = work / f"{label}.squashfs"
        extract_squash_bytes(bp, sq)
        nodes[label] = collect_nodes(sq)
        n_link = sum(1 for v in nodes[label].values() if v["is_symlink"])
        n_marker = sum(
            1
            for v in nodes[label].values()
            if v["is_file"] and isinstance(v["head"], str) and v["head"].startswith("SYMLINK")
        )
        print(f"{label}: nodes={len(nodes[label])} symlinks={n_link} marker_files={n_marker}")

    # Compare critical paths
    critical = [
        "/bin/sh",
        "/bin/ash",
        "/bin/cat",
        "/bin/ls",
        "/bin/mount",
        "/usr/bin/env",
        "/lib/ld-musl-mipsel-sf.so.1",
        "/etc/os-release",
        "/etc/resolv.conf",
        "/etc/mtab",
        "/var",
    ]
    print("\n==== critical path compare ====")
    for p in critical:
        a = nodes["FASTFI"].get(p)
        b = nodes["KONEKSIK"].get(p)
        def fmt(x):
            if not x:
                return "MISSING"
            if x["is_symlink"]:
                return f"SYMLINK -> {x['link']}"
            if x["is_file"]:
                return f"FILE size={x['size']} head={x['head']!r}"
            if x["is_dir"]:
                return "DIR"
            return str(x)
        print(f"{p}")
        print(f"  FASTFI  : {fmt(a)}")
        print(f"  KONEKSIK: {fmt(b)}")

    # Full symlink set compare
    fa = {p for p, v in nodes["FASTFI"].items() if v["is_symlink"]}
    ka = {p for p, v in nodes["KONEKSIK"].items() if v["is_symlink"]}
    km = {
        p
        for p, v in nodes["KONEKSIK"].items()
        if v["is_file"] and isinstance(v["head"], str) and v["head"].startswith("SYMLINK")
    }
    print("\n==== set stats ====")
    print(f"FASTFI symlinks: {len(fa)}")
    print(f"KonekSik symlinks: {len(ka)}")
    print(f"KonekSik SYMLINK-marker regular files: {len(km)}")
    print(f"In FASTFI as symlink but KonekSik as marker-file: {len(fa & km)}")
    print(f"In FASTFI as symlink, missing as symlink in KonekSik: {len(fa - ka)}")
    only_fastfi = sorted(fa - ka)[:20]
    print("sample FASTFI-symlink missing as symlink in KonekSik:")
    for p in only_fastfi:
        b = nodes["KONEKSIK"].get(p)
        print(f"  {p} -> KonekSik={b}")

    report = {
        "fastfi_symlinks": len(fa),
        "koneksik_symlinks": len(ka),
        "koneksik_marker_files": len(km),
        "fastfi_symlink_became_marker": sorted(fa & km),
        "fastfi_symlink_not_symlink_in_koneksik": sorted(fa - ka),
    }
    out = work / "compare-report.json"
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"\nwrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
