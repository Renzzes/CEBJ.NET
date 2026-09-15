#!/usr/bin/env python3
"""
Restore Windows 'SYMLINK -> target' placeholder files to real OS symlinks.

On Windows this requires Developer Mode (or admin) for os.symlink.
Prefer relying on build-image.sh restore inside WSL; use this to clean the
editable EXTRACTED rootfs on a symlink-capable volume.

Usage:
  python tools/restore-symlink-placeholders.py EXTRACTED-OPENWRT-FASTFI-V2.5.1\\rootfs
  python tools/restore-symlink-placeholders.py EXTRACTED-...\\rootfs --manifest EXTRACTED-...\\symlinks.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

MARKER_RE = re.compile(r"^SYMLINK\s*->\s*(.*)\s*$", re.DOTALL)


def restore_tree(root: Path) -> tuple[int, list[str]]:
    restored = 0
    errors: list[str] = []
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        if path.stat().st_size > 512:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError as e:
            errors.append(f"{path}: read {e}")
            continue
        m = MARKER_RE.match(text)
        if not m:
            continue
        target = m.group(1).strip().strip("\r\n")
        try:
            path.unlink()
            os.symlink(target, path)
            restored += 1
        except OSError as e:
            errors.append(f"{path}: symlink({target!r}) failed: {e}")
            # best-effort rewrite marker back if unlink succeeded
            if not path.exists():
                path.write_text(f"SYMLINK -> {target}\n", encoding="utf-8")
    return restored, errors


def apply_manifest(root: Path, manifest: Path) -> tuple[int, list[str]]:
    n = 0
    errors: list[str] = []
    for e in json.loads(manifest.read_text(encoding="utf-8")):
        dest = root / e["path"].lstrip("/")
        target = e["target"]
        if dest.is_symlink():
            continue
        if dest.exists() and dest.is_file():
            try:
                txt = dest.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            if not txt.startswith("SYMLINK"):
                continue
            dest.unlink()
        elif dest.exists():
            continue
        try:
            dest.parent.mkdir(parents=True, exist_ok=True)
            os.symlink(target, dest)
            n += 1
        except OSError as err:
            errors.append(f"{dest}: {err}")
    return n, errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rootfs", type=Path)
    ap.add_argument("--manifest", type=Path, default=None)
    args = ap.parse_args()
    root = args.rootfs
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 2
    r1, e1 = restore_tree(root)
    print(f"content-scan restored: {r1}")
    r2 = 0
    e2: list[str] = []
    manifest = args.manifest
    if manifest is None:
        cand = root.parent / "symlinks.json"
        if cand.exists():
            manifest = cand
    if manifest and manifest.exists():
        r2, e2 = apply_manifest(root, manifest)
        print(f"manifest ensured: {r2} ({manifest})")
    for e in e1 + e2:
        print(f"ERROR: {e}", file=sys.stderr)
    leftover = []
    for path in root.rglob("*"):
        if path.is_file() and not path.is_symlink() and path.stat().st_size <= 512:
            try:
                if path.read_text(encoding="utf-8", errors="ignore").startswith("SYMLINK"):
                    leftover.append(path)
            except OSError:
                pass
    print(f"leftover markers: {len(leftover)}")
    if leftover or e1 or e2:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
