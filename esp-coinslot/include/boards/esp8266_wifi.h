#pragma once
/* ESP8266 WiFi coinslot (no Ethernet module) */

#define BOARD_NAME "ESP8266 WiFi"
#define BOARD_HAS_W5500 0
#define BOARD_HAS_WIFI 1
#define BOARD_HAS_NATIVE_ETH 0

#define PIN_COIN_PRIMARY 4
#define PIN_COIN_BACKUP  5
#define PIN_RELAY        15
#define PIN_LED          2
#define PIN_LED_ACTIVE_LOW 1
#define PIN_CONFIG_BTN   0

#define RELAY_DEFAULT_ACTIVE_HIGH 0
#define NUM_COIN_PINS 2
