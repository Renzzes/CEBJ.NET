#include "coin_relay.h"

static const int coinPins[NUM_COIN_PINS] = {PIN_COIN_PRIMARY, PIN_COIN_BACKUP};
static const int relayPin = PIN_RELAY;

static int relayLogic = 1;  // 1 = active HIGH

static volatile unsigned long lastPulseTime = 0;
static const unsigned long MIN_PULSE_WIDTH_MS = 10;
static const unsigned long MAX_PULSE_WIDTH_MS = 200;

#define PULSE_BUFFER_SIZE 32
static volatile unsigned long isrPulseWidths[NUM_COIN_PINS][PULSE_BUFFER_SIZE];
static volatile int isrPulseHead[NUM_COIN_PINS] = {0};
static volatile int isrPulseTail[NUM_COIN_PINS] = {0};
static volatile unsigned long isrFallingTime[NUM_COIN_PINS] = {0};
static volatile bool isrPinLow[NUM_COIN_PINS] = {false};

static int pendingPulses = 0;

#if defined(ESP8266)
#define COIN_ISR_ATTR ICACHE_RAM_ATTR
#elif defined(ESP32)
#define COIN_ISR_ATTR IRAM_ATTR
#else
#define COIN_ISR_ATTR
#endif

static void COIN_ISR_ATTR coinChangeISR(int slot) {
  unsigned long now = millis();
  if (digitalRead(coinPins[slot]) == LOW) {
    isrFallingTime[slot] = now;
    isrPinLow[slot] = true;
  } else if (isrPinLow[slot]) {
    unsigned long width = now - isrFallingTime[slot];
    isrPinLow[slot] = false;
    if (width >= 5 && width <= 500) {
      int head = isrPulseHead[slot];
      int next = (head + 1) % PULSE_BUFFER_SIZE;
      if (next != isrPulseTail[slot]) {
        isrPulseWidths[slot][head] = width;
        isrPulseHead[slot] = next;
      }
    }
  }
}

static void COIN_ISR_ATTR coinIsr0() { coinChangeISR(0); }
static void COIN_ISR_ATTR coinIsr1() { coinChangeISR(1); }

void setRelay(bool active) {
  if (relayLogic == 1) {
    digitalWrite(relayPin, active ? HIGH : LOW);
  } else {
    digitalWrite(relayPin, active ? LOW : HIGH);
  }
}

void coinRelayBegin(int relayActiveHigh) {
  relayLogic = relayActiveHigh ? 1 : 0;
  for (int i = 0; i < NUM_COIN_PINS; i++) {
    pinMode(coinPins[i], INPUT_PULLUP);
  }
  pinMode(relayPin, OUTPUT);
  setRelay(false);

  pinMode(PIN_LED, OUTPUT);
#if PIN_LED_ACTIVE_LOW
  digitalWrite(PIN_LED, HIGH);
#else
  digitalWrite(PIN_LED, LOW);
#endif

  attachInterrupt(digitalPinToInterrupt(coinPins[0]), coinIsr0, CHANGE);
#if NUM_COIN_PINS > 1
  attachInterrupt(digitalPinToInterrupt(coinPins[1]), coinIsr1, CHANGE);
#endif
}

void coinRelayLoop() {
  for (int slot = 0; slot < NUM_COIN_PINS; slot++) {
    while (isrPulseTail[slot] != isrPulseHead[slot]) {
      unsigned long width = isrPulseWidths[slot][isrPulseTail[slot]];
      isrPulseTail[slot] = (isrPulseTail[slot] + 1) % PULSE_BUFFER_SIZE;
      if (width >= MIN_PULSE_WIDTH_MS && width <= MAX_PULSE_WIDTH_MS) {
        pendingPulses++;
        lastPulseTime = millis();
      }
    }
  }
}

int takeValidatedPulses() {
  int n = pendingPulses;
  pendingPulses = 0;
  return n;
}

void printBoardPins() {
  Serial.println(F("---- Board pin map ----"));
  Serial.print(F("Board: "));
  Serial.println(BOARD_NAME);
  Serial.print(F("ID: "));
  Serial.println(BOARD_ID);
  Serial.print(F("Coin primary GPIO "));
  Serial.println(PIN_COIN_PRIMARY);
  Serial.print(F("Coin backup  GPIO "));
  Serial.println(PIN_COIN_BACKUP);
  Serial.print(F("Relay        GPIO "));
  Serial.println(PIN_RELAY);
  Serial.print(F("LED          GPIO "));
  Serial.println(PIN_LED);
#if BOARD_HAS_W5500
  Serial.println(F("Network: W5500 SPI"));
  Serial.print(F("  CS   GPIO "));
  Serial.println(PIN_W5500_CS);
  Serial.print(F("  SCLK GPIO "));
  Serial.println(PIN_W5500_SCLK);
  Serial.print(F("  MISO GPIO "));
  Serial.println(PIN_W5500_MISO);
  Serial.print(F("  MOSI GPIO "));
  Serial.println(PIN_W5500_MOSI);
#elif BOARD_HAS_NATIVE_ETH
  Serial.println(F("Network: Native Ethernet (RMII)"));
  Serial.print(F("  MDC  GPIO "));
  Serial.println(PIN_ETH_MDC);
  Serial.print(F("  MDIO GPIO "));
  Serial.println(PIN_ETH_MDIO);
#elif BOARD_HAS_WIFI
  Serial.println(F("Network: WiFi (no W5500)"));
#else
  Serial.println(F("Network: (none configured)"));
#endif
  Serial.println(F("-----------------------"));
}
