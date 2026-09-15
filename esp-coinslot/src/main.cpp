/*
 * KonekSik-Fi multi-board coinslot firmware (portable core)
 *
 * Implements:
 *  - Board-specific pin maps (ESP8266 / ESP32 / S3 / ETH)
 *  - Coin + relay HAL
 *  - Offline license serial protocol for the laptop provisioner
 *
 * Full FastFi router HTTP register/heartbeat from the legacy lanbase .ino
 * will be layered on next; this build is the portable foundation.
 */

#include <Arduino.h>
#include "board_select.h"
#include "coin_relay.h"
#include "license_serial.h"
#include "license_store.h"

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println();
  Serial.println(F("KonekSik-Fi coinslot (multi-board)"));
  printBoardPins();

  coinRelayBegin(RELAY_DEFAULT_ACTIVE_HIGH);
  licenseSerialBegin();

  Serial.print(F("MAC  "));
  Serial.println(deviceMacString());
  Serial.print(F("CHIP "));
  Serial.println(deviceChipIdString());
  Serial.print(F("License stored: "));
  Serial.println(licenseStoreHas() ? F("YES") : F("NO"));
  Serial.println(F("Commands: KSK_ID?  KSK_PINS?  KSK_LICENSE_WRITE …  KSK_LICENSE_READ  KSK_LICENSE_CLEAR"));
}

void loop() {
  licenseSerialLoop();
  coinRelayLoop();

  // Hardware gate: no license burned by provisioner → ignore/drain coin pulses
  if (!licenseStoreHas()) {
    (void)takeValidatedPulses();
    return;
  }

  int pulses = takeValidatedPulses();
  if (pulses > 0) {
    Serial.print(F("COIN pulses="));
    Serial.println(pulses);
    setRelay(true);
    delay(80);
    setRelay(false);
  }
}
