/*
 * FastFi ESP8266 Coinslot — LANBASE variant (W5500 wired Ethernet)
 *
 * Same coin/relay/registration protocol as the WiFi build, but the network
 * transport is a W5500 SPI Ethernet module instead of WiFi. The relay logic
 * defaults to ACTIVE HIGH (custom boards) — see relayLogic below. There is
 * no WiFi AP / captive-portal flow; configuration is via the web UI at the
 * device's DHCP address (printed to Serial at boot).
 *
 * ----- WIRING (ESP8266 NodeMCU <-> W5500 module) -----
 *   W5500 SCLK  -> GPIO14 (D5)   [hardware SPI SCLK]
 *   W5500 MISO  -> GPIO12 (D6)   [hardware SPI MISO]
 *   W5500 MOSI  -> GPIO13 (D7)   [hardware SPI MOSI]
 *   W5500 CS/SS  -> GPIO0  (D3)  [chip select, set via Ethernet.init(); D3 is also the
 *                                config-pin strap — the physical reset button is disabled
 *                                on this build, use the web UI /reset instead. GPIO0 is a
 *                                boot strap (must idle HIGH); add a 10k pull-up D3->3V3 if
 *                                the board ever fails to enter normal boot.]
 *   W5500 RST    -> 3V3 (tie high on the module; not driven by the ESP)
 *   W5500 VCC    -> 3V3, GND -> GND
 *
 * ----- OTHER PINS -----
 *   Coin signal  -> GPIO4  (D2)  primary  (interrupt-capable)
 *   Coin backup  -> GPIO5  (D1)  redundant 2nd pin for the same acceptor
 *   Relay        -> GPIO15 (D8)  single output (active HIGH by default)
 *   LED          -> GPIO2  (D4)  (module blue LED)
 *   Config btn   -> GPIO0  (D3)  (hold at boot = factory reset)
 *
 * NOTE: hardware SPI claims GPIO12/13/14, so the WiFi build's coin pin 12 and
 * relay pins 13/14 CANNOT be reused here — they are relocated as shown above.
 * ESP8266 has only 9 usable GPIOs (0,2,4,5,12,13,14,15,16; 6-11 are tied to
 * flash and 1/3 are serial). Hardware SPI is FIXED to GPIO12/13/14 (MISO/MOSI/
 * SCLK) — these cannot move. The custom board wires the W5500 CS to GPIO0
 * (D3), so W5500_CS=0 here. GPIO0 is a boot strap (must read HIGH at power-on
 * for normal boot) — the W5500 CS idles HIGH, which satisfies the strap, but a
 * 10k pull-up D3->3V3 is recommended for robust cold-boot. Because D3 is now
 * the CS line, the physical config/reset button on CONFIG_PIN is disabled;
 * use the web UI /reset endpoint for factory reset instead. The relay runs on
 * a single pin (GPIO15/D8). GPIO15 is a boot strapping pin that must read LOW
 * at boot — for an ACTIVE-HIGH relay, OFF == LOW, so the strap is satisfied;
 * it is only driven HIGH later in setup() when energising the relay.
 *
 * Required library: "Ethernet" (Arduino library, v2.0+ — supports W5500 and
 * Ethernet.init(csPin)). Install via Library Manager if not present.
 *
 * Device identity: the ESP8266 chip MAC (WiFi.macAddress(), read from eFuse —
 * works with the WiFi radio OFF) is used both as the W5500's MAC and as the
 * device id reported to the router. This keeps the SAME device_id as the WiFi
 * build, so a board re-flashed wifi<->lanbase keeps its registration/license.
 *
 * EEPROM layout is kept IDENTICAL to the WiFi build (routerIP@96, slot@128,
 * relayLogic@132; the SSID@0 / PASS@32 fields are simply unused here) so a
 * wifi<->lanbase reflash preserves the slot and relay-logic settings.
 */

#include <SPI.h>
#include <Ethernet.h>           // W5500 driver (Ethernet.init(cs), EthernetClient)
#include <ESP8266WiFi.h>        // only for WiFi.macAddress() (chip eFuse MAC; radio stays off)
#include <ESP8266WebServer.h>   // config UI (LwIP — serves over Ethernet too)
#include <EEPROM.h>

#define LED_PIN 2                // D4 - module LED (active LOW, like the WiFi build)
#define CONFIG_PIN 0             // D3 - hold LOW at boot = factory reset (shared w/ W5500 CS — see below)
#define W5500_CS 0               // D3 - W5500 chip select (matches custom-board wiring: SCS->D3)
#define EEPROM_SIZE 512

ESP8266WebServer server(80);

/* ================= CONFIG ================= */

const char* SERVER_URL = "https://fastfi.cloud";
const char* DEVICE_TYPE = "ESP8266-LANBASE";

const char* DEFAULT_ROUTER_IP = "10.0.0.1";

// Static IP fallback used only if DHCP fails (or when USE_STATIC_IP is true).
#define USE_STATIC_IP false
IPAddress staticIP(10, 0, 0, 200);
IPAddress gateway(10, 0, 0, 1);
IPAddress subnet(255, 255, 255, 0);
IPAddress dns1(10, 0, 0, 1);

/* ================= STORAGE ================= */

// SSID@0 / PASS@32 from the WiFi build are intentionally unused on lanbase;
// the offsets are reserved so a wifi<->lanbase reflash keeps slot + relayLogic.
char routerIP[32] = "10.0.0.1";
char slotNumberStr[4] = "1";
int relayLogic = 1;            // DEFAULT ACTIVE HIGH for lanbase. 1 = Active HIGH (custom), 0 = Active LOW (generic)

/* ================= COIN & RELAY ================= */

// SPI claims GPIO12/13/14. Of the 4 remaining free GPIOs (4,5,15,16), GPIO16
// is output-only → W5500 CS, GPIO15 is the (single) relay output, and GPIO4 +
// GPIO5 are the two interrupt-capable coin inputs (primary + redundant backup,
// both reporting Slot 1, mirroring the WiFi build's coin-pin redundancy).
#define NUM_COIN_PINS 2
#define NUM_RELAY_PINS 1

int coinPins[NUM_COIN_PINS] = {4, 5};              // D2 (primary), D1 (backup)
const int relayPins[NUM_RELAY_PINS] = {15};        // D8 (single relay output)

// Device MAC captured ONCE at the very start of setup() (before the WiFi radio
// is switched off). Reused as the W5500's on-wire MAC and as the device id sent
// to the router, so the on-wire MAC == reported id and is stable across a
// wifi<->lanbase reflash. Reading it before WIFI_OFF avoids any core quirk
// where WiFi.macAddress() returns zeros once the radio is off.
byte ethMac[6] = {0, 0, 0, 0, 0, 0};

volatile int pulseCount[NUM_COIN_PINS] = {0};
volatile unsigned long lastPulseTime = 0;

const unsigned long pulseTimeout = 150;    // 150ms — optimal (no splits, minimal batching)
const int minValidPulse = 1;

// Hybrid ISR + pulse width validation (same scheme as the WiFi build):
// ISR catches BOTH edges (CHANGE) — never misses pulses even during HTTP.
// Main loop validates width — rejects EMI noise (<10ms).
const unsigned long MIN_PULSE_WIDTH_MS = 10;   // Real coin pulse is 10-60ms
const unsigned long MAX_PULSE_WIDTH_MS = 200;  // Reject stuck line

volatile unsigned long isrFallingTime[NUM_COIN_PINS] = {0};
volatile bool isrPinLow[NUM_COIN_PINS] = {false};

#define PULSE_BUFFER_SIZE 32
volatile unsigned long isrPulseWidths[NUM_COIN_PINS][PULSE_BUFFER_SIZE];
volatile int isrPulseHead[NUM_COIN_PINS] = {0};
volatile int isrPulseTail[NUM_COIN_PINS] = {0};

bool inserting = false;
bool registered = false;
bool hasLicense = false;
String deviceLicense = "";
String deviceSlotID = "";
bool ethUp = false;             // Ethernet link up AND we have an IP

unsigned long lastHeartbeat = 0;
const unsigned long heartbeatInterval = 2000;   // Poll router every 2s for power-on command
unsigned long lastLinkCheck = 0;
const unsigned long linkCheckInterval = 5000;   // Re-check link / renew DHCP every 5s
unsigned long lastDhcpAttempt = 0;
const unsigned long dhcpRetryInterval = 30000;  // Fresh DHCPDISCOVER at most every 30s (begin() blocks ~60s)

String getNormalizedMac() {
  char buf[18];
  sprintf(buf, "%02x:%02x:%02x:%02x:%02x:%02x",
          ethMac[0], ethMac[1], ethMac[2], ethMac[3], ethMac[4], ethMac[5]);
  return String(buf);
}

/* ================= HYBRID ISR + VALIDATION ================= */

void ICACHE_RAM_ATTR coinChangeISR(int slot) {
  unsigned long now = millis();

  if (digitalRead(coinPins[slot]) == LOW) {
    // Falling edge — record start time
    isrFallingTime[slot] = now;
    isrPinLow[slot] = true;
  } else if (isrPinLow[slot]) {
    // Rising edge — calculate and buffer the pulse width
    unsigned long width = now - isrFallingTime[slot];
    isrPinLow[slot] = false;

    if (width >= 5 && width <= 500) {
      int head = isrPulseHead[slot];
      int next = (head + 1) % PULSE_BUFFER_SIZE;
      if (next != isrPulseTail[slot]) {  // Buffer not full
        isrPulseWidths[slot][head] = width;
        isrPulseHead[slot] = next;
      }
    }
  }
}

void ICACHE_RAM_ATTR coinChangeISR0() { coinChangeISR(0); }
void ICACHE_RAM_ATTR coinChangeISR1() { coinChangeISR(1); }

// Drain ISR buffer and validate pulse widths in main loop
void processISRPulses() {
  for (int slot = 0; slot < NUM_COIN_PINS; slot++) {
    while (isrPulseTail[slot] != isrPulseHead[slot]) {
      unsigned long width = isrPulseWidths[slot][isrPulseTail[slot]];
      isrPulseTail[slot] = (isrPulseTail[slot] + 1) % PULSE_BUFFER_SIZE;

      if (width >= MIN_PULSE_WIDTH_MS && width <= MAX_PULSE_WIDTH_MS) {
        pulseCount[slot]++;
        lastPulseTime = millis();
      }
    }
  }
}

void setRelay(bool active) {
  for (int i = 0; i < NUM_RELAY_PINS; i++) {
    if (relayLogic == 1) {
      digitalWrite(relayPins[i], active ? HIGH : LOW); // Active HIGH (lanbase default)
    } else {
      digitalWrite(relayPins[i], active ? LOW : HIGH); // Active LOW (generic)
    }
  }
}

/* ================= EEPROM ================= */
// Offsets match the WiFi build: routerIP@96, slot@128, relayLogic@132.
// SSID@0 / PASS@32 are left untouched (unused on lanbase).

void saveConfig(String rip, String slot, int rLogic = -1) {
  EEPROM.begin(EEPROM_SIZE);

  if (rLogic != -1) {
    relayLogic = rLogic;
  }

  memset(routerIP, 0, sizeof(routerIP));
  memset(slotNumberStr, 0, sizeof(slotNumberStr));

  rip.toCharArray(routerIP, sizeof(routerIP));
  slot.toCharArray(slotNumberStr, sizeof(slotNumberStr));

  for (int i = 0; i < 32; i++) EEPROM.write(96 + i, routerIP[i]);
  for (int i = 0; i < 4; i++) EEPROM.write(128 + i, slotNumberStr[i]);
  EEPROM.write(132, relayLogic);

  EEPROM.commit();
  EEPROM.end();
}

void loadConfig() {
  EEPROM.begin(EEPROM_SIZE);

  if (EEPROM.read(96) == 0xFF) {
    // Fresh EEPROM — apply lanbase defaults (relay active HIGH)
    strcpy(routerIP, DEFAULT_ROUTER_IP);
    strcpy(slotNumberStr, "1");
    relayLogic = 1;
  } else {
    for (int i = 0; i < 32; i++) routerIP[i] = EEPROM.read(96 + i);
    for (int i = 0; i < 4; i++) slotNumberStr[i] = EEPROM.read(128 + i);
    relayLogic = EEPROM.read(132);
    // Default to ACTIVE HIGH if the stored value is garbage (or a wifi-build 0
    // carried over into a lanbase flash where the operator wants active-high).
    if (relayLogic != 0 && relayLogic != 1) relayLogic = 1;
  }

  // Validate / sanitise loaded strings
  if (routerIP[0] == 0xFF || routerIP[0] == '\0') strcpy(routerIP, DEFAULT_ROUTER_IP);
  if (slotNumberStr[0] < '0' || slotNumberStr[0] > '9') strcpy(slotNumberStr, "1");

  EEPROM.end();
}

void clearConfig() {
  EEPROM.begin(EEPROM_SIZE);
  for (int i = 0; i < EEPROM_SIZE; i++) EEPROM.write(i, 0);
  EEPROM.commit();
  EEPROM.end();
}

/* ================= DARK CSS ================= */

String darkCSS() {
  return "<style>\
  body{background:#121212;color:#eee;font-family:Arial;text-align:center;margin-top:30px;}\
  .box{background:#1e1e1e;padding:20px;border-radius:10px;width:330px;margin:auto;box-shadow:0 0 15px #000;}\
  select,input{width:100%;padding:8px;margin:8px 0;border:none;border-radius:6px;background:#2c2c2c;color:#fff;}\
  button{width:100%;padding:10px;margin-top:10px;background:#00bcd4;border:none;border-radius:6px;color:white;font-weight:bold;cursor:pointer;}\
  button:hover{background:#0097a7;}\
  .danger{background:#c62828;}\
  .danger:hover{background:#b71c1c;}\
  h2{margin-bottom:15px;}\
  .status{background:#1b5e20;padding:10px;border-radius:5px;margin:10px 0;}\
  .error{background:#b71c1c;padding:10px;border-radius:5px;margin:10px 0;}\
  </style>";
}

/* ================= WEB UI ================= */

void handleRoot() {
  String page = "<html><head><meta name='viewport' content='width=device-width, initial-scale=1'><title>ESP LAN Setup</title>";
  page += darkCSS();
  page += "</head><body><div class='box'>";
  page += "<h2>LAN Setup</h2>";
  page += "<p><small>Wired (W5500). No WiFi.</small></p>";

  page += "<form action='/bind' method='POST'>";
  page += "<input type='text' name='rip' value='" + String(routerIP) + "' placeholder='Router IP'>";
  page += "<input type='number' name='slot' value='" + String(slotNumberStr) + "' min='1' max='20' placeholder='Slot Number (1-20)'>";
  page += "<select name='rlogic'>";
  page += "<option value='1' " + String(relayLogic == 1 ? "selected" : "") + ">Relay: Active HIGH (Custom)</option>";
  page += "<option value='0' " + String(relayLogic == 0 ? "selected" : "") + ">Relay: Active LOW (Generic)</option>";
  page += "</select>";
  page += "<button type='submit'>Save</button>";
  page += "</form>";

  page += "<form action='/status'><button>Status</button></form>";
  page += "<form action='/reset'><button class='danger'>Factory Reset</button></form>";

  page += "</div></body></html>";

  server.send(200, "text/html", page);
}

void handleStatus() {
  String page = "<html><head><meta name='viewport' content='width=device-width, initial-scale=1'><title>Status</title>";
  page += darkCSS();
  page += "</head><body><div class='box'>";

  page += "<h2>Device Status</h2>";

  if (ethUp) {
    page += "<div class='status'>Ethernet: UP</div>";
    page += "<p>ESP IP: http://" + Ethernet.localIP().toString() + "</p>";
    page += "<p>Gateway: " + Ethernet.gatewayIP().toString() + "</p>";
  } else {
    page += "<div class='error'>Ethernet: DOWN (no link / no IP)</div>";
  }

  page += "<p>Slot: " + String(slotNumberStr) + "</p>";
  page += "<p>MAC: " + getNormalizedMac() + "</p>";
  page += "<p>Router: " + String(routerIP) + "</p>";
  page += "<p>Relay: " + String(relayLogic == 1 ? "Active HIGH" : "Active LOW") + "</p>";

  if (registered) {
    page += "<div class='status'>Registered: YES</div>";
    if (hasLicense) {
      page += "<div class='status'>License: " + deviceLicense + "</div>";
    } else {
      page += "<div class='error'>License: NOT LICENSED</div>";
    }
  } else {
    page += "<div class='error'>Registered: NO</div>";
  }

  page += "<form action='/'><button>Configure</button></form>";
  page += "<form action='/reset'><button class='danger'>Factory Reset</button></form>";
  page += "</div></body></html>";

  server.send(200, "text/html", page);
}

void handleBind() {
  String rip = server.arg("rip");
  String slot = server.arg("slot");
  String rlogic = server.arg("rlogic");

  if (rip == "") rip = DEFAULT_ROUTER_IP;
  if (slot == "") slot = "1";
  int rLogicInt = (rlogic == "0") ? 0 : 1;   // default active-high for any non-"0" value

  saveConfig(rip, slot, rLogicInt);

  server.send(200, "text/html",
  "<html><head><meta name='viewport' content='width=device-width, initial-scale=1'></head><body style='background:#121212;color:white;text-align:center;margin-top:50px;'>"
  "<h2>Saved! Restarting...</h2></body></html>");

  delay(2000);
  ESP.restart();
}

void handleReset() {
  clearConfig();

  server.send(200, "text/html",
  "<html><head><meta name='viewport' content='width=device-width, initial-scale=1'></head><body style='background:#121212;color:white;text-align:center;margin-top:50px;'>"
  "<h2>Factory Reset Done! Restarting...</h2></body></html>");

  delay(2000);
  ESP.restart();
}

/* ================= ETHERNET (W5500) ================= */

bool initEthernet() {
  Ethernet.init(W5500_CS);

  // ethMac was captured at the start of setup(); reuse it so the on-wire MAC
  // matches the device id reported to the router.
  Serial.println("=================================");
  Serial.println("W5500 Ethernet init");
  Serial.print("MAC: ");
  Serial.println(getNormalizedMac());
  Serial.println("=================================");

#if USE_STATIC_IP
  Ethernet.begin(ethMac, staticIP, dns1, gateway, subnet);
  Serial.println("Using STATIC IP configuration");
#else
  // DHCP (default ~60s timeout in the Ethernet library). If DHCP fails or
  // times out, localIP stays 0.0.0.0 and we fall back to the static config.
  Ethernet.begin(ethMac);
  if (Ethernet.localIP()[0] == 0 && Ethernet.localIP()[1] == 0 &&
      Ethernet.localIP()[2] == 0 && Ethernet.localIP()[3] == 0) {
    Serial.println("DHCP failed — falling back to static 10.0.0.200");
    Ethernet.begin(ethMac, staticIP, dns1, gateway, subnet);
  }
#endif

  // Link check (W5500 reports LinkON/LinkOFF; older libs may report Unknown).
  auto link = Ethernet.linkStatus();
  if (link == LinkOFF) {
    Serial.println("Ethernet link DOWN (no cable?)");
    ethUp = false;
    return false;
  }

  ethUp = true;
  IPAddress ip = Ethernet.localIP();
  IPAddress gw = Ethernet.gatewayIP();
  Serial.println("Ethernet UP");
  Serial.println("IP: " + ip.toString());
  Serial.println("Gateway: " + gw.toString());

  // Auto-detect router IP from the DHCP gateway (works on any subnet). Only
  // adopt it if the operator hasn't explicitly saved a different one.
  if (gw[0] != 0) {
    String gwStr = gw.toString();
    if (gwStr != "0.0.0.0") gwStr.toCharArray(routerIP, sizeof(routerIP));
    Serial.println("Router IP auto-set to gateway: " + gwStr);
  }

  Serial.println("Config UI: http://" + ip.toString() + "/");
  Serial.println("=================================");
  return true;
}

// Maintain the link + DHCP lease. Returns true while usable (link up, have IP).
bool maintainEthernet() {
  auto link = Ethernet.linkStatus();
  if (link == LinkOFF) {
    if (ethUp) {
      Serial.println("Ethernet link LOST");
      ethUp = false;
      setRelay(false);   // safe state while offline
    }
    return false;
  }

  // Renew DHCP if needed (returns nonzero if the lease renewed / IP changed).
  Ethernet.maintain();

  IPAddress ip = Ethernet.localIP();
  if (ip[0] == 0 && ip[1] == 0 && ip[2] == 0 && ip[3] == 0) {
    if (ethUp) {
      Serial.println("Ethernet lost IP (DHCP lease expired?)");
      ethUp = false;
      setRelay(false);
    }
    return false;
  }

  if (!ethUp) {
    ethUp = true;
    Serial.println("Ethernet link back UP — IP " + ip.toString());
    IPAddress gw = Ethernet.gatewayIP();
    if (gw[0] != 0) {
      String gwStr = gw.toString();
      if (gwStr != "0.0.0.0") gwStr.toCharArray(routerIP, sizeof(routerIP));
    }
  }
  return true;
}

/* ================= MANUAL HTTP (over EthernetClient) ================= */
// ESP8266HTTPClient.begin() is typed to WiFiClient and won't accept an
// EthernetClient, so all router calls go through this raw HTTP helper.
// Returns the response BODY only (headers stripped) so the existing
// response.indexOf() parsing matches the WiFi build's http.getString().

String espHTTPRequest(const String& host, int port, const String& path,
                       bool isPost, const String& body) {
  EthernetClient client;
  client.setTimeout(5000);

  if (!client.connect(host.c_str(), port)) {
    Serial.println("HTTP: connect to " + host + ":" + String(port) + " failed");
    return "";
  }

  String req = String(isPost ? "POST " : "GET ") + path + " HTTP/1.1\r\n";
  req += "Host: " + host + "\r\n";
  req += "Connection: close\r\n";
  if (isPost) {
    req += "Content-Type: application/json\r\n";
    req += "Content-Length: " + String(body.length()) + "\r\n";
  }
  req += "\r\n";
  if (isPost) req += body;

  client.print(req);

  // Wait for the response (up to 5s)
  unsigned long start = millis();
  while (!client.available() && client.connected() && millis() - start < 5000) {
    delay(10);
  }

  String resp;
  while (client.available()) {
    resp += (char)client.read();
    if (resp.length() > 4096) break;   // cap to bound memory
  }
  client.stop();

  // Strip headers: everything up to and including the first blank line.
  int sep = resp.indexOf("\r\n\r\n");
  if (sep >= 0) return resp.substring(sep + 4);
  return resp;
}

/* ================= HEARTBEAT ================= */

void sendHeartbeat() {
  if (!ethUp || !registered) return;

  String mac = getNormalizedMac();
  String path = "/cgi-bin/api?action=esp_status";
  String body = "{\"mac\":\"" + mac + "\",\"status\":\"online\"}";

  String response = espHTTPRequest(routerIP, 80, path, true, body);

  if (response.length() > 0 && response.indexOf("\"status\":\"ok\"") >= 0) {
    Serial.print("Heartbeat OK - Relay: ");
    if (response.indexOf("\"relay\":1") >= 0) {
      Serial.println("ON");
      setRelay(true);
    } else {
      Serial.println("OFF");
      setRelay(false);
    }
  }
}

/* ================= OFFLINE STATUS ================= */

void sendOfflineStatus() {
  if (!registered || !ethUp) return;

  String mac = getNormalizedMac();
  String path = "/cgi-bin/api?action=esp_status";
  String body = "{\"mac\":\"" + mac + "\",\"status\":\"offline\"}";

  espHTTPRequest(routerIP, 80, path, true, body);
  Serial.println("Offline status sent");
}

/* ================= REGISTRATION ================= */

bool registerDevice() {
  if (!ethUp) {
    Serial.println("Ethernet not up — cannot register");
    return false;
  }

  Serial.println("Registering with router...");
  Serial.println("Router IP: " + String(routerIP));
  Serial.println("ESP IP: " + Ethernet.localIP().toString());
  Serial.println("Gateway: " + Ethernet.gatewayIP().toString());

  String mac = getNormalizedMac();
  String path = "/cgi-bin/api?action=register_esp_slot";

  // Smart slot naming: use saved slot number, or MAC-based auto-name
  String slotName;
  if (strlen(slotNumberStr) > 0 && String(slotNumberStr) != "0") {
    slotName = "Slot " + String(slotNumberStr);
  } else {
    slotName = "ESP-" + mac.substring(mac.length() - 4);
  }

  String body = "{\"mac\":\"" + mac + "\",\"name\":\"" + slotName + "\"}";
  Serial.println("POST data: " + body);

  String response = espHTTPRequest(routerIP, 80, path, true, body);
  Serial.println("Registration Response: " + response);

  if (response.length() == 0) {
    Serial.println("Registration failed (no response)");
    return false;
  }

  if (response.indexOf("\"licensed\":true") > 0) {
    registered = true;
    hasLicense = true;

    int keyStart = response.indexOf("\"license_key\":\"") + 15;
    int keyEnd = response.indexOf("\"", keyStart);
    if (keyStart > 14 && keyEnd > keyStart) {
      deviceLicense = response.substring(keyStart, keyEnd);
      Serial.println("License: " + deviceLicense);
    } else {
      if (response.indexOf("\"license_status\":\"free\"") > 0) {
        hasLicense = true;
        deviceLicense = "FREE";
        Serial.println("Free slot - no license needed");
      }
    }

    setRelay(false);
    Serial.println("Registered successfully!");
    return true;
  } else if (response.indexOf("\"licensed\":false") > 0) {
    registered = true;
    hasLicense = false;
    Serial.println("Registered but no license available");
    setRelay(false);
    return true;
  }

  Serial.println("Registration response unclear");
  return false;
}

void tryRegisterWithRetry() {
  int attempts = 0;
  const int maxAttempts = 5;

  while (attempts < maxAttempts && !hasLicense) {
    attempts++;
    Serial.println("");
    Serial.println("=================================");
    Serial.println("Registration attempt " + String(attempts) + " of " + String(maxAttempts));
    Serial.println("=================================");

    if (registerDevice()) {
      if (hasLicense) {
        Serial.println("Registration successful with license!");
        return;
      }
      Serial.println("Registered but no license available yet.");
    }

    if (attempts < maxAttempts) {
      Serial.println("Waiting 5 seconds before retry...");
      delay(5000);
    }
  }

  if (!hasLicense) {
    Serial.println("Registration failed to obtain license after " + String(maxAttempts) + " attempts. Will keep retrying in loop.");
  }
}

/* ================= COIN SEND ================= */

void sendInsertCoin(int slot, int pulses) {
  if (!registered) {
    Serial.println("Not registered - cannot send coins");
    return;
  }
  if (!hasLicense) {
    Serial.println("No license - coins not accepted");
    return;
  }
  if (!ethUp) {
    Serial.println("Ethernet down - coins not sent");
    return;
  }

  String mac = getNormalizedMac();
  String path = "/cgi-bin/api?action=insertcoin&slot=" + String(slot) + "&mac=" + mac + "&pulses=" + String(pulses);

  Serial.println("Sending coins: slot=" + String(slot) + ", pulses=" + String(pulses));

  // Retry up to 3 times (router CGI may be busy with portal polling)
  for (int attempt = 1; attempt <= 3; attempt++) {
    String response = espHTTPRequest(routerIP, 80, path, false, "");
    if (response.length() > 0) {
      Serial.println("Coin response: " + response);
      inserting = false;
      return;  // Success
    }
    Serial.println("Coin send attempt " + String(attempt) + " failed");
    if (attempt < 3) delay(500);
  }

  Serial.println("Coin send failed after 3 attempts!");
  inserting = false;
}

/* ================= SETUP ================= */

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, HIGH);   // LED off (active LOW)

  // Capture the chip MAC FIRST, while the WiFi subsystem is in its default
  // boot state (before we switch the radio off). ethMac is reused for the
  // W5500 and as the device id for the lifetime of this boot.
  WiFi.macAddress(ethMac);

  loadConfig();  // Load FIRST so we know relayLogic before driving pins

  // Initialize relay pins. GPIO15 reads LOW at boot (strap) which is OFF for
  // active-high — safe. Drive OFF explicitly based on the configured logic.
  for (int i = 0; i < NUM_RELAY_PINS; i++) {
    pinMode(relayPins[i], OUTPUT);
  }
  setRelay(false);

  pinMode(CONFIG_PIN, INPUT_PULLUP);

  // Hold the config button at boot = factory reset (no AP mode on lanbase).
  bool forceReset = (digitalRead(CONFIG_PIN) == LOW);

  // LED: 10 quick blinks = starting up
  for (int i = 0; i < 10; i++) {
    digitalWrite(LED_PIN, LOW);
    delay(50);
    digitalWrite(LED_PIN, HIGH);
    delay(50);
  }

  if (forceReset) {
    Serial.println("Config button held — factory reset");
    clearConfig();
    delay(500);
  }

  // LED: 3 quick blinks after init = relay/coin pins OK
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_PIN, LOW);
    delay(100);
    digitalWrite(LED_PIN, HIGH);
    delay(100);
  }

  Serial.println("=================================");
  Serial.println("FastFi ESP8266 Coinslot — LANBASE (W5500)");
  Serial.println("MAC: " + getNormalizedMac());
  Serial.println("Relay logic: " + String(relayLogic == 1 ? "Active HIGH" : "Active LOW"));
  Serial.println("=================================");

  // Initialize coin pins and attach CHANGE interrupts (primary + backup)
  for (int i = 0; i < NUM_COIN_PINS; i++) {
    pinMode(coinPins[i], INPUT_PULLUP);
  }
  attachInterrupt(digitalPinToInterrupt(coinPins[0]), coinChangeISR0, CHANGE);
  attachInterrupt(digitalPinToInterrupt(coinPins[1]), coinChangeISR1, CHANGE);

  // LED: 2 quick blinks = ready
  for (int i = 0; i < 2; i++) {
    digitalWrite(LED_PIN, LOW);
    delay(100);
    digitalWrite(LED_PIN, HIGH);
    delay(100);
  }

  // Bring up the W5500. Keep the WiFi radio OFF (we only read its MAC).
  WiFi.mode(WIFI_OFF);
  initEthernet();

  delay(1000);

  // LED: 3 quick blinks = Ethernet done
  for (int i = 0; i < 3; i++) {
    digitalWrite(LED_PIN, LOW);
    delay(100);
    digitalWrite(LED_PIN, HIGH);
    delay(100);
  }

  if (ethUp) {
    tryRegisterWithRetry();
  } else {
    Serial.println("Ethernet not up — skipping registration (will retry in loop)");
  }

  // LED: 2 quick blinks = registration phase done
  for (int i = 0; i < 2; i++) {
    digitalWrite(LED_PIN, LOW);
    delay(100);
    digitalWrite(LED_PIN, HIGH);
    delay(100);
  }

  server.on("/", handleRoot);
  server.on("/bind", HTTP_POST, handleBind);
  server.on("/status", handleStatus);
  server.on("/reset", handleReset);
  server.onNotFound(handleRoot);

  server.begin();
  Serial.println("Web UI started on port 80");
}

/* ================= LOOP ================= */

void loop() {
  server.handleClient();

  // Periodically check link / renew DHCP. The W5500 retains its IP across link
  // flaps, so a brief unplug/replug needs no re-DHCP — maintainEthernet() just
  // flips ethUp on the link transition. A fresh DHCPDISCOVER is only needed if
  // the lease truly expired (link up but IP == 0.0.0.0), and since begin()
  // blocks up to ~60s it is throttled and only attempted with the link UP (a
  // begin() with the cable out would block the loop for a full minute).
  if (millis() - lastLinkCheck > linkCheckInterval) {
    lastLinkCheck = millis();
    bool up = maintainEthernet();
    if (!up && Ethernet.linkStatus() != LinkOFF &&
        millis() - lastDhcpAttempt > dhcpRetryInterval) {
      lastDhcpAttempt = millis();
      Serial.println("Link up but no IP — requesting DHCP (may block up to 60s)...");
      Ethernet.begin(ethMac);
      IPAddress ip = Ethernet.localIP();
      if (ip[0] == 0 && ip[1] == 0 && ip[2] == 0 && ip[3] == 0) {
        Serial.println("DHCP still failed — falling back to static 10.0.0.200");
        Ethernet.begin(ethMac, staticIP, dns1, gateway, subnet);
      }
      // Re-evaluate so ethUp flips and routerIP updates from the new gateway;
      // registerDevice() guards on ethUp, so this must run first.
      maintainEthernet();
      if (ethUp && !registered) {
        registerDevice();
      }
    }
  }

  // LED status
  if (!ethUp) {
    // Slow blink — no link / no IP
    if (millis() % 1000 < 500) digitalWrite(LED_PIN, LOW);
    else digitalWrite(LED_PIN, HIGH);
  } else if (registered && hasLicense) {
    digitalWrite(LED_PIN, LOW);   // Solid ON — licensed and working
  } else if (registered && !hasLicense) {
    if (millis() % 2000 < 100) digitalWrite(LED_PIN, LOW);   // Slow blink — no license
    else digitalWrite(LED_PIN, HIGH);
  } else {
    if (millis() % 500 < 100) digitalWrite(LED_PIN, LOW);    // Fast blink — not registered
    else digitalWrite(LED_PIN, HIGH);
  }

  // Process ISR-captured pulses (validates width, rejects noise)
  processISRPulses();

  // Check the coin pin for a completed pulse sequence
  for (int slot = 0; slot < NUM_COIN_PINS; slot++) {
    if (pulseCount[slot] > 0 && millis() - lastPulseTime > pulseTimeout) {
      int detectedPulses = pulseCount[slot];
      pulseCount[slot] = 0;

      if (detectedPulses >= minValidPulse) {
        Serial.print("Coin pin GPIO ");
        Serial.print(coinPins[slot]);
        Serial.print(" - Valid Pulses: ");
        Serial.println(detectedPulses);

        sendInsertCoin(1, detectedPulses);
      }
    }
  }

  // Send heartbeat to router every heartbeatInterval
  if (millis() - lastHeartbeat > heartbeatInterval) {
    lastHeartbeat = millis();
    sendHeartbeat();

    // If registered but no license, retry registration to check for updates
    if (registered && !hasLicense) {
      Serial.println("No license — retrying registration...");
      registerDevice();
    }
  }

  delay(10);
}