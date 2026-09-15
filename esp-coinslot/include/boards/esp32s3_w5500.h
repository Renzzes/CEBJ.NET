#pragma once
/* ESP32-S3 + W5500 SPI Ethernet */

#define BOARD_NAME "ESP32-S3 W5500"
#define BOARD_HAS_W5500 1
#define BOARD_HAS_WIFI 0
#define BOARD_HAS_NATIVE_ETH 0

#define PIN_COIN_PRIMARY 4
#define PIN_COIN_BACKUP  5
#define PIN_RELAY        6
#define PIN_LED          2
#define PIN_LED_ACTIVE_LOW 0

#define PIN_W5500_CS     10
#define PIN_W5500_SCLK   12
#define PIN_W5500_MISO   13
#define PIN_W5500_MOSI   11

#define RELAY_DEFAULT_ACTIVE_HIGH 1
#define NUM_COIN_PINS 2
