#include <SPI.h>
#include <LoRa.h>


#define SS   5
#define RST  14
#define DIO0 2

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("LoRa RX Booting...");

  SPI.begin(18, 19, 23, 5);
  LoRa.setPins(SS, RST, DIO0);

  if (!LoRa.begin(433E6)) {
    Serial.println("❌ LoRa INIT FAILED");
    while (1);
  }

  Serial.println("✅ LoRa INIT OK");
  Serial.println("Waiting for packets...");
}

void loop() {
  int packetSize = LoRa.parsePacket();

  if (packetSize) {
    Serial.print("Received: ");

    while (LoRa.available()) {
      Serial.print((char)LoRa.read());
    }

    Serial.print(" | RSSI: ");
    Serial.println(LoRa.packetRssi());
  }
}
