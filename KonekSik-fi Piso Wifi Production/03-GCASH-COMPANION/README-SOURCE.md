# KonekSik-Fi GCash Companion (owner-owned)

Android app that replaces any vendor “companion APK”.  
It runs on **the operator phone that receives GCash**, imports voucher codes from your Ruijie Admin, watches “Received ₱X” notifications, claims the matching portal order, and SMS-es a WiFi code to the customer.

## Flow

1. Customer opens captive portal → GCash → enters **mobile** + picks package  
2. Customer pays the exact amount to your GCash  
3. This app sees the GCash notification  
4. App calls router `gcash_claim_by_amount` (with your secret) → gets customer mobile  
5. App pops one unused code for that price from the imported pool  
6. App SMS: `Your KonekSik-Fi WiFi code: …`  
7. Customer enters the code in **Wifi Pass**

## Build / install

1. Install [Android Studio](https://developer.android.com/studio)  
2. **Open** this folder: `gcash-companion/`  
3. Let Gradle sync (first time downloads the Android Gradle Plugin)  
4. Connect a phone (or use an emulator for UI only — SMS/notifications need a real device)  
5. Run **app** → install the APK  

Sideload: `Build → Build Bundle(s) / APK(s) → Build APK(s)` then copy `app/build/outputs/apk/debug/app-debug.apk` to the phone.

## Pair with your router (once)

On Admin → **GCash**:

1. Enable GCash, set your number + QR  
2. **Generate** companion secret → copy it  
3. **Generate pool** → **Export** JSON file  

In this app → **Setup**:

1. Paste the secret  
2. Set router URL (usually `http://10.0.0.1` or your LAN IP) — phone must reach the router when claiming  
3. **Import pool JSON** (or use `pool-sample.json` for a dry run)  
4. **Save setup**

## Permissions (required)

Open **Permissions** tab:

| Permission | Why |
|---|---|
| Notification access | Read GCash “Received ₱X” alerts |
| SMS | Text the voucher to the customer |
| Battery unrestricted | Keep listening alive |

Then on **Status**: turn **Enable payment listening** ON.

## Daily use

- Keep **GCash** installed and logged in on this phone  
- Keep notifications enabled for GCash  
- Leave this companion listening  
- When codes run low: Admin → Generate pool → Export → Import again  

## If claim says “no pending order”

The customer must start from the portal (mobile + package) **before** paying.  
Random GCash sends with no portal order are ignored on purpose (no phone number to SMS).

## Project layout

- `app/src/main/java/.../data` — prefs, pool store, event log  
- `.../notif` — notification listener + amount parser  
- `.../net` — `gcash_claim_by_amount` client  
- `.../sms` — SMS sender  
- `pool-sample.json` — sample export for testing import  

You own this app and the router firmware — no vendor APK required.
