"""Append-only local log of issued licenses (no cloud)."""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any


def append_issue(path: str | Path, record: dict[str, Any]) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    row = dict(record)
    row.setdefault("logged_at", int(time.time()))
    with p.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, separators=(",", ":")) + "\n")
