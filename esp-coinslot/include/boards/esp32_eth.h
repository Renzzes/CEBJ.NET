#pragma once
/* ESP32 with native Ethernet PHY (LAN8720-style). RMII pins are Espressif-fixed. */

#define BOARD_NAME "ESP32 Native ETH"
#define BOARD_HAS_W5500 0
#define BOARD_HAS_WIFI 0
#define BOARD_HAS_NATIVE_ETH 1

#define PIN_COIN_PRIMARY 34
#define PIN_COIN_BACKUP  35
#define PIN_RELAY        4
#define PIN_LED          2
#define PIN_LED_ACTIVE_LOW 0

#define PIN_ETH_MDC      23
#define PIN_ETH_MDIO     18
#define PIN_ETH_CLK      0
#define PIN_ETH_POWER    16

#define RELAY_DEFAULT_ACTIVE_HIGH 1
#define NUM_COIN_PINS 2
