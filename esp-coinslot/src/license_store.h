#pragma once
#include <Arduino.h>

// Simple EEPROM/NVS-backed license blob storage (JSON text, max ~512 bytes)

bool licenseStoreBegin();
bool licenseStoreSave(const String &json);
String licenseStoreLoad();
bool licenseStoreClear();
bool licenseStoreHas();
