#include "license_store.h"

#if defined(ESP32)
#include <Preferences.h>
static Preferences prefs;
static bool prefsReady = false;

bool licenseStoreBegin() {
  prefsReady = prefs.begin("ksklic", false);
  return prefsReady;
}

bool licenseStoreSave(const String &json) {
  if (!prefsReady && !licenseStoreBegin()) return false;
  return prefs.putString("blob", json) > 0;
}

String licenseStoreLoad() {
  if (!prefsReady && !licenseStoreBegin()) return String();
  return prefs.getString("blob", "");
}

bool licenseStoreClear() {
  if (!prefsReady && !licenseStoreBegin()) return false;
  return prefs.remove("blob");
}

bool licenseStoreHas() {
  return licenseStoreLoad().length() > 8;
}

#else
#include <EEPROM.h>
static const int LIC_MAGIC = 0x4B534B31;  // KSK1
static const int LIC_OFFSET = 200;
static const int LIC_MAX = 300;

bool licenseStoreBegin() {
  EEPROM.begin(512);
  return true;
}

bool licenseStoreSave(const String &json) {
  licenseStoreBegin();
  int n = json.length();
  if (n > LIC_MAX - 8) return false;
  EEPROM.put(LIC_OFFSET, LIC_MAGIC);
  EEPROM.put(LIC_OFFSET + 4, n);
  for (int i = 0; i < n; i++) EEPROM.write(LIC_OFFSET + 8 + i, json[i]);
  EEPROM.commit();
  return true;
}

String licenseStoreLoad() {
  licenseStoreBegin();
  int magic = 0, n = 0;
  EEPROM.get(LIC_OFFSET, magic);
  EEPROM.get(LIC_OFFSET + 4, n);
  if (magic != LIC_MAGIC || n <= 0 || n > LIC_MAX - 8) return String();
  String s;
  s.reserve(n);
  for (int i = 0; i < n; i++) s += (char)EEPROM.read(LIC_OFFSET + 8 + i);
  return s;
}

bool licenseStoreClear() {
  licenseStoreBegin();
  EEPROM.put(LIC_OFFSET, (int)0);
  EEPROM.put(LIC_OFFSET + 4, (int)0);
  EEPROM.commit();
  return true;
}

bool licenseStoreHas() {
  return licenseStoreLoad().length() > 8;
}
#endif
