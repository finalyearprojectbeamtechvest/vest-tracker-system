#include <TinyGPS.h>

TinyGPS gps;
HardwareSerial gpsSerial(2);

void setup() {
  Serial.begin(115200);

  
  gpsSerial.begin(9600, SERIAL_8N1, 16, 17);

  Serial.println("GPS Starting...");
}

void loop() {
  while (gpsSerial.available()) {
    char c = gpsSerial.read();
    gps.encode(c);

    
    Serial.print(c);
  }

  float lat, lon;
  unsigned long age;

  gps.f_get_position(&lat, &lon, &age);

  if (age < 2000) {
    Serial.println("\n------ GPS DATA ------");

    Serial.print("Latitude: ");
    Serial.println(lat, 6);

    Serial.print("Longitude: ");
    Serial.println(lon, 6);

    Serial.print("Satellites: ");
    Serial.println(gps.satellites());

    Serial.print("Altitude (m): ");
    Serial.println(gps.f_altitude());

    Serial.print("Speed (km/h): ");
    Serial.println(gps.f_speed_kmph());

    Serial.println("----------------------\n");
  } else {
    Serial.println("\nWaiting for GPS signal...");
  }

  delay(5000);
}
