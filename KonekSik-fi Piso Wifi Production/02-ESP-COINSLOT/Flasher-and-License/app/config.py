from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "config.json"
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
