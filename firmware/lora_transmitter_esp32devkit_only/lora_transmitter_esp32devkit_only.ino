#include <SPI.h>
#include <LoRa.h>


#define SS   5
#define RST  14
#define DIO0 2

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("LoRa TX Booting...");

  SPI.begin(18, 19, 23, 5); 
  LoRa.setPins(SS, RST, DIO0);

  if (!LoRa.begin(433E6)) {
    Serial.println("❌ LoRa INIT FAILED");
    while (1);
  }

  Serial.println("✅ LoRa INIT OK");
}

void loop() {
  Serial.println("Sending packet...");

  LoRa.beginPacket();
  LoRa.print("HELLO_FROM_TX");
  LoRa.endPacket();

  Serial.println("Sent ✔");

  delay(1000);
}
