#!/usr/bin/env python3
"""
Fail if a KonekSik/OpenWrt firmware SquashFS contains Windows symlink placeholders.

Usage:
  python tools/validate-firmware-symlinks.py path\\to\\image.bin
  python tools/validate-firmware-symlinks.py --compare-fastfi path\\to\\koneksik.bin

Exit 0 = pass, 1 = fail.
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

from PySquashfsImage import SquashFsImage

CRITICAL = [
    "/bin/sh",
    "/bin/ash",
    "/bin/cat",
    "/bin/chmod",
    "/bin/chown",
    "/bin/cp",
    "/bin/date",
    "/bin/dd",
    "/bin/df",
    "/bin/dmesg",
    "/bin/echo",
    "/bin/grep",
    "/bin/kill",
    "/bin/ls",
    "/bin/mkdir",
    "/bin/mount",
    "/bin/mv",
    "/bin/ping",
    "/bin/ps",
    "/bin/rm",
    "/bin/sed",
    "/bin/sleep",
    "/bin/tar",
    "/bin/true",
    "/bin/umount",
    "/bin/uname",
    "/etc/os-release",
    "/etc/resolv.conf",
    "/etc/mtab",
    "/etc/localtime",
    "/etc/TZ",
    "/etc/ssl/cert.pem",
    "/lib/ld-musl-mipsel-sf.so.1",
    "/usr/bin/env",
    "/usr/bin/lua",
    "/usr/bin/wget",
    "/usr/bin/ssh",
    "/usr/bin/scp",
    "/usr/bin/hexdump",
    "/usr/bin/logger",
    "/usr/bin/which",
]


def squash_offset(data: bytes) -> int:
    if data[0:4] != b"\x27\x05\x19\x56":
        raise SystemExit("not a uImage (.bin)")
    ih_size = struct.unpack(">I", data[12:16])[0]
    for off in (ih_size + 64, ih_size, 3193853):
        if off + 4 <= len(data) and data[off : off + 4] == b"hsqs":
            return off
    idx = data.find(b"hsqs")
    if idx < 0:
        raise SystemExit("squashfs not found in image")
    return idx


def load_nodes(bin_path: Path) -> dict[str, dict]:
    data = bin_path.read_bytes()
    off = squash_offset(data)
    # PySquashfsImage can open with offset
    img = SquashFsImage.from_file(str(bin_path), offset=off)
    out: dict[str, dict] = {}
    try:
        for node in img:
            p = str(node.path)
            if not p.startswith("/"):
                p = "/" + p
            info = {
                "is_symlink": bool(node.is_symlink),
                "is_file": bool(node.is_file),
                "link": None,
                "head": None,
                "size": getattr(node, "size", None),
            }
            if node.is_symlink:
                link = node.readlink()
                if isinstance(link, bytes):
                    link = link.decode("utf-8", "replace")
                info["link"] = link
            elif node.is_file and (info["size"] or 0) <= 256:
                try:
                    raw = img.read_file(node.inode)
                    info["head"] = raw.decode("utf-8", "replace").strip()[:80]
                except Exception:  # noqa: BLE001
                    pass
            out[p] = info
    finally:
        img.close()
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("image", type=Path, help="Firmware .bin to validate")
    ap.add_argument(
        "--compare-fastfi",
        type=Path,
        default=None,
        help="Optional FASTFI baseline .bin for full symlink-set compare",
    )
    ap.add_argument("--json-out", type=Path, default=None)
    args = ap.parse_args()

    nodes = load_nodes(args.image)
    markers = sorted(
        p
        for p, v in nodes.items()
        if v["is_file"] and isinstance(v["head"], str) and v["head"].startswith("SYMLINK")
    )
    symlinks = sorted(p for p, v in nodes.items() if v["is_symlink"])

    print(f"image: {args.image}")
    print(f"symlinks: {len(symlinks)}")
    print(f"SYMLINK-marker regular files: {len(markers)}")

    failed = []
    print("\nCRITICAL CHECKS:")
    for p in CRITICAL:
        v = nodes.get(p)
        if not v:
            # some critical paths may be absent depending on packages
            print(f"  SKIP  {p} (absent)")
            continue
        if v["is_symlink"]:
            print(f"  PASS  {p} -> {v['link']}")
        elif v["is_file"] and isinstance(v["head"], str) and v["head"].startswith("SYMLINK"):
            print(f"  FAIL  {p} is regular file: {v['head']!r}")
            failed.append(p)
        else:
            print(f"  FAIL  {p} expected symlink, got file/dir size={v.get('size')}")
            failed.append(p)

    if markers:
        print(f"\nFAIL: {len(markers)} placeholder file(s) present (sample):")
        for p in markers[:25]:
            print(f"  {p}: {nodes[p]['head']}")
        failed.extend(markers)

    report = {
        "image": str(args.image),
        "symlink_count": len(symlinks),
        "marker_count": len(markers),
        "failed_critical": sorted(set(failed)),
        "markers": markers,
    }

    if args.compare_fastfi and args.compare_fastfi.exists():
        base = load_nodes(args.compare_fastfi)
        base_links = {p for p, v in base.items() if v["is_symlink"]}
        img_links = set(symlinks)
        missing = sorted(base_links - img_links)
        report["fastfi_symlink_count"] = len(base_links)
        report["missing_vs_fastfi"] = missing
        print(f"\nFASTFI baseline symlinks: {len(base_links)}")
        print(f"Missing as symlink vs FASTFI: {len(missing)}")
        if missing:
            # missing is OK only if not turned into markers; markers already fail
            as_marker = [p for p in missing if p in markers]
            print(f"  of which are marker files: {len(as_marker)}")
            if as_marker:
                failed.extend(as_marker)

    if args.json_out:
        args.json_out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"wrote {args.json_out}")

    if failed or markers:
        print("\nRESULT: FAIL")
        return 1
    print("\nRESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
