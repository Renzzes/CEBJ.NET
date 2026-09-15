"""
Seller-only License Generator — mint KSK licenses / replacement bundles (no flash UI).
"""

from __future__ import annotations

import json
import time
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from app import __version__
from app.config import ROOT, load_config
from app.crypto_license import (
    ensure_keypair,
    export_replacement_bundle,
    issue_license,
    verify_license,
)
from app.ui_theme import build_shell, make_card, make_log


GUIDE_STEPS = (
    ("Who uses this", "Seller / CEBJ desk only. Buyers never get this app or your private key."),
    ("Fill optional fields", "Chip ID or MAC help label the license. Leave blank to mint stock licenses."),
    ("License ID", "Leave blank for a new auto KSK-… ID. Only set manually if you know why."),
    ("Generate", "Click Generate. A signed license JSON and a .ksk buyer bundle are saved."),
    ("Give to buyer", "Send the .ksk file. Buyer uses Replacement Flasher or you use ESP Flasher to burn it."),
    ("Grace exhausted", "After 3 board replacements on the router, mint a NEW license here."),
)

GUIDE_NOTES = (
    "Outputs: logs\\license_KSK-….json and bundles\\KSK-….ksk",
    "Keep keys\\issuer_ed25519.pem secret and backed up.",
    "This app does not flash hardware.",
)


class LicenseGeneratorApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"CEBJ.NET License Generator v{__version__}")
        self.geometry("980x640")
        self.minsize(880, 560)

        self.cfg = load_config()
        ensure_keypair(self.cfg["private_key_path"], self.cfg["public_key_path"])

        self.chip_var = tk.StringVar()
        self.mac_var = tk.StringVar()
        self.plan_var = tk.StringVar(value=self.cfg.get("plan_default", "standard"))
        self.days_var = tk.StringVar(value=str(self.cfg.get("lifetime_days", 0)))
        self.lid_var = tk.StringVar()
        self.status_var = tk.StringVar(value="Ready to mint a new offline license.")

        content, _ = build_shell(
            self,
            brand="CEBJ.NET / KonekSik",
            title="Seller License Generator",
            subtitle="Create a new offline KSK license and buyer .ksk bundle — no cloud, no flash.",
            guide_title="Step-by-step (always here)",
            guide_steps=GUIDE_STEPS,
            guide_notes=GUIDE_NOTES,
        )

        box = make_card(
            content,
            "1 · License details",
            "Blank Chip/MAC is OK for stock. Blank License ID = auto KSK-…",
        )
        box.pack(fill=tk.X, pady=(0, 12))

        grid = ttk.Frame(box)
        grid.pack(fill=tk.X)
        fields = (
            ("Chip ID (optional)", self.chip_var),
            ("MAC (optional)", self.mac_var),
            ("License ID (blank = auto)", self.lid_var),
            ("Plan", self.plan_var),
            ("Lifetime days (0 = forever)", self.days_var),
        )
        for r, (label, var) in enumerate(fields):
            ttk.Label(grid, text=label, style="Card.TLabel").grid(row=r, column=0, sticky=tk.W, pady=4, padx=(0, 12))
            if label == "Plan":
                ttk.Combobox(
                    grid,
                    textvariable=var,
                    values=("lite", "standard", "pro", "lifetime"),
                    width=28,
                ).grid(row=r, column=1, sticky=tk.W, pady=4)
            else:
                ttk.Entry(grid, textvariable=var, width=32).grid(row=r, column=1, sticky=tk.W, pady=4)

        actions = ttk.Frame(content)
        actions.pack(fill=tk.X, pady=(0, 8))
        ttk.Button(actions, text="Generate + export .ksk bundle", style="Accent.TButton", command=self.on_generate).pack(
            side=tk.LEFT
        )
        ttk.Button(actions, text="Open bundles folder", style="Secondary.TButton", command=self.open_bundles).pack(
            side=tk.LEFT, padx=8
        )
        ttk.Label(content, textvariable=self.status_var, style="Muted.TLabel").pack(anchor=tk.W, pady=(0, 8))

        log_card = make_card(content, "2 · Activity log")
        log_card.pack(fill=tk.BOTH, expand=True)
        self.log = make_log(log_card, height=14)
        self._log(f"Keys ready under {ROOT / 'keys'}")
        self._log(f"Bundles will save to {ROOT / 'bundles'}")

    def _log(self, m: str) -> None:
        self.log.insert(tk.END, m + "\n")
        self.log.see(tk.END)

    def open_bundles(self) -> None:
        path = ROOT / "bundles"
        path.mkdir(parents=True, exist_ok=True)
        try:
            import os

            os.startfile(str(path))  # type: ignore[attr-defined]
        except Exception as e:
            messagebox.showinfo("Bundles", str(path) + "\n" + str(e))

    def on_generate(self) -> None:
        try:
            chip = self.chip_var.get().strip()
            mac = self.mac_var.get().strip()
            if not chip and not mac:
                chip = "GEN" + str(int(time.time()))[-8:]
            lid = self.lid_var.get().strip() or None
            lic = issue_license(
                private_key_path=self.cfg["private_key_path"],
                chip_id=chip,
                mac=mac,
                plan=self.plan_var.get(),
                issuer=self.cfg.get("issuer", "KonekSik-Fi"),
                lifetime_days=int(self.days_var.get() or 0),
                license_id=lid,
            )
            if not verify_license(lic, self.cfg["public_key_path"]):
                raise RuntimeError("Verify failed after sign")
            lid = lic["license_id"]
            out_json = ROOT / "logs" / f"license_{lid}.json"
            out_json.parent.mkdir(parents=True, exist_ok=True)
            out_json.write_text(json.dumps(lic, indent=2), encoding="utf-8")
            bundle = export_replacement_bundle(lic, ROOT / "bundles" / f"{lid}.ksk")
            self._log(json.dumps(lic, indent=2))
            self._log(f"Saved {out_json}")
            self._log(f"Buyer bundle {bundle}")
            self.status_var.set(f"Issued {lid} — give {bundle.name} to the buyer.")
            messagebox.showinfo("License issued", f"License ID: {lid}\n\nBuyer bundle:\n{bundle}")
        except Exception as e:
            messagebox.showerror("License", str(e))
            self._log(f"ERROR: {e}")
            self.status_var.set("Failed — see log.")


def main() -> None:
    LicenseGeneratorApp().mainloop()


if __name__ == "__main__":
    main()
