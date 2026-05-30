#include <WiFi.h>
#include <time.h>

#include <SPI.h>
#include <LoRa.h>

#include <ArduinoJson.h>
#include <Firebase_ESP_Client.h>


struct VestMessage;


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

  void waitFor(unsigned long nowMs, unsigned long delayMs) {
    nextAtMs = nowMs + delayMs;
  }
};

static Backoff wifiBackoff;
static Backoff firebaseBackoff;
static Backoff rtdbWriteBackoff;

static bool wifiBeginCalled = false;
static unsigned long wifiLastBeginMs = 0;
static bool timeSynced = false;
static bool firebaseStarted = false;

static uint32_t consecutiveRtdbFailures = 0;
static constexpr uint32_t MAX_CONSECUTIVE_RTDB_FAILURES_BEFORE_HARD_RECOVERY = 6;
static unsigned long lastHardRecoveryMs = 0;
static constexpr unsigned long HARD_RECOVERY_COOLDOWN_MS = 60000UL;
static unsigned long lastFirebaseBeginMs = 0;
static bool lastWriteWasTokenNotReady = false;
static constexpr unsigned long POST_FIREBASE_BEGIN_QUIET_MS = 7000UL;

static bool isTokenNotReadyError(const String& s) {
  return s.indexOf("token is not ready") >= 0;
}


struct VestMessage {
  uint16_t id = 0;

  int gs = 0;
  char gsn[32] = {0};

  bool wet = false;
  bool imp = false;
  uint32_t t = 0;

  
  char time_my[32] = {0};

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


static bool buildDeviceBasePath(uint16_t id, char* out, size_t outLen) {
  if (outLen == 0) return false;
  out[0] = '\0';
  const int n = snprintf(
    out,
    outLen,
    (id < 10) ? "/vest/device_0%u" : "/vest/device_%u",
    static_cast<unsigned>(id)
  );
  return (n > 0) && (static_cast<size_t>(n) < outLen);
}

static bool getMalaysiaTimeIso8601(char* out, size_t outLen) {
  if (outLen == 0) return false;
  out[0] = '\0';

  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return false;

  
  const int n = snprintf(
    out,
    outLen,
    "%04d-%02d-%02dT%02d:%02d:%02d+08:00",
    timeinfo.tm_year + 1900,
    timeinfo.tm_mon + 1,
    timeinfo.tm_mday,
    timeinfo.tm_hour,
    timeinfo.tm_min,
    timeinfo.tm_sec
  );
  return (n > 0) && (static_cast<size_t>(n) < outLen);
}

static void fillTimeMyIfPossible(VestMessage& m) {
  if (m.time_my[0] != '\0') return;
  (void)getMalaysiaTimeIso8601(m.time_my, sizeof(m.time_my));
}

static bool parseVestJson(const String& payload, VestMessage& out) {
  StaticJsonDocument<512> doc;
  DeserializationError err = deserializeJson(doc, payload);
  if (err) return false;

  
  out.time_my[0] = '\0';
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
    WiFi.setSleep(false);
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

  
  config.timeout.socketConnection = 20 * 1000;
  config.timeout.serverResponse = 20 * 1000;
  config.timeout.wifiReconnect = 10 * 1000;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  firebaseStarted = true;
  lastFirebaseBeginMs = millis();

  Serial.println("Firebase begin called");
}

static void hardRecoverNetworkAndFirebase(unsigned long nowMs, const char* reason) {
  if (nowMs - lastHardRecoveryMs < HARD_RECOVERY_COOLDOWN_MS) return;
  lastHardRecoveryMs = nowMs;

  Serial.print("HARD RECOVERY: ");
  Serial.println(reason);

  consecutiveRtdbFailures = 0;

  
  firebaseStarted = false;
  WiFi.disconnect(true, true);
  wifiBeginCalled = false;
  timeSynced = false;

  wifiBackoff.reset(nowMs, 250, 30000);
  firebaseBackoff.reset(nowMs, 250, 30000);
  rtdbWriteBackoff.reset(nowMs, 250, 30000);
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
  char basePath[48];
  if (!buildDeviceBasePath(m.id, basePath, sizeof(basePath))) return false;

  FirebaseJson json;
  json.set("gs", m.gs);
  json.set("gsn", m.gsn);
  json.set("wet", m.wet);
  json.set("imp", m.imp);
  json.set("t", static_cast<int>(m.t));

  if (m.time_my[0] != '\0') json.set("time_my", m.time_my);

  if (m.hasLoc) {
    json.set("lat", m.lat);
    json.set("lon", m.lon);
    json.set("alt", m.alt);
    json.set("spd", m.spd);
    json.set("sat", m.sat);
    json.set("fix_ms", static_cast<int>(m.fix_ms));
  }

  const bool ok = Firebase.RTDB.updateNode(&fbdo, basePath, &json);

  if (!ok) {
    const String reason = fbdo.errorReason();
    lastWriteWasTokenNotReady = isTokenNotReadyError(reason);

    
    if (!lastWriteWasTokenNotReady) consecutiveRtdbFailures++;

    Serial.print("RTDB write error: ");
    Serial.println(reason);

    Serial.print("Diag: heap=");
    Serial.print(ESP.getFreeHeap());
    Serial.print(" rssi=");
    Serial.println(WiFi.status() == WL_CONNECTED ? WiFi.RSSI() : 0);
  } else {
    consecutiveRtdbFailures = 0;
    lastWriteWasTokenNotReady = false;
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

  
  fillTimeMyIfPossible(msg);

  queuePush(msg);
  Serial.print("Enqueued id=");
  Serial.print(msg.id);
  Serial.print(" queue=");
  Serial.println(queueCount());
}

static void flushQueueToFirebase(unsigned long nowMs) {
  if (!Firebase.ready()) return;
  if (queueCount() == 0) return;
  if (!rtdbWriteBackoff.due(nowMs)) return;

  
  if (lastFirebaseBeginMs != 0 && (nowMs - lastFirebaseBeginMs) < POST_FIREBASE_BEGIN_QUIET_MS) {
    rtdbWriteBackoff.waitFor(nowMs, 1000);
    return;
  }

  if (consecutiveRtdbFailures >= MAX_CONSECUTIVE_RTDB_FAILURES_BEFORE_HARD_RECOVERY) {
    hardRecoverNetworkAndFirebase(nowMs, "too many RTDB/SSL failures");
    return;
  }

  
  static constexpr int MAX_FLUSH_PER_LOOP = 4;

  for (int i = 0; i < MAX_FLUSH_PER_LOOP; i++) {
    VestMessage m;
    if (!queuePop(m)) break;

    
    fillTimeMyIfPossible(m);

    Serial.print("RTDB write id=");
    Serial.print(m.id);
    Serial.print(" remaining=");
    Serial.println(queueCount());

    if (!writeLatestToRtdb(m)) {
      if (lastWriteWasTokenNotReady) {
        
        rtdbWriteBackoff.waitFor(nowMs, 5000);
      } else {
        rtdbWriteBackoff.fail(nowMs);
      }
      
      queuePush(m);
      break;
    }
    rtdbWriteBackoff.success(nowMs);
  }
}

void setup() {
  Serial.begin(115200);
  delay(400);
  Serial.println("RECEIVER_CONTROL_TOWER_V2 booting...");

  WiFi.setSleep(false);

  wifiBackoff.reset(millis(), 250, 30000);
  firebaseBackoff.reset(millis(), 250, 30000);
  rtdbWriteBackoff.reset(millis(), 250, 30000);

  
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
