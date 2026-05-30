# IoT Vest Tracker System

The **IoT Vest Tracker System** tracks a wearable vest’s location in near real time and raises alerts when a rain/water sensor detects moisture. A vest unit reads **GPS** and a **rain sensor**, then sends compact **LoRa** packets to a **receiver / control tower** (ESP32). The receiver uploads the latest state to **Firebase Realtime Database** when Wi‑Fi is available. The **Vest Tracker** Android app (Flutter) reads that data and shows live map markers, a device list, and optional **wet alerts**.

The system supports **multiple vests** (one RTDB document per device ID) and is intended for field tracking, safety recovery using last-known position, and weather-exposure awareness when the vest gets wet.

## Documentation (read in this order)

1. [PowerSafetyNotes.pdf](documentation/PDF/PowerSafetyNotes.pdf) — Battery charging, operating safety, and emergency steps before field use.
2. [Hardware.pdf](documentation/PDF/Hardware.pdf) — Physical components in the vest and receiver, behavior, and limitations.
3. [UserGuide.pdf](documentation/PDF/UserGuide.pdf) — First-time setup and day-to-day operation.
4. [MobileAppGuide.pdf](documentation/PDF/MobileAppGuide.pdf) — Android app installation, screens, settings, and wet alerts.
5. [TroubleshootingGuide.pdf](documentation/PDF/TroubleshootingGuide.pdf) — Common faults, operator mistakes, and fixes.
6. [FirmwareSoftware.pdf](documentation/PDF/FirmwareSoftware.pdf) — LoRa payloads, RTDB fields, firmware behavior, and repo layout.
7. [Appendix.pdf](documentation/PDF/Appendix.pdf) — BOM, pin tables, schematic reference, and assembly notes for maintainers.
