"""
Buyer Replacement Flasher — flash firmware + write a sealed .ksk license (no private key).
"""

from __future__ import annotations

import threading
import time
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from app import __version__
from app.boards import list_profiles
from app.config import ROOT, load_config
from app.crypto_license import load_replacement_bundle, license_to_provision_line
from app.flasher import flash_firmware
from app.serial_provision import list_serial_ports, read_identity, write_license
from app.ui_theme import build_shell, make_card, make_log


GUIDE_STEPS = (
    ("Get your .ksk", "Your seller sends the sealed .ksk from the original purchase (same license ID)."),
    ("Load the bundle", "Browse and open the .ksk. This app cannot mint licenses — only reuse sealed ones."),
    ("Connect the new ESP", "Plug USB → Refresh → pick the COM port. Choose the matching board type."),
    ("Select firmware", "Browse to the coinslot .bin (same firmware family as your kit)."),
    ("Flash + write", "Click Flash + write sealed license. Wait until it finishes."),
    ("Detect on router", "Admin → Sub Vendo → enter MAC + License ID → Detect ESP32 (uses 1 grace if MAC changed)."),
)

GUIDE_NOTES = (
    "Max 3 grace replacements per license on the router.",
    "After grace is used up, ask seller for a NEW license (License Generator).",
    "No private key in this app — safe to give buyers.",
)


class BuyerReplacementApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"CEBJ.NET Buyer Replacement Flasher v{__version__}")
        self.geometry("1040x720")
        self.minsize(920, 640)

        self.cfg = load_config()
        self.profiles = list_profiles()
        self.bundle_license: dict | None = None
        self._ports: list[dict] = []

        self.port_var = tk.StringVar()
        self.board_var = tk.StringVar()
        self.chip_var = tk.StringVar(value=self.cfg.get("chip", "esp32"))
        self.fw_var = tk.StringVar(value=self.cfg.get("firmware_path", ""))
        self.bundle_var = tk.StringVar()
        self.lid_var = tk.StringVar(value="No bundle loaded yet")
        self.status_var = tk.StringVar(value="Load a .ksk bundle from your seller to begin.")

        content, _ = build_shell(
            self,
            brand="CEBJ.NET / KonekSik",
            title="Buyer Replacement Flasher",
            subtitle="Flash a replacement ESP with the same sealed license — grace is counted when you Detect on the router.",
            guide_title="Step-by-step (always here)",
            guide_steps=GUIDE_STEPS,
            guide_notes=GUIDE_NOTES,
        )

        box0 = make_card(content, "1 · Sealed license (.ksk)", "File from your seller — do not edit it.")
        box0.pack(fill=tk.X, pady=(0, 10))
        brow = ttk.Frame(box0)
        brow.pack(fill=tk.X)
        ttk.Entry(brow, textvariable=self.bundle_var).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        ttk.Button(brow, text="Browse…", style="Secondary.TButton", command=self.browse_bundle).pack(side=tk.LEFT)
        ttk.Label(box0, textvariable=self.lid_var, style="CardMuted.TLabel").pack(anchor=tk.W, pady=(8, 0))

        box1 = make_card(content, "2 · Board, COM port & firmware")
        box1.pack(fill=tk.X, pady=(0, 10))

        row = ttk.Frame(box1)
        row.pack(fill=tk.X)
        ttk.Label(row, text="Board", style="Card.TLabel").pack(side=tk.LEFT)
        self.board_combo = ttk.Combobox(
            row,
            textvariable=self.board_var,
            values=[p.get("name", p["id"]) for p in self.profiles],
            width=36,
            state="readonly",
        )
        self.board_combo.pack(side=tk.LEFT, padx=8)
        if self.profiles:
            self.board_var.set(self.profiles[0].get("name", self.profiles[0]["id"]))
            self.chip_var.set(self.profiles[0].get("esptool_chip", "esp32"))
        self.board_combo.bind("<<ComboboxSelected>>", lambda e: self.on_board())

        row2 = ttk.Frame(box1)
        row2.pack(fill=tk.X, pady=(8, 0))
        ttk.Label(row2, text="COM", style="Card.TLabel").pack(side=tk.LEFT)
        self.port_combo = ttk.Combobox(row2, textvariable=self.port_var, width=36, state="readonly")
        self.port_combo.pack(side=tk.LEFT, padx=8)
        ttk.Button(row2, text="Refresh", style="Secondary.TButton", command=self.refresh_ports).pack(side=tk.LEFT)

        row3 = ttk.Frame(box1)
        row3.pack(fill=tk.X, pady=(8, 0))
        ttk.Label(row3, text="Firmware", style="Card.TLabel").pack(side=tk.LEFT)
        ttk.Entry(row3, textvariable=self.fw_var).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=8)
        ttk.Button(row3, text="Browse…", style="Secondary.TButton", command=self.browse_fw).pack(side=tk.LEFT)

        btns = ttk.Frame(content)
        btns.pack(fill=tk.X, pady=(0, 8))
        ttk.Button(
            btns,
            text="Flash + write sealed license",
            style="Accent.TButton",
            command=self.on_full,
        ).pack(side=tk.LEFT)
        ttk.Button(btns, text="Write license only", style="Secondary.TButton", command=self.on_write_only).pack(
            side=tk.LEFT, padx=8
        )
        ttk.Label(content, textvariable=self.status_var, style="Muted.TLabel").pack(anchor=tk.W, pady=(0, 8))

        log_card = make_card(content, "3 · Activity log")
        log_card.pack(fill=tk.BOTH, expand=True)
        self.log = make_log(log_card, height=12)

        self.refresh_ports()
        self.on_board()

    def _log(self, m: str) -> None:
        self.log.insert(tk.END, m + "\n")
        self.log.see(tk.END)

    def current_profile(self) -> dict:
        for p in self.profiles:
            if p.get("name", p["id"]) == self.board_var.get():
                return p
        return self.profiles[0] if self.profiles else {}

    def on_board(self) -> None:
        p = self.current_profile()
        self.chip_var.set(p.get("esptool_chip", "esp32"))

    def refresh_ports(self) -> None:
        try:
            ports = list_serial_ports()
        except Exception as e:
            messagebox.showerror("Serial", str(e))
            return
        self._ports = ports
        labels = [f"{p['device']} — {p['description']}" for p in ports]
        self.port_combo["values"] = labels
        if labels:
            self.port_combo.current(0)
            self.port_var.set(labels[0])
        self._log(f"Found {len(ports)} serial port(s).")

    def selected_port(self) -> str:
        label = self.port_var.get()
        if not label:
            raise ValueError("Select COM port")
        return label.split(" — ")[0].strip()

    def browse_bundle(self) -> None:
        path = filedialog.askopenfilename(
            title="Select sealed .ksk bundle",
            filetypes=[("KonekSik bundle", "*.ksk"), ("JSON", "*.json"), ("All", "*.*")],
            initialdir=str(ROOT / "bundles"),
        )
        if not path:
            return
        try:
            lic = load_replacement_bundle(path)
            self.bundle_license = lic
            self.bundle_var.set(path)
            lid = lic.get("license_id") or lic.get("chip_id")
            self.lid_var.set(f"License ID: {lid}")
            self.status_var.set(f"Loaded {lid} — connect ESP and flash.")
            self._log(f"Loaded bundle {path}")
        except Exception as e:
            messagebox.showerror("Bundle", str(e))

    def browse_fw(self) -> None:
        path = filedialog.askopenfilename(
            title="Firmware .bin",
            filetypes=[("Firmware", "*.bin"), ("All", "*.*")],
            initialdir=str(ROOT / "firmware"),
        )
        if path:
            self.fw_var.set(path)

    def _busy(self, title: str, job) -> None:
        def runner():
            try:
                job()
            except Exception as e:
                self.after(0, lambda: messagebox.showerror(title, str(e)))
                self.after(0, lambda: self._log(f"ERROR: {e}"))
                self.after(0, lambda: self.status_var.set("Failed — see log."))

        threading.Thread(target=runner, daemon=True).start()

    def on_write_only(self) -> None:
        def job():
            if not self.bundle_license:
                raise ValueError("Load a .ksk bundle first")
            port = self.selected_port()
            line = license_to_provision_line(self.bundle_license)
            ok = write_license(
                port,
                line,
                baud=int(self.cfg.get("baud", 115200)),
                log=lambda m: self.after(0, lambda msg=m: self._log(msg)),
            )
            msg = "OK — now Detect ESP32 in Admin Sub Vendo" if ok else "ESP did not confirm KSK_LICENSE_OK"
            self.after(0, lambda: self.status_var.set(msg))
            self.after(0, lambda: messagebox.showinfo("License", msg))

        self._busy("Write", job)

    def on_full(self) -> None:
        def job():
            if not self.bundle_license:
                raise ValueError("Load a .ksk bundle first")
            port = self.selected_port()
            fw = self.fw_var.get().strip()
            if not fw or not Path(fw).exists():
                raise ValueError("Select firmware .bin")
            p = self.current_profile()
            self.after(0, lambda: self.status_var.set("Flashing…"))
            self.after(0, lambda: self._log("Flashing…"))
            flash_firmware(
                port=port,
                firmware_path=fw,
                chip=self.chip_var.get() or p.get("esptool_chip", "esp32"),
                baud=int(self.cfg.get("flash_baud", 460800)),
                flash_mode=p.get("flash_mode") or self.cfg.get("flash_mode", "dio"),
                flash_freq=p.get("flash_freq") or self.cfg.get("flash_freq", "40m"),
                flash_size=p.get("flash_size") or self.cfg.get("flash_size", "4MB"),
                log=lambda m: self.after(0, lambda msg=m: self._log(msg)),
            )
            time.sleep(2.0)
            info = read_identity(
                port,
                baud=int(self.cfg.get("baud", 115200)),
                log=lambda m: self.after(0, lambda msg=m: self._log(msg)),
            )
            self.after(0, lambda: self._log(f"New board chip={info.get('chip_id')} mac={info.get('mac')}"))
            line = license_to_provision_line(self.bundle_license)
            ok = write_license(
                port,
                line,
                baud=int(self.cfg.get("baud", 115200)),
                log=lambda m: self.after(0, lambda msg=m: self._log(msg)),
            )
            lid = self.bundle_license.get("license_id")
            msg = (
                f"Done. License {lid} written.\n\nAdmin → Sub Vendo → Detect ESP32\n"
                f"MAC: {info.get('mac')}\nLicense ID: {lid}"
                if ok
                else "Flash OK but license write not confirmed"
            )
            self.after(0, lambda: self.status_var.set("Replacement finished." if ok else "Check log."))
            self.after(0, lambda: messagebox.showinfo("Replacement", msg))

        self._busy("Flash+License", job)


def main() -> None:
    BuyerReplacementApp().mainloop()


if __name__ == "__main__":
    main()
