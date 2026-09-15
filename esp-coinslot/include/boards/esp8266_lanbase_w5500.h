#pragma once
/* ESP8266 NodeMCU + W5500 — matches FastFi lanbase wiring */

#define BOARD_NAME "ESP8266 LANBASE W5500"
#define BOARD_HAS_W5500 1
#define BOARD_HAS_WIFI 0
#define BOARD_HAS_NATIVE_ETH 0

#define PIN_COIN_PRIMARY 4   /* D2 */
#define PIN_COIN_BACKUP  5   /* D1 */
#define PIN_RELAY        15  /* D8 */
#define PIN_LED          2   /* D4 active LOW */
#define PIN_LED_ACTIVE_LOW 1

#define PIN_W5500_CS     0   /* D3 */
#define PIN_W5500_SCLK   14  /* D5 HW SPI */
#define PIN_W5500_MISO   12  /* D6 */
#define PIN_W5500_MOSI   13  /* D7 */

#define RELAY_DEFAULT_ACTIVE_HIGH 1
#define NUM_COIN_PINS 2
