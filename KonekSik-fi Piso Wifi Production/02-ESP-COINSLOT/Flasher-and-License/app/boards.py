"""Load board pin profiles for the flasher UI."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

PROFILES_DIR = Path(__file__).resolve().parent.parent / "board_profiles"


def list_profiles() -> list[dict[str, Any]]:
    if not PROFILES_DIR.is_dir():
        return []
    out: list[dict[str, Any]] = []
    for path in sorted(PROFILES_DIR.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            data["_path"] = str(path)
            out.append(data)
        except Exception:
            continue
    return out


def get_profile(board_id: str) -> dict[str, Any] | None:
    for p in list_profiles():
        if p.get("id") == board_id:
            return p
    return None


def format_pin_map(profile: dict[str, Any]) -> str:
    lines: list[str] = []
    lines.append(profile.get("name", profile.get("id", "Board")))
    lines.append(f"Chip: {profile.get('chip')}  |  Network: {profile.get('network')}")
    lines.append(f"Wireless: {'yes' if profile.get('wireless') else 'no'}")
    if profile.get("notes"):
        lines.append("")
        lines.append(profile["notes"])
    lines.append("")
    lines.append("Pins:")
    pins = profile.get("pins") or {}
    # Stable-ish order: coin, relay, led, then w5500/eth
    order = [
        "coin_primary",
        "coin_backup",
        "relay",
        "led",
        "config_btn",
        "w5500_cs",
        "w5500_sclk",
        "w5500_miso",
        "w5500_mosi",
        "eth_mdc",
        "eth_mdio",
        "eth_clk",
        "eth_power",
    ]
    seen = set()
    for key in order:
        if key in pins:
            seen.add(key)
            p = pins[key]
            lines.append(
                f"  • {p.get('role', key)}: GPIO {p.get('gpio')} ({p.get('label', '')})"
            )
    for key, p in pins.items():
        if key in seen:
            continue
        lines.append(f"  • {p.get('role', key)}: GPIO {p.get('gpio')} ({p.get('label', '')})")
    return "\n".join(lines)
