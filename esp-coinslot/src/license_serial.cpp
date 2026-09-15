#include "license_serial.h"
#include "license_store.h"
#include "coin_relay.h"
#include "board_select.h"

#if defined(ESP8266)
#include <ESP8266WiFi.h>
#elif defined(ESP32)
#include <WiFi.h>
#endif

static String lineBuf;

static const char B64_TBL[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static String b64Encode(const String &in) {
  String out;
  out.reserve(((in.length() + 2) / 3) * 4);
  const uint8_t *data = (const uint8_t *)in.c_str();
  size_t len = in.length();
  for (size_t i = 0; i < len; i += 3) {
    uint32_t n = ((uint32_t)data[i]) << 16;
    if (i + 1 < len) n |= ((uint32_t)data[i + 1]) << 8;
    if (i + 2 < len) n |= (uint32_t)data[i + 2];
    out += B64_TBL[(n >> 18) & 63];
    out += B64_TBL[(n >> 12) & 63];
    out += (i + 1 < len) ? B64_TBL[(n >> 6) & 63] : '=';
    out += (i + 2 < len) ? B64_TBL[n & 63] : '=';
  }
  return out;
}

static int b64Val(char c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == '+') return 62;
  if (c == '/') return 63;
  return -1;
}

static String b64Decode(const String &in) {
  String out;
  out.reserve(in.length() * 3 / 4);
  int val = 0, valb = -8;
  for (size_t i = 0; i < in.length(); i++) {
    char c = in[i];
    if (c == '=' || c == '\r' || c == '\n' || c == ' ') break;
    int d = b64Val(c);
    if (d < 0) continue;
    val = (val << 6) + d;
    valb += 6;
    if (valb >= 0) {
      out += char((val >> valb) & 0xFF);
      valb -= 8;
    }
  }
  return out;
}

String deviceMacString() {
  uint8_t mac[6] = {0};
#if defined(ESP8266) || defined(ESP32)
  WiFi.macAddress(mac);
#endif
  char buf[18];
  sprintf(buf, "%02X:%02X:%02X:%02X:%02X:%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  return String(buf);
}

String deviceChipIdString() {
#if defined(ESP8266)
  char buf[16];
  sprintf(buf, "%08X", ESP.getChipId());
  return String(buf);
#elif defined(ESP32)
  uint64_t id = ESP.getEfuseMac();
  char buf[20];
  sprintf(buf, "%04X%08X", (uint16_t)(id >> 32), (uint32_t)id);
  return String(buf);
#else
  return deviceMacString();
#endif
}

static void handleLine(String line) {
  line.trim();
  if (line.length() == 0) return;

  if (line == "KSK_ID?") {
    Serial.print(F("KSK_ID chip="));
    Serial.print(deviceChipIdString());
    Serial.print(F(" mac="));
    Serial.println(deviceMacString());
    return;
  }

  if (line == "KSK_PINS?") {
    printBoardPins();
    return;
  }

  if (line == "KSK_LICENSE_ID?") {
    String blob = licenseStoreLoad();
    if (blob.length() < 8) {
      Serial.println(F("KSK_LICENSE_ID none"));
      return;
    }
    // crude extract of "license_id":"..."
    int i = blob.indexOf("\"license_id\"");
    if (i < 0) i = blob.indexOf("\"chip_id\"");
    if (i < 0) {
      Serial.println(F("KSK_LICENSE_ID unknown"));
      return;
    }
    int c1 = blob.indexOf('"', i + 10);
    int c2 = blob.indexOf('"', c1 + 1);
    int c3 = blob.indexOf('"', c2 + 1);
    if (c2 < 0 || c3 < 0) {
      Serial.println(F("KSK_LICENSE_ID parse_err"));
      return;
    }
    Serial.print(F("KSK_LICENSE_ID "));
    Serial.println(blob.substring(c2 + 1, c3));
    return;
  }

  if (line == "KSK_LICENSE_READ") {
    String blob = licenseStoreLoad();
    if (blob.length() < 8) {
      Serial.println(F("KSK_LICENSE_EMPTY"));
    } else {
      Serial.print(F("KSK_LICENSE_BLOB "));
      Serial.println(b64Encode(blob));
    }
    return;
  }

  if (line == "KSK_LICENSE_CLEAR") {
    licenseStoreClear();
    Serial.println(F("KSK_LICENSE_OK"));
    return;
  }

  if (line.startsWith("KSK_LICENSE_WRITE ")) {
    String b64 = line.substring(18);
    b64.trim();
    String json = b64Decode(b64);
    if (json.length() < 8 || json.indexOf('{') < 0) {
      Serial.println(F("KSK_LICENSE_ERR bad_payload"));
      return;
    }
    String mac = deviceMacString();
    String chip = deviceChipIdString();
    String macCompact = mac;
    macCompact.replace(":", "");
    if (json.indexOf(mac) < 0 && json.indexOf(macCompact) < 0 && json.indexOf(chip) < 0) {
      Serial.println(F("KSK_LICENSE_WARN id_mismatch_saving_anyway"));
    }
    if (!licenseStoreSave(json)) {
      Serial.println(F("KSK_LICENSE_ERR store_failed"));
      return;
    }
    Serial.println(F("KSK_LICENSE_OK"));
    return;
  }
}

void licenseSerialBegin() {
  licenseStoreBegin();
  lineBuf.reserve(640);
}

void licenseSerialLoop() {
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (lineBuf.length()) {
        handleLine(lineBuf);
        lineBuf = "";
      }
    } else if (lineBuf.length() < 600) {
      lineBuf += c;
    }
  }
}
