"""
KonekSik-Fi ESP License Provisioner
Flash coinslot firmware + generate/burn offline Ed25519 license (no cloud).
Shows per-board coin / relay / W5500 / ETH pin maps.
"""

from __future__ import annotations

import json
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from app import __version__
from app.boards import format_pin_map, get_profile, list_profiles
from app.config import ROOT, load_config, save_config
from app.crypto_license import (
    ensure_keypair,
    export_public_key_raw_b64,
    issue_license,
    license_to_provision_line,
    verify_license,
)
from app.flasher import flash_firmware
from app.issue_log import append_issue
from app.serial_provision import list_serial_ports, read_identity, write_license


class ProvisionerApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"KonekSik-Fi ESP License Provisioner v{__version__}")
        self.geometry("920x720")
        self.minsize(820, 640)

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
        self.last_license: dict | None = None
        self._ports: list[dict] = []

        self._build()
        self.refresh_ports()
        if self.profiles:
            # Prefer lanbase as default
            default = None
            for p in self.profiles:
                if p.get("id") == "esp8266_lanbase_w5500":
                    default = p
                    break
            default = default or self.profiles[0]
            self.board_var.set(default.get("name", default["id"]))
            self.on_board_changed()

    def _build(self) -> None:
        pad = {"padx": 10, "pady": 6}
        root = ttk.Frame(self, padding=12)
        root.pack(fill=tk.BOTH, expand=True)

        ttk.Label(
            root,
            text="Offline flasher + license factory — multi-board pin maps",
            font=("Segoe UI", 12, "bold"),
        ).pack(anchor=tk.W)

        # Board selection + pin map
        box0 = ttk.LabelFrame(root, text="Board profile (pins used by this coinslot)", padding=10)
        box0.pack(fill=tk.BOTH, **pad)

        brow = ttk.Frame(box0)
        brow.pack(fill=tk.X)
        ttk.Label(brow, text="Board").pack(side=tk.LEFT)
        self.board_combo = ttk.Combobox(
            brow,
            textvariable=self.board_var,
            values=[p.get("name", p["id"]) for p in self.profiles],
            width=42,
            state="readonly",
        )
        self.board_combo.pack(side=tk.LEFT, padx=8)
        self.board_combo.bind("<<ComboboxSelected>>", lambda e: self.on_board_changed())
        ttk.Label(brow, text="esptool chip").pack(side=tk.LEFT, padx=(12, 4))
        ttk.Entry(brow, textvariable=self.chip_var, width=12, state="readonly").pack(side=tk.LEFT)

        self.pin_text = tk.Text(box0, height=9, wrap=tk.WORD, font=("Consolas", 9), bg="#0f172a", fg="#e2e8f0")
        self.pin_text.pack(fill=tk.BOTH, expand=True, pady=(8, 0))
        self.pin_text.configure(state=tk.DISABLED)

        # Connection
        box = ttk.LabelFrame(root, text="1. Connect ESP", padding=10)
        box.pack(fill=tk.X, **pad)
        row = ttk.Frame(box)
        row.pack(fill=tk.X)
        ttk.Label(row, text="COM port").pack(side=tk.LEFT)
        self.port_combo = ttk.Combobox(row, textvariable=self.port_var, width=36, state="readonly")
        self.port_combo.pack(side=tk.LEFT, padx=8)
        ttk.Button(row, text="Refresh", command=self.refresh_ports).pack(side=tk.LEFT)

        idrow = ttk.Frame(box)
        idrow.pack(fill=tk.X, pady=(8, 0))
        ttk.Button(idrow, text="Read chip ID / MAC", command=self.on_read_id).pack(side=tk.LEFT)
        ttk.Label(idrow, text="Chip ID").pack(side=tk.LEFT, padx=(16, 4))
        ttk.Entry(idrow, textvariable=self.chip_id_var, width=22).pack(side=tk.LEFT)
        ttk.Label(idrow, text="MAC").pack(side=tk.LEFT, padx=(12, 4))
        ttk.Entry(idrow, textvariable=self.mac_var, width=18).pack(side=tk.LEFT)

        # Firmware
        box2 = ttk.LabelFrame(root, text="2. Firmware", padding=10)
        box2.pack(fill=tk.X, **pad)
        fwrow = ttk.Frame(box2)
        fwrow.pack(fill=tk.X)
        ttk.Entry(fwrow, textvariable=self.fw_var).pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(fwrow, text="Browse…", command=self.browse_fw).pack(side=tk.LEFT, padx=6)
        ttk.Button(box2, text="Flash firmware only", command=self.on_flash).pack(anchor=tk.W, pady=(8, 0))

        # License
        box3 = ttk.LabelFrame(root, text="3. License", padding=10)
        box3.pack(fill=tk.X, **pad)
        prow = ttk.Frame(box3)
        prow.pack(fill=tk.X)
        ttk.Label(prow, text="Plan").pack(side=tk.LEFT)
        ttk.Combobox(
            prow,
            textvariable=self.plan_var,
            values=("lite", "standard", "pro", "lifetime"),
            width=12,
        ).pack(side=tk.LEFT, padx=8)
        ttk.Label(prow, text="Expiry days (0 = lifetime)").pack(side=tk.LEFT, padx=(12, 4))
        ttk.Entry(prow, textvariable=self.days_var, width=8).pack(side=tk.LEFT)

        brow2 = ttk.Frame(box3)
        brow2.pack(fill=tk.X, pady=(8, 0))
        ttk.Button(brow2, text="Generate license", command=self.on_generate).pack(side=tk.LEFT)
        ttk.Button(brow2, text="Write license to ESP", command=self.on_write_license).pack(side=tk.LEFT, padx=8)
        ttk.Button(brow2, text="Flash + License (full provision)", command=self.on_full_provision).pack(side=tk.LEFT)

        box4 = ttk.LabelFrame(root, text="Issuer keys (keep private key secret)", padding=10)
        box4.pack(fill=tk.X, **pad)
        ttk.Label(box4, text=f"Private: {self.cfg['private_key_path']}").pack(anchor=tk.W)
        ttk.Label(box4, text=f"Public:  {self.cfg['public_key_path']}").pack(anchor=tk.W)
        ttk.Button(box4, text="Copy public key (raw b64 for firmware)", command=self.copy_pubkey).pack(
            anchor=tk.W, pady=(6, 0)
        )

        box5 = ttk.LabelFrame(root, text="Log", padding=8)
        box5.pack(fill=tk.BOTH, expand=True, **pad)
        self.log = tk.Text(box5, height=10, wrap=tk.WORD, font=("Consolas", 9))
        self.log.pack(fill=tk.BOTH, expand=True)
        self._log(f"Ready. Profiles: {len(self.profiles)}  |  root: {ROOT}")

    def current_profile(self) -> dict | None:
        return self.profile_by_label.get(self.board_var.get())

    def on_board_changed(self) -> None:
        p = self.current_profile()
        if not p:
            return
        self.chip_var.set(p.get("esptool_chip") or p.get("chip") or "esp8266")
        # Prefer profile default firmware if present under project
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
        self._log(f"Board selected: {p.get('id')} ({'W5500' if p.get('network')=='w5500' else p.get('network')})")

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
                log=lambda m: self.after(0, lambda: self._log(m)),
            )
            self.after(0, lambda: self.chip_id_var.set(info.get("chip_id", "")))
            self.after(0, lambda: self.mac_var.set(info.get("mac", "")))
            self.after(0, lambda: self._log(f"Identity: chip={info.get('chip_id')} mac={info.get('mac')}"))

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
            out.write_text(json.dumps(lic, indent=2), encoding="utf-8")
            self._log(f"Saved {out}")
            messagebox.showinfo("License", f"License generated for {lic['chip_id']}")
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
            import time

            port = self.selected_port()
            fw = self.fw_var.get().strip()
            kw = self._flash_kwargs()
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
                log=lambda m: self.after(0, lambda: self._log(m)),
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
            (ROOT / "logs" / f"license_{lic['chip_id']}.json").write_text(json.dumps(lic, indent=2), encoding="utf-8")
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
            self.after(
                0,
                lambda: messagebox.showinfo(
                    "Provision",
                    "Flash done.\nLicense generated"
                    + (" and written to ESP." if ok else " (awaiting KSK_LICENSE_OK from firmware)."),
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
