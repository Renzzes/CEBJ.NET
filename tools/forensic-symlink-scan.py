#!/usr/bin/env python3
"""Offline forensic scan: uImage headers + SYMLINK marker detection in firmware bins."""
from __future__ import annotations

import struct
import sys
from pathlib import Path


def uimage_info(data: bytes) -> dict:
    if data[0:4] != b"\x27\x05\x19\x56":
        return {"valid": False}
    ih_size = struct.unpack(">I", data[12:16])[0]
    load = struct.unpack(">I", data[16:20])[0]
    ep = struct.unpack(">I", data[20:24])[0]
    name = data[32:60].split(b"\x00", 1)[0].decode("ascii", "replace")
    return {
        "valid": True,
        "ih_size": ih_size,
        "load": load,
        "ep": ep,
        "name": name,
    }


def find_squashfs(data: bytes, ih_size: int) -> int | None:
    candidates = [ih_size + 64, ih_size, 3193853]
    for off in candidates:
        if off + 4 <= len(data) and data[off : off + 4] in (b"hsqs", b"sqsh"):
            return off
    idx = data.find(b"hsqs")
    return idx if idx >= 0 else None


def scan_bin(path: Path) -> None:
    data = path.read_bytes()
    print(f"==== {path.name} ({len(data)} bytes) ====")
    info = uimage_info(data)
    print(f"uImage valid={info.get('valid')} name={info.get('name')} "
          f"ih_size={info.get('ih_size')} load=0x{info.get('load', 0):08x} "
          f"ep=0x{info.get('ep', 0):08x}")
    if info.get("valid"):
        sq = find_squashfs(data, info["ih_size"])
        print(f"squashfs offset={sq}")
        if sq is not None:
            print(f"squashfs magic={data[sq:sq+4]!r}")
    # Raw ASCII (only visible if uncompressed or in metadata)
    needle = b"SYMLINK ->"
    print(f"raw ASCII '{needle.decode()}' count={data.count(needle)}")
    # Also count in zlib/xz unlikely; report marker-like short strings near busybox
    print()


def scan_overlay_markers(root: Path) -> None:
    markers = []
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        if p.stat().st_size > 256:
            continue
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if text.startswith("SYMLINK"):
            rel = "/" + p.relative_to(root).as_posix()
            markers.append((rel, text.strip()))
    print(f"==== overlay markers under {root} ====")
    print(f"count={len(markers)}")
    for rel, text in markers[:15]:
        print(f"  {rel}: {text}")
    if len(markers) > 15:
        print(f"  ... +{len(markers) - 15} more")
    print()


def main() -> int:
    base = Path(__file__).resolve().parents[1]
    bins = [
        base / "FASTFI-RUIJIE-EW1200G-PRO-V2.5.1.bin",
        base / "KonekSik-fi Piso Wifi Production" / "01-RUIJIE-OPENWRT" / "KonekSik-fi-EW1200G-PRO-sysupgrade.bin",
    ]
    for b in bins:
        if b.exists():
            scan_bin(b)
        else:
            print(f"MISSING {b}")
    overlay = base / "EXTRACTED-OPENWRT-FASTFI-V2.5.1" / "rootfs"
    scan_overlay_markers(overlay)
    sj = base / "EXTRACTED-OPENWRT-FASTFI-V2.5.1" / "symlinks.json"
    if sj.exists():
        import json
        data = json.loads(sj.read_text(encoding="utf-8"))
        print(f"symlinks.json entries={len(data)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
