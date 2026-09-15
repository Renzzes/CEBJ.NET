"""Shared modern ttk theme + always-visible step guide for CEBJ / KonekSik apps."""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk
from typing import Sequence


# Slate + teal (not purple / cream / dark-glow default AI look)
COLORS = {
    "bg": "#f1f5f9",
    "surface": "#ffffff",
    "surface2": "#e2e8f0",
    "border": "#cbd5e1",
    "text": "#0f172a",
    "muted": "#64748b",
    "accent": "#0d9488",
    "accent_hover": "#0f766e",
    "accent_soft": "#ccfbf1",
    "sidebar": "#0f172a",
    "sidebar_text": "#e2e8f0",
    "sidebar_muted": "#94a3b8",
    "step_num": "#14b8a6",
    "danger": "#dc2626",
    "ok": "#059669",
    "log_bg": "#0f172a",
    "log_fg": "#e2e8f0",
}


def apply_theme(root: tk.Tk | tk.Toplevel) -> ttk.Style:
    root.configure(bg=COLORS["bg"])
    style = ttk.Style(root)
    try:
        style.theme_use("clam")
    except Exception:
        pass

    style.configure(".", background=COLORS["bg"], foreground=COLORS["text"], font=("Segoe UI", 10))
    style.configure("TFrame", background=COLORS["bg"])
    style.configure("Card.TFrame", background=COLORS["surface"])
    style.configure("Sidebar.TFrame", background=COLORS["sidebar"])
    style.configure("TLabel", background=COLORS["bg"], foreground=COLORS["text"], font=("Segoe UI", 10))
    style.configure("Card.TLabel", background=COLORS["surface"], foreground=COLORS["text"])
    style.configure("Muted.TLabel", background=COLORS["bg"], foreground=COLORS["muted"], font=("Segoe UI", 9))
    style.configure("CardMuted.TLabel", background=COLORS["surface"], foreground=COLORS["muted"], font=("Segoe UI", 9))
    style.configure("Title.TLabel", background=COLORS["bg"], foreground=COLORS["text"], font=("Segoe UI Semibold", 16))
    style.configure("Subtitle.TLabel", background=COLORS["bg"], foreground=COLORS["muted"], font=("Segoe UI", 10))
    style.configure("Brand.TLabel", background=COLORS["sidebar"], foreground="#5eead4", font=("Segoe UI Semibold", 13))
    style.configure("SideTitle.TLabel", background=COLORS["sidebar"], foreground=COLORS["sidebar_text"], font=("Segoe UI Semibold", 11))
    style.configure("SideBody.TLabel", background=COLORS["sidebar"], foreground=COLORS["sidebar_muted"], font=("Segoe UI", 9))
    style.configure("StepNum.TLabel", background=COLORS["sidebar"], foreground=COLORS["step_num"], font=("Segoe UI Semibold", 10))
    style.configure("CardTitle.TLabel", background=COLORS["surface"], foreground=COLORS["text"], font=("Segoe UI Semibold", 11))
    style.configure("TLabelframe", background=COLORS["surface"], foreground=COLORS["text"], bordercolor=COLORS["border"])
    style.configure("TLabelframe.Label", background=COLORS["surface"], foreground=COLORS["accent"], font=("Segoe UI Semibold", 10))
    style.configure("TEntry", fieldbackground="#fff", foreground=COLORS["text"], insertcolor=COLORS["text"])
    style.configure("TCombobox", fieldbackground="#fff", foreground=COLORS["text"])
    style.configure(
        "Accent.TButton",
        background=COLORS["accent"],
        foreground="#ffffff",
        font=("Segoe UI Semibold", 10),
        padding=(14, 8),
        borderwidth=0,
    )
    style.map(
        "Accent.TButton",
        background=[("active", COLORS["accent_hover"]), ("disabled", COLORS["border"])],
        foreground=[("disabled", COLORS["muted"])],
    )
    style.configure("Secondary.TButton", padding=(12, 7), font=("Segoe UI", 10))
    style.configure("TButton", padding=(10, 6), font=("Segoe UI", 10))
    style.configure("TSeparator", background=COLORS["border"])
    style.configure("Horizontal.TProgressbar", background=COLORS["accent"], troughcolor=COLORS["surface2"])
    return style


def make_card(parent: tk.Widget, title: str, hint: str = "") -> ttk.LabelFrame:
    box = ttk.LabelFrame(parent, text=title, padding=14)
    if hint:
        ttk.Label(box, text=hint, style="CardMuted.TLabel").pack(anchor=tk.W, pady=(0, 8))
    return box


def make_log(parent: tk.Widget, height: int = 10) -> tk.Text:
    wrap = ttk.Frame(parent)
    wrap.pack(fill=tk.BOTH, expand=True)
    log = tk.Text(
        wrap,
        height=height,
        wrap=tk.WORD,
        font=("Consolas", 9),
        bg=COLORS["log_bg"],
        fg=COLORS["log_fg"],
        insertbackground=COLORS["log_fg"],
        relief=tk.FLAT,
        padx=10,
        pady=8,
        highlightthickness=0,
    )
    scroll = ttk.Scrollbar(wrap, command=log.yview)
    log.configure(yscrollcommand=scroll.set)
    log.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
    scroll.pack(side=tk.RIGHT, fill=tk.Y)
    return log


def build_shell(
    root: tk.Tk,
    *,
    brand: str,
    title: str,
    subtitle: str,
    guide_title: str,
    guide_steps: Sequence[tuple[str, str]],
    guide_notes: Sequence[str] | None = None,
) -> tuple[ttk.Frame, tk.Text]:
    """
    Two-column layout: left always-visible guide, right content host.
    Returns (content_frame, guide_text_widget for optional extra notes).
    """
    apply_theme(root)

    outer = ttk.Frame(root)
    outer.pack(fill=tk.BOTH, expand=True)

    # --- Sidebar guide (always visible) ---
    side = tk.Frame(outer, bg=COLORS["sidebar"], width=300)
    side.pack(side=tk.LEFT, fill=tk.Y)
    side.pack_propagate(False)

    pad = tk.Frame(side, bg=COLORS["sidebar"])
    pad.pack(fill=tk.BOTH, expand=True, padx=18, pady=18)

    ttk.Label(pad, text=brand, style="Brand.TLabel").pack(anchor=tk.W)
    ttk.Label(pad, text=guide_title, style="SideTitle.TLabel").pack(anchor=tk.W, pady=(14, 6))

    guide_box = tk.Text(
        pad,
        wrap=tk.WORD,
        font=("Segoe UI", 9),
        bg=COLORS["sidebar"],
        fg=COLORS["sidebar_text"],
        relief=tk.FLAT,
        highlightthickness=0,
        cursor="arrow",
        padx=0,
        pady=0,
    )
    guide_box.pack(fill=tk.BOTH, expand=True)

    def _insert_guide() -> None:
        guide_box.configure(state=tk.NORMAL)
        guide_box.delete("1.0", tk.END)
        guide_box.tag_configure("num", foreground=COLORS["step_num"], font=("Segoe UI Semibold", 10))
        guide_box.tag_configure("body", foreground=COLORS["sidebar_text"], font=("Segoe UI", 9), lmargin2=14, spacing3=10)
        guide_box.tag_configure("note", foreground=COLORS["sidebar_muted"], font=("Segoe UI", 8), spacing3=6)
        for i, (step_title, step_body) in enumerate(guide_steps, 1):
            guide_box.insert(tk.END, f"{i}. {step_title}\n", "num")
            guide_box.insert(tk.END, f"{step_body}\n\n", "body")
        if guide_notes:
            guide_box.insert(tk.END, "Tips\n", "num")
            for n in guide_notes:
                guide_box.insert(tk.END, f"• {n}\n", "note")
        guide_box.configure(state=tk.DISABLED)

    _insert_guide()

    # --- Main column ---
    main = ttk.Frame(outer, padding=18)
    main.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

    ttk.Label(main, text=title, style="Title.TLabel").pack(anchor=tk.W)
    ttk.Label(main, text=subtitle, style="Subtitle.TLabel").pack(anchor=tk.W, pady=(2, 14))

    content = ttk.Frame(main)
    content.pack(fill=tk.BOTH, expand=True)
    return content, guide_box
