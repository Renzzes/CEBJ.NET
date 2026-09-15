"""Flash ESP8266 / ESP32 via esptool."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Callable


LogFn = Callable[[str], None]


def flash_firmware(
    *,
    port: str,
    firmware_path: str | Path,
    chip: str = "esp8266",
    baud: int = 460800,
    flash_mode: str = "dout",
    flash_freq: str = "40m",
    flash_size: str = "4MB",
    log: LogFn | None = None,
) -> None:
    fw = Path(firmware_path)
    if not fw.is_file():
        raise FileNotFoundError(f"Firmware not found: {fw}")

    def _log(msg: str) -> None:
        if log:
            log(msg)

    chip = (chip or "esp8266").lower()
    # esptool v4 CLI
    args = [
        "--chip", chip,
        "--port", port,
        "--baud", str(baud),
        "write_flash",
        "-fm", flash_mode,
        "-ff", flash_freq,
        "-fs", flash_size,
        "0x0",
        str(fw),
    ]
    _log("esptool " + " ".join(args))

    try:
        import esptool
    except ImportError as e:
        raise RuntimeError("esptool is not installed. Run: pip install -r requirements.txt") from e

    # esptool.main mutates sys.argv
    old_argv = sys.argv[:]
    try:
        sys.argv = ["esptool"] + args
        esptool.main()
    finally:
        sys.argv = old_argv
    _log("Flash complete.")
