"""Build a tiny update.tar.gz that fits a ~168KB-free overlay.

Priority payload (must fit need+peak <= 160 KB):
  1) Delete/Unbind lifecycle Lua + tiny admin-esp-lifecycle.js
  2) init.d hook
  3) fastfi-ota.sh (continue-full) if budget remains

migrate.sh injects the tiny JS into /www/admin.html so Delete/Unbind work
even when the multi-MB update-full.tar.gz cannot land yet.
"""
from __future__ import annotations

import io
import shutil
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROOTFS = ROOT / "EXTRACTED-OPENWRT-FASTFI-V2.5.1" / "rootfs"
OUT = ROOTFS / "update.tar.gz"
BUDGET_KB = 160

MIGRATE = r"""#!/bin/sh
# Bootstrap migrate: wire lifecycle JS + flag full OTA continuation.
mkdir -p /etc/fastfi 2>/dev/null || true
echo 1 > /etc/fastfi/ota_pending_full 2>/dev/null || true
chmod 600 /etc/fastfi/ota_pending_full 2>/dev/null || true

# Inject tiny lifecycle override into admin.html (does not replace the whole file).
if [ -f /www/admin-esp-lifecycle.js ] && [ -f /www/admin.html ]; then
  if ! grep -q 'admin-esp-lifecycle.js' /www/admin.html 2>/dev/null; then
    sed -i 's|</body>|<script src="/admin-esp-lifecycle.js?v=70"></script></body>|' /www/admin.html 2>/dev/null || true
  fi
fi
if [ -f /www/admin-esp-lifecycle.js ] && [ -f /www/admin-preview.html ]; then
  if ! grep -q 'admin-esp-lifecycle.js' /www/admin-preview.html 2>/dev/null; then
    sed -i 's|</body>|<script src="/admin-esp-lifecycle.js?v=70"></script></body>|' /www/admin-preview.html 2>/dev/null || true
  fi
fi

if [ -f /etc/rc.local ] && ! grep -q 'ota_pending_full' /etc/rc.local 2>/dev/null; then
  cat >> /etc/rc.local <<'EOF'

# KonekSik OTA bootstrap continue (one-shot; safe if flag absent)
if [ -f /etc/fastfi/ota_pending_full ]; then
  ( sleep 25; /usr/libexec/fastfi/core/fastfi-ota.sh continue-full >/tmp/ota-continue-full.log 2>&1 ) &
fi
EOF
fi
logger -t koneksik-ota 'Bootstrap lifecycle OTA installed; continue-full pending if engine present' 2>/dev/null || true
exit 0
"""


def add_text(tar: tarfile.TarFile, arcname: str, text: str, mode: int = 0o644) -> None:
    data = text.encode("utf-8")
    info = tarfile.TarInfo(name=arcname)
    info.size = len(data)
    info.mode = mode
    tar.addfile(info, io.BytesIO(data))


def add_file(tar: tarfile.TarFile, path: Path, arcname: str, mode: int = 0o755) -> None:
    data = path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    info = tarfile.TarInfo(name=arcname)
    info.size = len(data)
    info.mode = mode
    tar.addfile(info, io.BytesIO(data))


def measure(tar_path: Path) -> tuple[int, int]:
    td = Path(tempfile.mkdtemp(prefix="ota-boot-"))
    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            try:
                tar.extractall(td, filter="data")
            except TypeError:
                tar.extractall(td)
        need = 0
        peak = 0
        for rel in ("www", "usr/lib/lua/fastfi", "usr/libexec/fastfi", "etc"):
            p = td / rel
            if not p.exists():
                continue
            for f in p.rglob("*"):
                if f.is_file():
                    sz = (f.stat().st_size + 4095) // 4096 * 4
                    need += sz
                    peak = max(peak, sz)
        return need, peak
    finally:
        shutil.rmtree(td, ignore_errors=True)


def main() -> int:
    ver = (ROOTFS / "VERSION").read_text(encoding="utf-8").strip()

    # Must-have lifecycle (Delete/Unbind identity removal).
    required = [
        (ROOTFS / "usr/lib/lua/fastfi/db/sqlite.lua", "usr/lib/lua/fastfi/db/sqlite.lua", 0o644),
        (ROOTFS / "usr/lib/lua/fastfi/api/routes/esp.lua", "usr/lib/lua/fastfi/api/routes/esp.lua", 0o644),
        (
            ROOTFS / "usr/lib/lua/fastfi/api/routes/esp_license.lua",
            "usr/lib/lua/fastfi/api/routes/esp_license.lua",
            0o644,
        ),
        (ROOTFS / "www/admin-esp-lifecycle.js", "www/admin-esp-lifecycle.js", 0o644),
    ]
    optional = [
        (ROOTFS / "etc/init.d/fastfi", "etc/init.d/fastfi", 0o755),
        (ROOTFS / "usr/libexec/fastfi/core/fastfi-ota.sh", "usr/libexec/fastfi/core/fastfi-ota.sh", 0o755),
    ]

    for path, _, _ in required:
        if not path.is_file():
            raise SystemExit(f"missing required bootstrap file: {path}")

    chosen_optional: list[tuple[Path, str, int]] = []
    for item in optional:
        if not item[0].is_file():
            continue
        trial = required + chosen_optional + [item]
        if OUT.exists():
            OUT.unlink()
        with tarfile.open(OUT, "w:gz") as tar:
            add_text(tar, "VERSION", ver + "\n", 0o644)
            add_text(tar, "migrate.sh", MIGRATE, 0o755)
            for p, arc, mode in trial:
                add_file(tar, p, arc, mode)
        need, peak = measure(OUT)
        if need + peak <= BUDGET_KB:
            chosen_optional.append(item)
            print(f"include optional {item[1]} (need+peak={need + peak})")
        else:
            print(f"skip optional {item[1]} (would be need+peak={need + peak} > {BUDGET_KB})")

    if OUT.exists():
        OUT.unlink()
    with tarfile.open(OUT, "w:gz") as tar:
        add_text(tar, "VERSION", ver + "\n", 0o644)
        add_text(tar, "migrate.sh", MIGRATE, 0o755)
        for p, arc, mode in required + chosen_optional:
            add_file(tar, p, arc, mode)

    need, peak = measure(OUT)
    print(f"bootstrap {OUT}")
    print(f"version={ver}")
    print(f"estimated need_kb={need} peak_kb={peak} total={need + peak}")
    print("members:", required + chosen_optional)
    if need + peak > BUDGET_KB:
        raise SystemExit(f"bootstrap too large for 168KB-free target ({need + peak}KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
