

#include <WiFi.h>
#include <time.h>

#include <SPI.h>
#include <LoRa.h>

#include <ArduinoJson.h>
#include <Firebase_ESP_Client.h>


#define WIFI_SSID "User's iPhone"
#define WIFI_PASSWORD "11111111"


#define API_KEY "AIzaSyA0WC18bVO2nE7ZupP_NKSq-qW3j6GCCpQ"
#define DATABASE_URL "https://vest-tracker-system-default-rtdb.asia-southeast1.firebasedatabase.app/"
#define USER_EMAIL "finalyearprojectbeamtechvest@gmail.com"
#define USER_PASSWORD "final.year.project6782"


static constexpr int LORA_SS = 5;
static constexpr int LORA_RST = 14;
static constexpr int LORA_DIO0 = 2;
static constexpr long LORA_FREQ_HZ = 433E6;


static constexpr int LORA_SCK = 18;
static constexpr int LORA_MISO = 19;
static constexpr int LORA_MOSI = 23;


FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;


struct Backoff {
  unsigned long nextDelayMs = 250;
  unsigned long maxDelayMs = 30000;
  unsigned long nextAtMs = 0;

  void reset(unsigned long nowMs, unsigned long initialDelayMs = 250, unsigned long maxMs = 30000) {
    nextDelayMs = initialDelayMs;
    maxDelayMs = maxMs;
    nextAtMs = nowMs;
  }

  bool due(unsigned long nowMs) const {
    return nowMs >= nextAtMs;
  }

  void success(unsigned long nowMs) {
    nextDelayMs = 250;
    nextAtMs = nowMs + 250;
  }

  void fail(unsigned long nowMs) {
    nextAtMs = nowMs + nextDelayMs;
    nextDelayMs = (nextDelayMs < maxDelayMs / 2) ? (nextDelayMs * 2) : maxDelayMs;
  }
};

static Backoff wifiBackoff;
static Backoff firebaseBackoff;

static bool wifiBeginCalled = false;
static unsigned long wifiLastBeginMs = 0;
static bool timeSynced = false;
static bool firebaseStarted = false;


struct VestMessage {
  uint16_t id = 0;

  int gs = 0;
  char gsn[32] = {0};

  bool wet = false;
  bool imp = false;
  uint32_t t = 0;

  bool hasLoc = false;
  float lat = 0.0f;
  float lon = 0.0f;
  float alt = 0.0f;
  float spd = 0.0f;
  int sat = 0;
  uint32_t fix_ms = 0;
};

static constexpr size_t QUEUE_CAPACITY = 30;
static VestMessage queueBuf[QUEUE_CAPACITY];
static size_t queueHead = 0; 
static size_t queueSize = 0;

static void queueDropOldestIfFull() {
  if (queueSize < QUEUE_CAPACITY) return;
  queueHead = (queueHead + 1) % QUEUE_CAPACITY;
  queueSize--;
}

static void queuePush(const VestMessage& m) {
  queueDropOldestIfFull();
  const size_t idx = (queueHead + queueSize) % QUEUE_CAPACITY;
  queueBuf[idx] = m;
  queueSize++;
}

static bool queuePop(VestMessage& out) {
  if (queueSize == 0) return false;
  out = queueBuf[queueHead];
  queueHead = (queueHead + 1) % QUEUE_CAPACITY;
  queueSize--;
  return true;
}

static size_t queueCount() { return queueSize; }


static bool syncTimeOnce() {
  if (timeSynced) return true;

  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  struct tm timeinfo;

  Serial.print("Syncing time");
  unsigned long start = millis();
  while (!getLocalTime(&timeinfo)) {
    Serial.print(".");
    delay(500);
    if (millis() - start > 20000UL) {
      Serial.println("\nTime sync timeout");
      return false;
    }
  }

  Serial.println("\nTime synced");
  timeSynced = true;
  return true;
}


static String deviceKeyForId(uint16_t id) {
  char buf[24];
  if (id < 10) snprintf(buf, sizeof(buf), "device_0%u", static_cast<unsigned>(id));
  else snprintf(buf, sizeof(buf), "device_%u", static_cast<unsigned>(id));
  return String(buf);
}

static bool parseVestJson(const String& payload, VestMessage& out) {
  StaticJsonDocument<512> doc;
  DeserializationError err = deserializeJson(doc, payload);
  if (err) return false;

  
  out.hasLoc = false;
  out.lat = 0.0f;
  out.lon = 0.0f;
  out.alt = 0.0f;
  out.spd = 0.0f;
  out.sat = 0;
  out.fix_ms = 0;

  if (!doc.containsKey("id")) return false;
  out.id = static_cast<uint16_t>(doc["id"].as<unsigned>());

  out.gs = doc["gs"] | 0;
  const char* gsn = doc["gsn"] | "";
  strncpy(out.gsn, gsn, sizeof(out.gsn) - 1);
  out.gsn[sizeof(out.gsn) - 1] = '\0';

  out.wet = doc["wet"] | false;
  out.imp = doc["imp"] | false;
  out.t = doc["t"] | 0UL;

  const bool locFlagPresent = doc.containsKey("loc");
  const bool locFalse = locFlagPresent && (doc["loc"].is<bool>() && (doc["loc"].as<bool>() == false));

  const bool hasLatLon = doc.containsKey("lat") && doc.containsKey("lon");
  if (!locFalse && hasLatLon) {
    out.hasLoc = true;
    out.lat = doc["lat"] | 0.0f;
    out.lon = doc["lon"] | 0.0f;
    out.alt = doc["alt"] | 0.0f;
    out.spd = doc["spd"] | 0.0f;
    out.sat = doc["sat"] | 0;
    out.fix_ms = doc["fix_ms"] | 0UL;
  }

  return true;
}


static bool ensureWiFi(unsigned long nowMs) {
  if (WiFi.status() == WL_CONNECTED) return true;

  if (!wifiBackoff.due(nowMs)) return false;

  
  const bool shouldRebegin = wifiBeginCalled && (nowMs - wifiLastBeginMs >= 60000UL);

  if (!wifiBeginCalled || shouldRebegin) {
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.disconnect(true, true);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    wifiBeginCalled = true;
    wifiLastBeginMs = nowMs;
    Serial.print("WiFi begin -> ");
    Serial.println(WIFI_SSID);
    wifiBackoff.fail(nowMs);
    return false;
  }

  Serial.print("WiFi waiting (status=");
  Serial.print(static_cast<int>(WiFi.status()));
  Serial.print("), next check in ");
  Serial.print(wifiBackoff.nextDelayMs);
  Serial.println("ms");

  wifiBackoff.fail(nowMs);
  return false;
}

static void startFirebaseIfNeeded() {
  if (firebaseStarted) return;

  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  firebaseStarted = true;

  Serial.println("Firebase begin called");
}

static bool ensureFirebaseReady(unsigned long nowMs) {
  if (!firebaseBackoff.due(nowMs)) return Firebase.ready();

  if (!firebaseStarted) startFirebaseIfNeeded();

  if (Firebase.ready()) {
    firebaseBackoff.success(nowMs);
    return true;
  }

  Serial.print("Firebase not ready, next check in ");
  Serial.print(firebaseBackoff.nextDelayMs);
  Serial.println("ms");

  
  static unsigned long lastRestartAttemptMs = 0;
  if (nowMs - lastRestartAttemptMs >= 60000UL) {
    lastRestartAttemptMs = nowMs;
    firebaseStarted = false;
    startFirebaseIfNeeded();
  }

  firebaseBackoff.fail(nowMs);
  return false;
}


static bool writeLatestToRtdb(const VestMessage& m) {
  const String deviceKey = deviceKeyForId(m.id);
  const String base = "/vest/" + deviceKey + "/";

  bool ok = true;

  ok = ok && Firebase.RTDB.setInt(&fbdo, base + "gs", m.gs);
  ok = ok && Firebase.RTDB.setString(&fbdo, base + "gsn", m.gsn);
  ok = ok && Firebase.RTDB.setBool(&fbdo, base + "wet", m.wet);
  ok = ok && Firebase.RTDB.setBool(&fbdo, base + "imp", m.imp);
  ok = ok && Firebase.RTDB.setInt(&fbdo, base + "t", static_cast<int>(m.t));

  if (m.hasLoc) {
    ok = ok && Firebase.RTDB.setFloat(&fbdo, base + "lat", m.lat);
    ok = ok && Firebase.RTDB.setFloat(&fbdo, base + "lon", m.lon);
    ok = ok && Firebase.RTDB.setFloat(&fbdo, base + "alt", m.alt);
    ok = ok && Firebase.RTDB.setFloat(&fbdo, base + "spd", m.spd);
    ok = ok && Firebase.RTDB.setInt(&fbdo, base + "sat", m.sat);
    ok = ok && Firebase.RTDB.setInt(&fbdo, base + "fix_ms", static_cast<int>(m.fix_ms));
  }

  if (!ok) {
    Serial.print("RTDB write error: ");
    Serial.println(fbdo.errorReason());
  }

  return ok;
}


static void pollLoraAndEnqueue() {
  const int packetSize = LoRa.parsePacket();
  if (packetSize <= 0) return;

  String payload;
  payload.reserve(static_cast<size_t>(packetSize) + 8);
  while (LoRa.available()) payload += static_cast<char>(LoRa.read());

  const int rssi = LoRa.packetRssi();
  Serial.print("LoRa RX (");
  Serial.print(packetSize);
  Serial.print(" bytes, RSSI ");
  Serial.print(rssi);
  Serial.print("): ");
  Serial.println(payload);

  VestMessage msg;
  if (!parseVestJson(payload, msg)) {
    Serial.println("JSON parse failed; dropped");
    return;
  }

  queuePush(msg);
  Serial.print("Enqueued id=");
  Serial.print(msg.id);
  Serial.print(" queue=");
  Serial.println(queueCount());
}

static void flushQueueToFirebase(unsigned long nowMs) {
  (void)nowMs;
  if (!Firebase.ready()) return;
  if (queueCount() == 0) return;

  
  static constexpr int MAX_FLUSH_PER_LOOP = 4;

  for (int i = 0; i < MAX_FLUSH_PER_LOOP; i++) {
    VestMessage m;
    if (!queuePop(m)) break;

    Serial.print("RTDB write id=");
    Serial.print(m.id);
    Serial.print(" remaining=");
    Serial.println(queueCount());

    if (!writeLatestToRtdb(m)) {
      
      queuePush(m);
      break;
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(400);
  Serial.println("RECEIVER_CONTROL_TOWER booting...");

  wifiBackoff.reset(millis(), 250, 30000);
  firebaseBackoff.reset(millis(), 250, 30000);

  
  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_SS);
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  if (!LoRa.begin(LORA_FREQ_HZ)) {
    Serial.println("LoRa INIT FAILED");
    while (true) delay(1000);
  }

  Serial.println("LoRa INIT OK");
}

void loop() {
  const unsigned long nowMs = millis();

  
  pollLoraAndEnqueue();

  
  if (!ensureWiFi(nowMs)) {
    delay(2);
    return;
  }

  if (!syncTimeOnce()) {
    delay(2);
    return;
  }

  if (!ensureFirebaseReady(nowMs)) {
    delay(2);
    return;
  }

  
  flushQueueToFirebase(nowMs);

  delay(2);
}
