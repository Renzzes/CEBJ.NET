#!/usr/bin/env python3
"""Reyee upgrade_crypt_v1 decrypt — ported from stock rg-upgrade-crypto (static RE).

Verified: EW_3.0(1)B11P313 install_encypto.bin -> rgos.bin
SHA-256 d2256fc6b4ec45c2cc40ab5f63abe7011313e8b5b45c58d9b42f9d00e528fe2e
"""
from __future__ import annotations

MAGIC = b"upgrade_crypt_v1!@2021"
INIT_STATE = bytes([0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00])


def decrypt_upgrade_crypt_v1(payload: bytes, init: bytes = INIT_STATE) -> bytes:
    state = bytearray(init)
    out = bytearray(len(payload))
    for idx, cin in enumerate(payload):
        s = state[0] + state[4] + state[5] + state[6]
        r2 = s & 0x80000001
        if r2 & 0x80000000:
            r2 = (((r2 - 1) | 0xFFFFFFFE) + 1) & 0xFFFFFFFF
        key_byte = r2 & 0xFF
        for i in range(6):
            state[i] = state[i + 1]
        state[7] = key_byte
        key_acc = 0
        for i in range(8):
            key_acc = ((state[i] << i) | key_acc) & 0xFF
        out[idx] = cin ^ key_acc
    return bytes(out)


def decrypt_installer(blob: bytes) -> bytes:
    if not blob.startswith(MAGIC):
        raise ValueError("missing upgrade_crypt_v1 magic header")
    return decrypt_upgrade_crypt_v1(blob[len(MAGIC):])
