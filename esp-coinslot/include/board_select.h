#pragma once
/*
 * Select board pin map from PlatformIO build flags.
 */

#if defined(BOARD_ESP8266_LANBASE_W5500)
  #include "boards/esp8266_lanbase_w5500.h"
#elif defined(BOARD_ESP8266_WIFI)
  #include "boards/esp8266_wifi.h"
#elif defined(BOARD_ESP32_W5500)
  #include "boards/esp32_w5500.h"
#elif defined(BOARD_ESP32S3_W5500)
  #include "boards/esp32s3_w5500.h"
#elif defined(BOARD_ESP32_ETH)
  #include "boards/esp32_eth.h"
#else
  #error "No board selected. Build with a PlatformIO env (e.g. esp8266_lanbase_w5500)."
#endif

#ifndef BOARD_ID
  #define BOARD_ID "unknown"
#endif
