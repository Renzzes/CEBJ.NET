"""Serial helpers: list ports, read identity, write license blob."""

from __future__ import annotations

import re
import time
from typing import Callable

LogFn = Callable[[str], None]


def list_serial_ports() -> list[dict]:
    try:
        from serial.tools import list_ports
    except ImportError as e:
        raise RuntimeError("pyserial is not installed") from e

    out = []
    for p in list_ports.comports():
        out.append(
            {
                "device": p.device,
                "description": p.description or "",
                "hwid": p.hwid or "",
                "vid": p.vid,
                "pid": p.pid,
            }
        )
    return out


def read_identity(port: str, baud: int = 115200, timeout: float = 4.0, log: LogFn | None = None) -> dict:
    """
    Ask the coinslot firmware for identity.
    Protocol (to be implemented on ESP):
      host -> KSK_ID?
      esp  -> KSK_ID chip=<hex> mac=AA:BB:...
    Falls back to parsing boot spam for MAC if needed.
    """
    import serial

    def _log(m: str) -> None:
        if log:
            log(m)

    chip_id = ""
    mac = ""
    with serial.Serial(port, baud, timeout=0.4) as ser:
        time.sleep(0.3)
        ser.reset_input_buffer()
        ser.write(b"KSK_ID?\r\n")
        ser.flush()
        deadline = time.time() + timeout
        buf = ""
        while time.time() < deadline:
            chunk = ser.read(256).decode("utf-8", errors="ignore")
            if chunk:
                buf += chunk
                _log(chunk.rstrip())
            m = re.search(r"KSK_ID\s+chip=([0-9A-Fa-f]+)\s+mac=([0-9A-Fa-f:]+)", buf)
            if m:
                chip_id = m.group(1).upper()
                mac = m.group(2).upper()
                break
            # common ESP8266 boot / WiFi.macAddress style
            m2 = re.search(r"([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})", buf)
            if m2 and not mac:
                mac = m2.group(1).upper()

    if not chip_id and mac:
        chip_id = mac.replace(":", "")
    return {"chip_id": chip_id, "mac": mac}


def write_license(
    port: str,
    provision_line: str,
    baud: int = 115200,
    timeout: float = 8.0,
    log: LogFn | None = None,
) -> bool:
    """
    Write signed license to ESP over serial.
    Protocol:
      host -> KSK_LICENSE_WRITE <base64json>
      esp  -> KSK_LICENSE_OK
         or -> KSK_LICENSE_ERR <msg>
    """
    import serial

    def _log(m: str) -> None:
        if log:
            log(m)

    line = provision_line.strip() + "\r\n"
    with serial.Serial(port, baud, timeout=0.4) as ser:
        time.sleep(0.4)
        ser.reset_input_buffer()
        _log("> " + provision_line[:80] + ("…" if len(provision_line) > 80 else ""))
        ser.write(line.encode("ascii"))
        ser.flush()
        deadline = time.time() + timeout
        buf = ""
        while time.time() < deadline:
            chunk = ser.read(512).decode("utf-8", errors="ignore")
            if chunk:
                buf += chunk
                _log(chunk.rstrip())
            if "KSK_LICENSE_OK" in buf:
                return True
            if "KSK_LICENSE_ERR" in buf:
                return False
    _log("No KSK_LICENSE_OK from device (firmware may not support provision yet).")
    return False
