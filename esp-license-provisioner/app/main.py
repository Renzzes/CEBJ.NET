"""
KonekSik-Fi ESP License Provisioner
Flash coinslot firmware + generate/burn offline Ed25519 license (no cloud).
Shows per-board coin / relay / W5500 / ETH pin maps.
"""

from __future__ import annotations

import json
import threading
import time
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from app import __version__
from app.boards import format_pin_map, list_profiles
from app.config import ROOT, load_config, save_config
from app.crypto_license import (
    ensure_keypair,
    export_public_key_raw_b64,
    export_replacement_bundle,
    issue_license,
    license_to_provision_line,
    verify_license,
)
from app.flasher import flash_firmware
from app.issue_log import append_issue
from app.serial_provision import list_serial_ports, read_identity, write_license
from app.ui_theme import build_shell, make_card, make_log


GUIDE_STEPS = (
    ("Pick board", "Select the ESP board profile so pin map and flash chip type match your hardware."),
    ("Connect USB", "Plug the ESP → Refresh → choose the COM port."),
    ("Read identity", "Click Read chip ID / MAC (or enter manually). Needed before licensing."),
    ("Firmware", "Browse to coinslot .bin, or use the path shown for this board."),
    ("Full provision", "Prefer Flash + License — flashes, reads ID, signs KSK license, writes to ESP, exports .ksk."),
    ("Router Detect", "Admin → Sub Vendo → Detect ESP32 with MAC + License ID so Insert Coin unlocks."),
)

GUIDE_NOTES = (
    "Seller desk tool — keeps the private key. Do not give to buyers.",
    "Buyer replacements: give them the .ksk + Buyer Replacement Flasher.",
    "Keep keys\\issuer_ed25519.pem backed up and secret.",
)


class ProvisionerApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"CEBJ.NET ESP Flasher + License v{__version__}")
        self.geometry("1100x780")
        self.minsize(960, 680)

        self.cfg = load_config()
        ensure_keypair(self.cfg["private_key_path"], self.cfg["public_key_path"])

        self.profiles = list_profiles()
        self.profile_by_label = {p.get("name", p["id"]): p for p in self.profiles}

        self.port_var = tk.StringVar()
        self.board_var = tk.StringVar()
        self.chip_var = tk.StringVar(value=self.cfg.get("chip", "esp8266"))
        self.plan_var = tk.StringVar(value=self.cfg.get("plan_default", "standard"))
        self.days_var = tk.StringVar(value=str(self.cfg.get("lifetime_days", 0)))
        self.fw_var = tk.StringVar(value=self.cfg.get("firmware_path", ""))
        self.chip_id_var = tk.StringVar()
        self.mac_var = tk.StringVar()
        self.status_var = tk.StringVar(value="Select board and COM port, then Flash + License.")
        self.last_license: dict | None = None
        self._ports: list[dict] = []

        content, _ = build_shell(
            self,
            brand="CEBJ.NET / KonekSik",
            title="ESP Flasher + License",
            subtitle="Seller factory tool — flash firmware, mint offline KSK license, burn to ESP.",
            guide_title="Step-by-step (always here)",
            guide_steps=GUIDE_STEPS,
            guide_notes=GUIDE_NOTES,
        )

        # Scrollable main work area
        canvas = tk.Canvas(content, highlightthickness=0, bg="#f1f5f9")
        scroll = ttk.Scrollbar(content, orient=tk.VERTICAL, command=canvas.yview)
        inner = ttk.Frame(canvas)
        inner.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=inner, anchor=tk.NW)
        canvas.configure(yscrollcommand=scroll.set)

        def _on_canvas_configure(event: tk.Event) -> None:
            canvas.itemconfigure(canvas.find_all()[0], width=event.width)

        canvas.bind("<Configure>", _on_canvas_configure)
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scroll.pack(side=tk.RIGHT, fill=tk.Y)

        box0 = make_card(inner, "1 · Board profile", "Pin map below is what the firmware expects.")
        box0.pack(fill=tk.X, pady=(0, 10), padx=(0, 4))
        brow = ttk.Frame(box0)
        brow.pack(fill=tk.X)
        ttk.Label(brow, text="Board", style="Card.TLabel").pack(side=tk.LEFT)
        self.board_combo = ttk.Combobox(
            brow,
            textvariable=self.board_var,
            values=[p.get("name", p["id"]) for p in self.profiles],
            width=42,
            state="readonly",
        )
        self.board_combo.pack(side=tk.LEFT, padx=8)
        self.board_combo.bind("<<ComboboxSelected>>", lambda e: self.on_board_changed())
        ttk.Label(brow, text="esptool chip", style="CardMuted.TLabel").pack(side=tk.LEFT, padx=(12, 4))
        ttk.Entry(brow, textvariable=self.chip_var, width=12, state="readonly").pack(side=tk.LEFT)

        self.pin_text = tk.Text(
            box0,
            height=7,
            wrap=tk.WORD,
            font=("Consolas", 9),
            bg="#0f172a",
            fg="#e2e8f0",
            relief=tk.FLAT,
            padx=8,
            pady=6,
        )
        self.pin_text.pack(fill=tk.BOTH, expand=True, pady=(8, 0))
        self.pin_text.configure(state=tk.DISABLED)

        box = make_card(inner, "2 · Connect ESP")
        box.pack(fill=tk.X, pady=(0, 10), padx=(0, 4))
        row = ttk.Frame(box)
        row.pack(fill=tk.X)
        ttk.Label(row, text="COM port", style="Card.TLabel").pack(side=tk.LEFT)
        self.port_combo = ttk.Combobox(row, textvariable=self.port_var, width=36, state="readonly")
        self.port_combo.pack(side=tk.LEFT, padx=8)
        ttk.Button(row, text="Refresh", style="Secondary.TButton", command=self.refresh_ports).pack(side=tk.LEFT)

        idrow = ttk.Frame(box)
        idrow.pack(fill=tk.X, pady=(8, 0))
        ttk.Button(idrow, text="Read chip ID / MAC", style="Secondary.TButton", command=self.on_read_id).pack(
            side=tk.LEFT
        )
        ttk.Label(idrow, text="Chip ID", style="Card.TLabel").pack(side=tk.LEFT, padx=(16, 4))
        ttk.Entry(idrow, textvariable=self.chip_id_var, width=20).pack(side=tk.LEFT)
        ttk.Label(idrow, text="MAC", style="Card.TLabel").pack(side=tk.LEFT, padx=(12, 4))
        ttk.Entry(idrow, textvariable=self.mac_var, width=16).pack(side=tk.LEFT)

        box2 = make_card(inner, "3 · Firmware")
        box2.pack(fill=tk.X, pady=(0, 10), padx=(0, 4))
        fwrow = ttk.Frame(box2)
        fwrow.pack(fill=tk.X)
        ttk.Entry(fwrow, textvariable=self.fw_var).pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(fwrow, text="Browse…", style="Secondary.TButton", command=self.browse_fw).pack(side=tk.LEFT, padx=6)
        ttk.Button(box2, text="Flash firmware only", style="Secondary.TButton", command=self.on_flash).pack(
            anchor=tk.W, pady=(8, 0)
        )

        box3 = make_card(inner, "4 · License", "Full provision is the usual seller path.")
        box3.pack(fill=tk.X, pady=(0, 10), padx=(0, 4))
        prow = ttk.Frame(box3)
        prow.pack(fill=tk.X)
        ttk.Label(prow, text="Plan", style="Card.TLabel").pack(side=tk.LEFT)
        ttk.Combobox(
            prow,
            textvariable=self.plan_var,
            values=("lite", "standard", "pro", "lifetime"),
            width=12,
        ).pack(side=tk.LEFT, padx=8)
        ttk.Label(prow, text="Expiry days (0 = lifetime)", style="Card.TLabel").pack(side=tk.LEFT, padx=(12, 4))
        ttk.Entry(prow, textvariable=self.days_var, width=8).pack(side=tk.LEFT)

        brow2 = ttk.Frame(box3)
        brow2.pack(fill=tk.X, pady=(10, 0))
        ttk.Button(
            brow2,
            text="Flash + License (full provision)",
            style="Accent.TButton",
            command=self.on_full_provision,
        ).pack(side=tk.LEFT)
        ttk.Button(brow2, text="Generate license", style="Secondary.TButton", command=self.on_generate).pack(
            side=tk.LEFT, padx=8
        )
        ttk.Button(brow2, text="Write license to ESP", style="Secondary.TButton", command=self.on_write_license).pack(
            side=tk.LEFT
        )

        box4 = make_card(inner, "Issuer keys (seller secret)")
        box4.pack(fill=tk.X, pady=(0, 10), padx=(0, 4))
        ttk.Label(box4, text=f"Private: {self.cfg['private_key_path']}", style="CardMuted.TLabel").pack(anchor=tk.W)
        ttk.Label(box4, text=f"Public:  {self.cfg['public_key_path']}", style="CardMuted.TLabel").pack(anchor=tk.W)
        ttk.Button(
            box4,
            text="Copy public key (raw b64)",
            style="Secondary.TButton",
            command=self.copy_pubkey,
        ).pack(anchor=tk.W, pady=(6, 0))

        ttk.Label(inner, textvariable=self.status_var, style="Muted.TLabel").pack(anchor=tk.W, pady=(0, 6))

        box5 = make_card(inner, "5 · Activity log")
        box5.pack(fill=tk.BOTH, expand=True, padx=(0, 4), pady=(0, 8))
        self.log = make_log(box5, height=9)
        self._log(f"Ready. Profiles: {len(self.profiles)}  |  root: {ROOT}")

        self.refresh_ports()
        if self.profiles:
            default = None
            for p in self.profiles:
                if p.get("id") == "esp8266_lanbase_w5500":
                    default = p
                    break
            default = default or self.profiles[0]
            self.board_var.set(default.get("name", default["id"]))
            self.on_board_changed()

    def current_profile(self) -> dict | None:
        return self.profile_by_label.get(self.board_var.get())

    def on_board_changed(self) -> None:
        p = self.current_profile()
        if not p:
            return
        self.chip_var.set(p.get("esptool_chip") or p.get("chip") or "esp8266")
        fw = p.get("default_firmware") or ""
        if fw:
            cand = ROOT / fw
            if cand.is_file():
                self.fw_var.set(str(cand))
            elif not self.fw_var.get():
                self.fw_var.set(str(cand))
        text = format_pin_map(p)
        self.pin_text.configure(state=tk.NORMAL)
        self.pin_text.delete("1.0", tk.END)
        self.pin_text.insert(tk.END, text)
        self.pin_text.configure(state=tk.DISABLED)
        self._log(f"Board selected: {p.get('id')}")

    def _log(self, msg: str) -> None:
        self.log.insert(tk.END, msg + "\n")
        self.log.see(tk.END)

    def _busy(self, title: str, fn) -> None:
        def worker():
            try:
                fn()
            except Exception as e:
                self.after(0, lambda: messagebox.showerror(title, str(e)))
                self.after(0, lambda: self._log(f"ERROR: {e}"))
                self.after(0, lambda: self.status_var.set("Failed — see log."))

        threading.Thread(target=worker, daemon=True).start()

    def refresh_ports(self) -> None:
        try:
            ports = list_serial_ports()
        except Exception as e:
            messagebox.showerror("Serial", str(e))
            return
        labels = [f"{p['device']} — {p['description']}" for p in ports]
        self._ports = ports
        self.port_combo["values"] = labels
        if labels:
            self.port_combo.current(0)
            self.port_var.set(labels[0])
        self._log(f"Found {len(ports)} serial port(s).")

    def selected_port(self) -> str:
        label = self.port_var.get()
        if not label:
            raise ValueError("Select a COM port")
        return label.split(" — ")[0].strip()

    def browse_fw(self) -> None:
        path = filedialog.askopenfilename(
            title="Select firmware .bin",
            filetypes=[("Firmware", "*.bin"), ("All", "*.*")],
            initialdir=str(ROOT / "firmware"),
        )
        if path:
            self.fw_var.set(path)

    def _flash_kwargs(self) -> dict:
        p = self.current_profile() or {}
        return dict(
            chip=self.chip_var.get() or p.get("esptool_chip", "esp8266"),
            baud=int(self.cfg.get("flash_baud", 460800)),
            flash_mode=p.get("flash_mode") or self.cfg.get("flash_mode", "dout"),
            flash_freq=p.get("flash_freq") or self.cfg.get("flash_freq", "40m"),
            flash_size=p.get("flash_size") or self.cfg.get("flash_size", "4MB"),
        )

    def on_read_id(self) -> None:
        def job():
            port = self.selected_port()
            self.after(0, lambda: self._log(f"Reading identity on {port}…"))
            info = read_identity(
                port,
                baud=int(self.cfg.get("baud", 115200)),
                log=lambda m: self.after(0, lambda msg=m: self._log(msg)),
            )
            self.after(0, lambda: self.chip_id_var.set(info.get("chip_id", "")))
            self.after(0, lambda: self.mac_var.set(info.get("mac", "")))
            self.after(0, lambda: self._log(f"Identity: chip={info.get('chip_id')} mac={info.get('mac')}"))
            self.after(0, lambda: self.status_var.set("Identity read — ready to license."))

        self._busy("Read ID", job)

    def on_flash(self) -> None:
        def job():
            port = self.selected_port()
            fw = self.fw_var.get().strip()
            kw = self._flash_kwargs()
            self.after(0, lambda: self._log(f"Flashing {fw} → {port} ({kw['chip']})"))
            flash_firmware(
                port=port,
                firmware_path=fw,
                log=lambda m: self.after(0, lambda msg=m: self._log(msg)),
                **kw,
            )
            self.after(0, lambda: self.status_var.set("Firmware flash finished."))
            self.after(0, lambda: messagebox.showinfo("Flash", "Firmware flash finished."))

        self._busy("Flash", job)

    def _make_license(self) -> dict:
        days = int(self.days_var.get() or 0)
        p = self.current_profile() or {}
        lic = issue_license(
            private_key_path=self.cfg["private_key_path"],
            chip_id=self.chip_id_var.get(),
            mac=self.mac_var.get(),
            plan=self.plan_var.get(),
            issuer=self.cfg.get("issuer", "KonekSik-Fi"),
            lifetime_days=days,
            extra={"board_id": p.get("id", "")},
        )
        if not verify_license(lic, self.cfg["public_key_path"]):
            raise RuntimeError("Internal verify failed after signing")
        self.last_license = lic
        return lic

    def on_generate(self) -> None:
        try:
            if not self.chip_id_var.get().strip() and not self.mac_var.get().strip():
                raise ValueError("Read or enter Chip ID / MAC first")
            lic = self._make_license()
            self._log("Issued license:")
            self._log(json.dumps(lic, indent=2))
            append_issue(
                self.cfg["issue_log_path"],
                {"event": "generate", "license": lic, "port": self.port_var.get(), "board": self.board_var.get()},
            )
            out = ROOT / "logs" / f"license_{lic['chip_id']}.json"
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(lic, indent=2), encoding="utf-8")
            self._log(f"Saved {out}")
            lid = lic.get("license_id") or lic.get("chip_id")
            bundle = export_replacement_bundle(lic, ROOT / "bundles" / f"{lid}.ksk")
            self._log(f"Buyer replacement bundle: {bundle}")
            self.status_var.set(f"License {lid} generated.")
            messagebox.showinfo("License", f"License generated for {lic['chip_id']}\nID: {lid}\nBundle: {bundle.name}")
        except Exception as e:
            messagebox.showerror("License", str(e))
            self._log(f"ERROR: {e}")

    def on_write_license(self) -> None:
        def job():
            lic = self.last_license or self._make_license()
            line = license_to_provision_line(lic)
            port = self.selected_port()
            ok = write_license(
                port,
                line,
                baud=int(self.cfg.get("baud", 115200)),
                log=lambda m: self.after(0, lambda msg=m: self._log(msg)),
            )
            append_issue(
                self.cfg["issue_log_path"],
                {"event": "write", "ok": ok, "license": lic, "port": port, "board": self.board_var.get()},
            )
            if ok:
                self.after(0, lambda: self.status_var.set("License written to ESP."))
                self.after(0, lambda: messagebox.showinfo("License", "ESP accepted license (KSK_LICENSE_OK)."))
            else:
                self.after(
                    0,
                    lambda: messagebox.showwarning(
                        "License",
                        "License generated/logged, but ESP did not confirm KSK_LICENSE_OK.\n"
                        "Flash the multi-board esp-coinslot firmware first.",
                    ),
                )

        self._busy("Write license", job)

    def on_full_provision(self) -> None:
        def job():
            port = self.selected_port()
            fw = self.fw_var.get().strip()
            kw = self._flash_kwargs()
            self.after(0, lambda: self.status_var.set("Full provision running…"))
            self.after(0, lambda: self._log("=== Full provision: flash → identity → license ==="))
            flash_firmware(
                port=port,
                firmware_path=fw,
                log=lambda m: self.after(0, lambda msg=m: self._log(msg)),
                **kw,
            )
            time.sleep(2.0)
            info = read_identity(
                port,
                baud=int(self.cfg.get("baud", 115200)),
                log=lambda m: self.after(0, lambda msg=m: self._log(msg)),
            )
            self.after(0, lambda: self.chip_id_var.set(info.get("chip_id", "")))
            self.after(0, lambda: self.mac_var.set(info.get("mac", "")))
            if not info.get("chip_id") and not info.get("mac"):
                raise RuntimeError("Could not read chip ID/MAC after flash. Enter manually and Write license.")
            p = self.current_profile() or {}
            lic = issue_license(
                private_key_path=self.cfg["private_key_path"],
                chip_id=info.get("chip_id") or "",
                mac=info.get("mac") or "",
                plan=self.plan_var.get(),
                issuer=self.cfg.get("issuer", "KonekSik-Fi"),
                lifetime_days=int(self.days_var.get() or 0),
                extra={"board_id": p.get("id", "")},
            )
            self.last_license = lic
            (ROOT / "logs").mkdir(parents=True, exist_ok=True)
            (ROOT / "logs" / f"license_{lic['chip_id']}.json").write_text(
                json.dumps(lic, indent=2), encoding="utf-8"
            )
            lid = lic.get("license_id") or lic.get("chip_id")
            bundle = export_replacement_bundle(lic, ROOT / "bundles" / f"{lid}.ksk")
            self.after(0, lambda: self._log(f"Buyer replacement bundle: {bundle}"))
            ok = write_license(
                port,
                license_to_provision_line(lic),
                baud=int(self.cfg.get("baud", 115200)),
                log=lambda m: self.after(0, lambda msg=m: self._log(msg)),
            )
            append_issue(
                self.cfg["issue_log_path"],
                {"event": "full_provision", "ok": ok, "license": lic, "port": port, "board": p.get("id")},
            )
            self.after(0, lambda: self.status_var.set(f"Provisioned {lid}"))
            self.after(
                0,
                lambda: messagebox.showinfo(
                    "Provision",
                    "Flash done.\nLicense generated"
                    + (" and written to ESP." if ok else " (awaiting KSK_LICENSE_OK from firmware).")
                    + f"\n\nLicense ID: {lid}\nBundle: {bundle.name}",
                ),
            )

        self._busy("Full provision", job)

    def copy_pubkey(self) -> None:
        try:
            b64 = export_public_key_raw_b64(self.cfg["public_key_path"])
            self.clipboard_clear()
            self.clipboard_append(b64)
            self._log("Public key raw b64 copied.")
            messagebox.showinfo("Public key", "Copied to clipboard.")
        except Exception as e:
            messagebox.showerror("Public key", str(e))

    def destroy(self) -> None:
        try:
            self.cfg["chip"] = self.chip_var.get()
            self.cfg["plan_default"] = self.plan_var.get()
            self.cfg["lifetime_days"] = int(self.days_var.get() or 0)
            self.cfg["firmware_path"] = self.fw_var.get()
            p = self.current_profile()
            if p:
                self.cfg["board_id"] = p.get("id")
            save_config(self.cfg)
        except Exception:
            pass
        super().destroy()


def main() -> None:
    app = ProvisionerApp()
    app.mainloop()


if __name__ == "__main__":
    main()
