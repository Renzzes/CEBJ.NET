# KonekSik-Fi Stage 2 — Registered ESP32 Delete/Unbind Lifecycle Fix

**Date:** 2026-10-14  
**Scope:** Admin → Registered ESP32 Devices → Delete; ESP32 Licensed Devices Unbind; transactional DB; regression tests.  
**Constraints honored:** No firmware flash, no router config change, no production device/license deletion, Kemo SET-HOLD patch preserved, RTR/Flash Auth untouched, Autopause Grace Period (sec) unchanged.

---

## 1. Exact failing Delete path and root cause

### Traced path (source)

| Step | Location | Behavior |
|------|----------|----------|
| 1 | `admin-ext.js` `loadESPDevices` Delete button | `onclick="deleteESPDevice(id, false, {name,mac,license})"` |
| 2 | `window.deleteESPDevice` | Confirm dialog → `GET /cgi-bin/api?action=delete_esp_device&slot_id=…` |
| 3 | Optional force | `&force=1&confirm_unbind=1` when bound / second confirm |
| 4 | `router.lua` | `delete_esp_device` → `esp.lua` `M.delete_esp_device` |
| 5 | Backend gate | If `license_status` is `licensed`/`free` with non-empty `license_key` and **no** `force` → **`REQUIRES_UNBIND`**, no DB writes |
| 6 | Force path | Clear related slots + unbind license row (`live_mac=NULL`, status `unbound`, keep `signed_ksk`) + `DELETE` slot |
| 7 | Licensed table | Separate Unbind → `esp_license_unbind` (does not delete slot by itself) |

### Root cause (why Delete “did nothing” while license stayed Active)

1. **Soft delete is intentional for bound devices.** Without `force=1`, the API returns `status=error`, `code=REQUIRES_UNBIND` and leaves `esp_slots` + `esp_licenses.live_mac` unchanged. The Licensed Devices row correctly stays **Active** (Active = `used`/`active` **and** non-empty `live_mac`).
2. **UI contract was incomplete / easy to mis-handle.** A plain “Delete?” confirm that then called soft delete looked like a successful operator action while the backend correctly refused. Success toasts must only fire on `status===ok`.
3. **No real multi-statement transaction** (pre-fix). Each `sqlite.execute` opened/closed its own connection, so a mid-flight failure could leave slot/license inconsistent.
4. **Offline is irrelevant to the gate.** Bound offline devices hit the same `REQUIRES_UNBIND` / force path; offline must not block authorized cleanup once force is confirmed.

**Classification:** Not a missing route. Identifier is `slot_id`. Primary UX/lifecycle gap: licensed Delete must be an explicit **Unbind-and-delete** (`force=1`) with dual-table refresh; soft path must never toast success.

**Runtime evidence:** Local environment cannot reach a live admin session on the production/router UI for this task. Network HAR / application logs for a live Delete click are **BLOCKED**. Findings above are **source-level + mock-DB verified**.

---

## 2. Frontend / API / database evidence

### Frontend (`admin-ext.js?v=46`)

- Licensed rows (`looksBound`): confirm copy states Unbind-then-delete; calls `force=1&confirm_unbind=1`.
- Soft path returning `REQUIRES_UNBIND`: second confirm, or cancel toast *“Delete cancelled — Unbind required…”* — **no success toast**.
- Success only when `d.status === "ok"`; then `loadESPDevices()` + `loadLicensePool()`.
- `removeESPDevice` aliases `deleteESPDevice` (Sub Vendo Del path).

### API

```
GET /cgi-bin/api?action=delete_esp_device&slot_id=<id>
GET /cgi-bin/api?action=delete_esp_device&slot_id=<id>&force=1&confirm_unbind=1
```

Responses:

- Soft bound: `{ status:"error", code:"REQUIRES_UNBIND", requires_unbind:true, … }`
- Force ok: `{ status:"ok", unbound:true, message:"ESP device deleted. Live binding cleared; signed KSK retained." }`
- Txn fail: `{ status:"error", code:"DATABASE_ERROR", message:"Delete failed; no changes were kept. …" }`

### Database writes (force delete, one transaction)

1. Clear `esp_slots` tied by `license_key` / live / last / slot MAC → `unlicensed`, `license_key=NULL`
2. `esp_licenses`: `status='unbound'`, `used_slot_id=NULL`, `live_mac=NULL`, `last_live_mac` preserved from live, `ksk_ever_bound=1`; **`signed_ksk` / `grace_used` retained**
3. `DELETE FROM esp_slots WHERE id=…`
4. Verify row gone; else error → ROLLBACK

Unbind (`esp_license_unbind`) uses the same clear+unbind writes inside `sqlite.transaction` (null/stale `used_slot_id` cleared by key+MAC, not only by slot id).

**License deletion is separate** (`remove` / Remove button only for unused available history-free rows). Device Delete does **not** delete the KSK row.

---

## 3. Minimal fix implemented

| File | Change |
|------|--------|
| `fastfi/db/sqlite.lua` | `M.transaction` — `BEGIN IMMEDIATE` / `COMMIT` / `ROLLBACK` on one connection |
| `fastfi/api/routes/esp.lua` | `delete_esp_device` wrapped in `sqlite.transaction`; post-delete verify; `DATABASE_ERROR` on failure |
| `fastfi/api/routes/esp_license.lua` | Unbind clear+unbind in `sqlite.transaction`; null/stale `used_slot_id` still clears by key/MAC |
| `www/admin-ext.js` | Bound → Unbind-and-delete + `force=1`; `REQUIRES_UNBIND` handling; dual refresh; no success before ok |
| `www/admin.html` | Cache-bust `admin-ext.js?v=46` |
| `tools/test-esp-detect-remove.lua/.py` | Mock txn + rollback; CASE12–22 lifecycle; UI/API contract checks |

---

## 4. Database consistency and rollback

- Multi-record Delete and Unbind run under `BEGIN IMMEDIATE`.
- Any `exec`/`query` error → `ROLLBACK`; API returns `DATABASE_ERROR` with “no changes were kept”.
- Mock harness snapshots license/slot tables and restores on injected failure (CASE19 delete, CASE22 unbind mid-txn after slot clear).
- Unrelated devices/licenses unchanged (CASE14, CASE18).
- Retry after successful delete → “ESP device not found” (CASE20).
- After unbind/delete, empty `live_mac` cannot satisfy `ksk_now` live binding → coin credit denied (CASE21 + `ksk_now.decide` rule).

---

## 5. Regression tests — commands and results

```text
python tools/test-esp-detect-remove.py
```

**Result: EXIT 0** (2026-10-14)

| Case | Scenario | Result |
|------|----------|--------|
| 12 | Licensed soft delete | PASS `REQUIRES_UNBIND`, no writes |
| 13 | Force delete | PASS slot gone, license unbound, signed/grace kept |
| 14 | Unlicensed offline delete | PASS; unrelated kept |
| 15 | Licensed before unbind | PASS blocked |
| 16 | Unbind `used_slot_id` null | PASS |
| 17 | Unbind stale `used_slot_id` | PASS |
| 18 | Soft then force unbind-and-delete | PASS; unrelated kept |
| 19 | Delete mid-txn DB failure | PASS rollback + `DATABASE_ERROR` |
| 20 | Retry after success | PASS not found |
| 21 | Unbound cannot authorize credit | PASS empty `live_mac` |
| 22 | Unbind mid-txn failure | PASS rollback |
| Py UI | force, REQUIRES_UNBIND, dual refresh, txn helpers | PASS |

Disposable mock DB only — **no production records touched**.

---

## 6. Grace / auth / portal review (Priority 4 — no unrelated edits)

| Area | Finding | Action |
|------|---------|--------|
| KSK grace replacement | `ksk_bind`: no replacement/transfer; `grace_used` frozen, never incremented for replace | **OK** — not edited |
| Autopause Grace Period (sec) | Still present in `admin.html` | **Unchanged** |
| Licensed table “Grace Used” column | `grace_used` still read for Remove eligibility only; Active badge uses `live_mac` | **OK** |
| `insertcoin` denials | Peer/KSK fail before `increment_credit`; `insertcoin_log` rate-limited (2s/key); no KSK blobs | **OK** — not edited |
| Captive portal timing | `KONEKSIK_PORTAL_TIMING` opt-in; credit poll / session gen safeguards present in `renzfi-app.js` | **OK** — not edited |
| RTR / Flash Auth | Not modified | **Preserved** |
| Kemo SET-HOLD | Not modified in this task | **Preserved** |

No reproducible defect found in these areas that required a code change for this Delete lifecycle task.

**Residual (not fixed here):** `admin-ext.js` still contains an info toast string referencing “replacement flasher … grace ≤ 3” (~line 3043). Bind policy already denies grace replacement; treat as leftover copy only — separate cleanup if desired.

---

## 7. Runtime limitations and hardware still BLOCKED

| Item | Status |
|------|--------|
| Live Admin Delete click + browser Network tab | **BLOCKED** — no live router admin session used (policy: no production deletes) |
| Router `logread` for `delete_esp_device` / unbind | **BLOCKED** |
| Phone captive portal timing (`KONEKSIK_PORTAL_TIMING`) | **BLOCKED** — no phone/browser-on-router run |
| Click→dialog / lock / countdown / pulse→router credit / credit→portal | **BLOCKED** (not stubbed as PASS) |
| Kemo SET-HOLD E2E flash | **BLOCKED** — awaits explicit flash authorization; License stored: NO on last pre-flash check |

---

## 8. Operator semantics (post-fix)

| Action | Effect |
|--------|--------|
| **Unbind** | Clears live binding + related slots; keeps signed `.ksk` / history; license shows Unbound (not Active) |
| **Delete device (unlicensed)** | Removes `esp_slots` row only |
| **Delete device (licensed)** | Confirm Unbind-and-delete → force path: unbind + delete slot; license retained unbound |
| **Remove license** | Separate; only unused available rows without history |

Offline licensed devices **can** be cleaned up after the Unbind-and-delete confirm.

---

## 9. Completion criteria

- Failing path identified: soft Delete on bound device → `REQUIRES_UNBIND` while UI needed explicit force + dual refresh.
- Minimal fix implemented and covered by CASE12–22 + UI contract checks.
- Tests prove expected mock-DB and frontend contract behavior.
- Live UI/hardware verification remains **BLOCKED** until an authorized non-production admin session and (for portal) phone timing run are available.
