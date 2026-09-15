"""Ed25519 offline license generate / verify."""

from __future__ import annotations

import base64
import json
import time
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)


def ensure_keypair(private_path: str | Path, public_path: str | Path) -> tuple[Path, Path]:
    priv = Path(private_path)
    pub = Path(public_path)
    priv.parent.mkdir(parents=True, exist_ok=True)
    if priv.exists() and pub.exists():
        return priv, pub

    key = Ed25519PrivateKey.generate()
    priv_bytes = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    pub_bytes = key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    priv.write_bytes(priv_bytes)
    pub.write_bytes(pub_bytes)
    try:
        priv.chmod(0o600)
    except Exception:
        pass
    return priv, pub


def _load_private(path: str | Path) -> Ed25519PrivateKey:
    data = Path(path).read_bytes()
    return serialization.load_pem_private_key(data, password=None)  # type: ignore[return-value]


def _load_public(path: str | Path) -> Ed25519PublicKey:
    data = Path(path).read_bytes()
    return serialization.load_pem_public_key(data)  # type: ignore[return-value]


def canonical_payload(license_obj: dict[str, Any]) -> bytes:
    """Stable bytes to sign (exclude signature fields)."""
    body = {k: v for k, v in license_obj.items() if k not in ("sig", "sig_b64")}
    return json.dumps(body, separators=(",", ":"), sort_keys=True).encode("utf-8")


def issue_license(
    *,
    private_key_path: str | Path,
    chip_id: str,
    mac: str,
    plan: str,
    issuer: str,
    lifetime_days: int = 0,
    extra: dict[str, Any] | None = None,
    license_id: str | None = None,
) -> dict[str, Any]:
    chip_id = (chip_id or "").strip().upper().replace(":", "")
    mac = (mac or "").strip().upper()
    if not chip_id and not mac:
        raise ValueError("chip_id or mac is required")

    now = int(time.time())
    expires_at = 0 if not lifetime_days or lifetime_days <= 0 else now + int(lifetime_days) * 86400

    # Stable license ID (survives board replacement / grace). New sales get a new ID.
    lid = (license_id or "").strip().upper()
    if not lid:
        base = chip_id or mac.replace(":", "")
        lid = "KSK-" + base[:16]

    license_obj: dict[str, Any] = {
        "v": 1,
        "type": "esp_coinslot",
        "license_id": lid,
        "chip_id": chip_id or mac.replace(":", ""),
        "mac": mac,
        "plan": plan or "standard",
        "issuer": issuer or "KonekSik-Fi",
        "issued_at": now,
        "expires_at": expires_at,
        "grace_max": 3,
    }
    if extra:
        license_obj.update(extra)
        # Keep license_id authoritative if caller passed it in extra
        if extra.get("license_id"):
            license_obj["license_id"] = str(extra["license_id"]).strip().upper()

    priv = _load_private(private_key_path)
    sig = priv.sign(canonical_payload(license_obj))
    license_obj["sig_b64"] = base64.b64encode(sig).decode("ascii")
    return license_obj


def export_replacement_bundle(license_obj: dict[str, Any], out_path: str | Path) -> Path:
    """Buyer flasher package: sealed signed license (no private key)."""
    path = Path(out_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    bundle = {
        "v": 1,
        "type": "ksk_replacement_bundle",
        "license_id": license_obj.get("license_id") or license_obj.get("chip_id"),
        "license": license_obj,
        "sealed_at": int(time.time()),
        "note": "Buyer replacement flasher — write this license to a new ESP only. No minting.",
    }
    path.write_text(json.dumps(bundle, indent=2), encoding="utf-8")
    return path


def load_replacement_bundle(path: str | Path) -> dict[str, Any]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if data.get("type") != "ksk_replacement_bundle":
        raise ValueError("Not a KonekSik replacement bundle (.ksk)")
    lic = data.get("license")
    if not isinstance(lic, dict) or not lic.get("sig_b64"):
        raise ValueError("Bundle missing signed license")
    return lic


def verify_license(license_obj: dict[str, Any], public_key_path: str | Path) -> bool:
    sig_b64 = license_obj.get("sig_b64") or ""
    if not sig_b64:
        return False
    pub = _load_public(public_key_path)
    try:
        pub.verify(base64.b64decode(sig_b64), canonical_payload(license_obj))
        return True
    except Exception:
        return False


def license_to_provision_line(license_obj: dict[str, Any]) -> str:
    """One-line command for ESP serial provision protocol."""
    blob = base64.b64encode(json.dumps(license_obj, separators=(",", ":")).encode("utf-8")).decode("ascii")
    return f"KSK_LICENSE_WRITE {blob}"


def export_public_key_raw_b64(public_key_path: str | Path) -> str:
    """32-byte raw Ed25519 public key, base64 — for embedding in router/ESP firmware."""
    pub = _load_public(public_key_path)
    raw = pub.public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return base64.b64encode(raw).decode("ascii")
