#pragma once
#include <Arduino.h>

// Serial provision protocol used by esp-license-provisioner:
//   KSK_ID?  -> KSK_ID chip=<hex> mac=AA:BB:...
//   KSK_LICENSE_WRITE <base64json> -> KSK_LICENSE_OK | KSK_LICENSE_ERR ...
//   KSK_LICENSE_READ -> KSK_LICENSE_BLOB <base64json> | KSK_LICENSE_EMPTY
//   KSK_LICENSE_CLEAR -> KSK_LICENSE_OK
//   KSK_PINS? -> human-readable pin map (also printed at boot)

void licenseSerialBegin();
void licenseSerialLoop();
String deviceMacString();
String deviceChipIdString();
