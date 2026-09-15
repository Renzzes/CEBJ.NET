from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path
from typing import Any


def _app_root() -> Path:
    # PyInstaller .exe: keep keys/firmware/logs next to the executable
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent


def _bundle_dir() -> Path:
    # Read-only bundled assets (board_profiles, config.example) when frozen
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        return Path(sys._MEIPASS)
    return _app_root()


ROOT = _app_root()
BUNDLE = _bundle_dir()
CONFIG_PATH = ROOT / "config.json"
EXAMPLE_PATH = BUNDLE / "config.example.json"
if not EXAMPLE_PATH.exists():
    EXAMPLE_PATH = ROOT / "config.example.json"


def ensure_config() -> Path:
    if not CONFIG_PATH.exists():
        shutil.copy(EXAMPLE_PATH, CONFIG_PATH)
    return CONFIG_PATH


def load_config() -> dict[str, Any]:
    ensure_config()
    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        data = json.load(f)
    # Resolve relative paths against project root
    for key in ("firmware_path", "private_key_path", "public_key_path", "issue_log_path"):
        if key in data and data[key] and not Path(data[key]).is_absolute():
            data[key] = str((ROOT / data[key]).resolve())
    return data


def save_config(data: dict[str, Any]) -> None:
    # Store relative paths when under ROOT
    out = dict(data)
    for key in ("firmware_path", "private_key_path", "public_key_path", "issue_log_path"):
        p = Path(out.get(key, ""))
        try:
            out[key] = str(p.relative_to(ROOT)).replace("\\", "/")
        except Exception:
            out[key] = str(p).replace("\\", "/")
    with CONFIG_PATH.open("w", encoding="utf-8") as f:
        json.dump(out, f, indent=2)
