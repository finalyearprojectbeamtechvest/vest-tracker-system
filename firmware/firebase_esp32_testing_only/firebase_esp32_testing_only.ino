#include <WiFi.h>
#include <time.h>
#include <Firebase_ESP_Client.h>


#define WIFI_SSID "User's iPhone"
#define WIFI_PASSWORD "11111111"


#define API_KEY "AIzaSyA0WC18bVO2nE7ZupP_NKSq-qW3j6GCCpQ"
#define DATABASE_URL "https://vest-tracker-system-default-rtdb.asia-southeast1.firebasedatabase.app/"
#define USER_EMAIL "finalyearprojectbeamtechvest@gmail.com"
#define USER_PASSWORD "final.year.project6782"


FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;


void syncTime() {
  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");

  struct tm timeinfo;
  Serial.print("Syncing time");

  while (!getLocalTime(&timeinfo)) {
    Serial.print(".");
    delay(1000);
  }

  Serial.println("\nTime synced");
}


void connectWiFi() {
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting WiFi");

  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(300);
  }

  Serial.println("\nWiFi OK");
}

void setup() {
  Serial.begin(115200);

  
  connectWiFi();

  
  syncTime();

  
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  
  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;

  
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  Serial.println("Firebase ready");
}

void loop() {

  if (Firebase.ready()) {

    Serial.println("Sending data...");

    
    if (!Firebase.RTDB.setInt(&fbdo, "/vest/device_01/gs", 3))
      Serial.println(fbdo.errorReason());

    if (!Firebase.RTDB.setString(&fbdo, "/vest/device_01/gsn", "locked"))
      Serial.println(fbdo.errorReason());

    if (!Firebase.RTDB.setFloat(&fbdo, "/vest/device_01/lat", 6.46039))
      Serial.println(fbdo.errorReason());

    if (!Firebase.RTDB.setFloat(&fbdo, "/vest/device_01/lon", 100.35924))
      Serial.println(fbdo.errorReason());

    if (!Firebase.RTDB.setInt(&fbdo, "/vest/device_01/alt", 62))
      Serial.println(fbdo.errorReason());

    if (!Firebase.RTDB.setFloat(&fbdo, "/vest/device_01/spd", 0.1))
      Serial.println(fbdo.errorReason());

    if (!Firebase.RTDB.setInt(&fbdo, "/vest/device_01/sat", 8))
      Serial.println(fbdo.errorReason());

    if (!Firebase.RTDB.setInt(&fbdo, "/vest/device_01/fix_ms", 60000))
      Serial.println(fbdo.errorReason());

    if (!Firebase.RTDB.setBool(&fbdo, "/vest/device_01/wet", false))
      Serial.println(fbdo.errorReason());

    if (!Firebase.RTDB.setBool(&fbdo, "/vest/device_01/imp", false))
      Serial.println(fbdo.errorReason());

    if (!Firebase.RTDB.setInt(&fbdo, "/vest/device_01/t", millis()))
      Serial.println(fbdo.errorReason());

    Serial.println("Data sent attempt complete");
  }

  delay(5000);
}
