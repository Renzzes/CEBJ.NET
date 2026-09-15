#pragma once
#include <Arduino.h>
#include "board_select.h"

void coinRelayBegin(int relayActiveHigh);
void coinRelayLoop();
void setRelay(bool active);
int takeValidatedPulses();  // drain and return new coin pulse count since last call
void printBoardPins();
