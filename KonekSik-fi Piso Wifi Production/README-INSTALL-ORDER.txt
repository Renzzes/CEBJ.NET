KonekSik-fi Piso Wifi — Production package
==========================================

Install in this order:

1) 01-RUIJIE-OPENWRT
   Flash KonekSik-fi-EW1200G-PRO-sysupgrade.bin to the Ruijie.

2) 02-ESP-COINSLOT
   a. firmware\  = coinslot .bin files
   b. Flasher-and-License\  = Windows flasher + offline license tool
      Double-click Flasher-and-License\START-FLASHER.bat
      Select board, COM port, browse firmware\*.bin
      Use Flash + License (full provision)

3) 03-GCASH-COMPANION
   Install APK on YOUR operator phone (not customers).

Each folder has STATUS.txt (OK / SKIPPED / FAILED).
Rebuild anytime: double-click BUILD-PRODUCTION.bat
