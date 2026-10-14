"""Build a tiny update.tar.gz that fits a ~168KB-free overlay.

Old OTA clients charge du(www+lua+libexec+etc)+peak. This bootstrap ships only
the new fastfi-ota.sh (+ init.d hook + migrate) so need+peak stays under ~150KB.
After reboot, continue-full pulls update-full.tar.gz from the same release.
"""
from __future__ import annotations

import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROOTFS = ROOT / "EXTRACTED-OPENWRT-FASTFI-V2.5.1" / "rootfs"
OUT = ROOTFS / "update.tar.gz"

MIGRATE = """#!/bin/sh
# Bootstrap migrate: flag a full OTA continuation after reboot.
mkdir -p /etc/fastfi 2>/dev/null || true
echo 1 > /etc/fastfi/ota_pending_full 2>/dev/null || true
chmod 600 /etc/fastfi/ota_pending_full 2>/dev/null || true
# One-shot rc.local fallback if init.d was not replaced yet.
if [ -f /etc/rc.local ] && ! grep -q 'ota_pending_full' /etc/rc.local 2>/dev/null; then
    cat >> /etc/rc.local <<'EOF'

# KonekSik OTA bootstrap continue (one-shot; safe if flag absent)
if [ -f /etc/fastfi/ota_pending_full ]; then
  ( sleep 25; /usr/libexec/fastfi/core/fastfi-ota.sh continue-full >/tmp/ota-continue-full.log 2>&1 ) &
fi
EOF
fi
logger -t koneksik-ota 'Bootstrap OTA installed; will pull update-full.tar.gz after reboot' 2>/dev/null || true
exit 0
"""


def add_text(tar: tarfile.TarFile, arcname: str, text: str, mode: int = 0o644) -> None:
    data = text.encode("utf-8")
    info = tarfile.TarInfo(name=arcname)
    info.size = len(data)
    info.mode = mode
    import io

    tar.addfile(info, io.BytesIO(data))


def add_file(tar: tarfile.TarFile, path: Path, arcname: str, mode: int = 0o755) -> None:
    data = path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    info = tarfile.TarInfo(name=arcname)
    info.size = len(data)
    info.mode = mode
    import io

    tar.addfile(info, io.BytesIO(data))


def main() -> int:
    ver = (ROOTFS / "VERSION").read_text(encoding="utf-8").strip()
    ota = ROOTFS / "usr/libexec/fastfi/core/fastfi-ota.sh"
    initd = ROOTFS / "etc/init.d/fastfi"
    if not ota.is_file() or not initd.is_file():
        raise SystemExit("missing fastfi-ota.sh or etc/init.d/fastfi")

    if OUT.exists():
        OUT.unlink()

    with tarfile.open(OUT, "w:gz") as tar:
        add_text(tar, "VERSION", ver + "\n", 0o644)
        add_text(tar, "migrate.sh", MIGRATE, 0o755)
        add_file(tar, ota, "usr/libexec/fastfi/core/fastfi-ota.sh", 0o755)
        add_file(tar, initd, "etc/init.d/fastfi", 0o755)

    # Mirror old-client space gate estimate.
    import tempfile, subprocess, shutil

    td = Path(tempfile.mkdtemp(prefix="ota-boot-"))
    try:
        with tarfile.open(OUT, "r:gz") as tar:
            tar.extractall(td)
        need = 0
        peak = 0
        for rel in (
            "www",
            "usr/lib/lua/fastfi",
            "usr/libexec/fastfi",
            "etc",
        ):
            p = td / rel
            if not p.exists():
                continue
            for f in p.rglob("*"):
                if f.is_file():
                    sz = (f.stat().st_size + 4095) // 4096 * 4
                    need += sz
                    peak = max(peak, sz)
        print(f"bootstrap {OUT}")
        print(f"version={ver}")
        print(f"estimated need_kb={need} peak_kb={peak} total={need + peak}")
        if need + peak > 160:
            raise SystemExit(f"bootstrap too large for 168KB-free target ({need + peak}KB)")
    finally:
        shutil.rmtree(td, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
