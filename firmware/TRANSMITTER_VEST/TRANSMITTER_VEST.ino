#include <SPI.h>
#include <LoRa.h>
#include <TinyGPS.h>


static constexpr int GPS_RX_PIN = 16;
static constexpr int GPS_TX_PIN = 17;


static constexpr uint16_t VEST_ID = 1;


static constexpr int LORA_SS = 5;
static constexpr int LORA_RST = 14;
static constexpr int LORA_DIO0 = 2;
static constexpr long LORA_FREQ_HZ = 433E6;


static constexpr int RAIN_ANALOG = 34;
static constexpr int RAIN_ANALOG_WET_THRESHOLD = 2500;


static constexpr unsigned long GPS_JSON_INTERVAL_MS = 10UL * 1000UL;
static constexpr unsigned long LORA_TX_INTERVAL_MS = 60UL * 1000UL;
static constexpr unsigned long GPS_NO_DATA_TIMEOUT_MS = 2000UL;

static constexpr unsigned long RAIN_DEBOUNCE_MS = 80UL;


TinyGPS gps;
HardwareSerial gpsSerial(2);

enum GpsStage : uint8_t {
  GPS_STAGE_WAITING_FOR_SIGNAL = 1,
  GPS_STAGE_AVAILABLE_NO_LOCK = 2,
  GPS_STAGE_LOCKED = 3,
};

struct LastGoodFix {
  float lat = 0.0f;
  float lon = 0.0f;
  float alt_m = 0.0f;
  float speed_kmh = 0.0f;
  uint8_t sats = 0;
  unsigned long fixMillis = 0;
  bool valid = false;
};

static unsigned long lastGpsByteMs = 0;
static LastGoodFix lastGoodFix;


static unsigned long lastGpsJsonMs = 0;
static unsigned long lastLoraTxMs = 0;

static bool rainStableWet = false;
static bool rainLastReadWet = false;
static unsigned long rainLastChangeMs = 0;


static const char* gpsStageName(GpsStage s) {
  switch (s) {
    case GPS_STAGE_WAITING_FOR_SIGNAL: return "waiting_for_signal";
    case GPS_STAGE_AVAILABLE_NO_LOCK: return "no_satellite_lock";
    case GPS_STAGE_LOCKED: return "locked";
    default: return "unknown";
  }
}

static bool isMinuteBoundaryNow(unsigned long nowMs) {
  if (nowMs < 60000UL) return false;
  return ((nowMs / 1000UL) % 60UL) == 0UL;
}

static void feedGps(unsigned long nowMs) {
  while (gpsSerial.available()) {
    char c = static_cast<char>(gpsSerial.read());
    gps.encode(c);
    lastGpsByteMs = nowMs;
  }
}

static bool gpsHasRecentBytes(unsigned long nowMs) {
  return (lastGpsByteMs != 0) && (nowMs - lastGpsByteMs <= GPS_NO_DATA_TIMEOUT_MS);
}

static bool gpsTryReadFix(float& lat, float& lon, unsigned long& ageMs) {
  gps.f_get_position(&lat, &lon, &ageMs);
  if (ageMs == TinyGPS::GPS_INVALID_AGE) return false;
  if (lat == TinyGPS::GPS_INVALID_F_ANGLE || lon == TinyGPS::GPS_INVALID_F_ANGLE) return false;
  return true;
}

static GpsStage getGpsStage(unsigned long nowMs, float& lat, float& lon, unsigned long& ageMs) {
  if (!gpsHasRecentBytes(nowMs)) {
    ageMs = TinyGPS::GPS_INVALID_AGE;
    lat = TinyGPS::GPS_INVALID_F_ANGLE;
    lon = TinyGPS::GPS_INVALID_F_ANGLE;
    return GPS_STAGE_WAITING_FOR_SIGNAL;
  }

  if (!gpsTryReadFix(lat, lon, ageMs)) {
    return GPS_STAGE_AVAILABLE_NO_LOCK;
  }

  if (ageMs < 2000UL) {
    return GPS_STAGE_LOCKED;
  }

  return GPS_STAGE_AVAILABLE_NO_LOCK;
}

static void updateLastGoodFixIfLocked(unsigned long nowMs, GpsStage stage, float lat, float lon) {
  if (stage != GPS_STAGE_LOCKED) return;

  lastGoodFix.lat = lat;
  lastGoodFix.lon = lon;
  lastGoodFix.alt_m = gps.f_altitude();
  lastGoodFix.speed_kmh = gps.f_speed_kmph();
  lastGoodFix.sats = static_cast<uint8_t>(gps.satellites());
  lastGoodFix.fixMillis = nowMs;
  lastGoodFix.valid = true;
}

static bool readRainWetDebounced(unsigned long nowMs, bool& wetEdgeToTrue) {
  wetEdgeToTrue = false;

  const int a = analogRead(RAIN_ANALOG);
  const bool wetNow = (a < RAIN_ANALOG_WET_THRESHOLD);

  if (wetNow != rainLastReadWet) {
    rainLastReadWet = wetNow;
    rainLastChangeMs = nowMs;
  }

  if ((nowMs - rainLastChangeMs) >= RAIN_DEBOUNCE_MS && rainStableWet != rainLastReadWet) {
    const bool prev = rainStableWet;
    rainStableWet = rainLastReadWet;
    if (!prev && rainStableWet) wetEdgeToTrue = true;
  }

  return rainStableWet;
}

static void buildSerialJson(
  char* out,
  size_t outSize,
  unsigned long nowMs,
  GpsStage stage,
  float lat,
  float lon,
  unsigned long ageMs,
  bool waterDetection
) {
  const bool important = waterDetection;

  if (stage == GPS_STAGE_LOCKED) {
    const float alt = gps.f_altitude();
    const float spd = gps.f_speed_kmph();
    const int sats = gps.satellites();

    snprintf(
      out,
      outSize,
      "{\"id\":%u,\"gps_stage\":%u,\"gps_stage_name\":\"%s\",\"latitude\":%.6f,\"longitude\":%.6f,\"altitude_m\":%.1f,\"speed_kmh\":%.1f,\"satellites\":%d,\"fix_age_ms\":%lu,\"water_detection\":%s,\"important_event\":%s,\"uptime_ms\":%lu}",
      static_cast<unsigned>(VEST_ID),
      static_cast<unsigned>(stage),
      gpsStageName(stage),
      lat,
      lon,
      alt,
      spd,
      sats,
      ageMs,
      waterDetection ? "true" : "false",
      important ? "true" : "false",
      nowMs
    );
    return;
  }

  snprintf(
    out,
    outSize,
    "{\"id\":%u,\"gps_stage\":%u,\"gps_stage_name\":\"%s\",\"water_detection\":%s,\"important_event\":%s,\"uptime_ms\":%lu}",
    static_cast<unsigned>(VEST_ID),
    static_cast<unsigned>(stage),
    gpsStageName(stage),
    waterDetection ? "true" : "false",
    important ? "true" : "false",
    nowMs
  );
}

static void buildLoraJson(
  char* out,
  size_t outSize,
  unsigned long nowMs,
  GpsStage stage,
  bool waterDetection
) {
  const bool important = waterDetection;

  
  if (lastGoodFix.valid) {
    snprintf(
      out,
      outSize,
      "{\"id\":%u,\"gs\":%u,\"gsn\":\"%s\",\"lat\":%.5f,\"lon\":%.5f,\"alt\":%.0f,\"spd\":%.1f,\"sat\":%u,\"fix_ms\":%lu,\"wet\":%s,\"imp\":%s,\"t\":%lu}",
      static_cast<unsigned>(VEST_ID),
      static_cast<unsigned>(stage),
      gpsStageName(stage),
      lastGoodFix.lat,
      lastGoodFix.lon,
      lastGoodFix.alt_m,
      lastGoodFix.speed_kmh,
      static_cast<unsigned>(lastGoodFix.sats),
      lastGoodFix.fixMillis,
      waterDetection ? "true" : "false",
      important ? "true" : "false",
      nowMs
    );
    return;
  }

  snprintf(
    out,
    outSize,
    "{\"id\":%u,\"gs\":%u,\"gsn\":\"%s\",\"loc\":false,\"wet\":%s,\"imp\":%s,\"t\":%lu}",
    static_cast<unsigned>(VEST_ID),
    static_cast<unsigned>(stage),
    gpsStageName(stage),
    waterDetection ? "true" : "false",
    important ? "true" : "false",
    nowMs
  );
}

static void sendLoraPayload(const char* payload) {
  LoRa.beginPacket();
  LoRa.print(payload);
  LoRa.endPacket();
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("TRANSMITTER_VEST booting...");

  
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  lastGpsByteMs = 0;

  
  SPI.begin(18, 19, 23, LORA_SS); 
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  if (!LoRa.begin(LORA_FREQ_HZ)) {
    Serial.println("LoRa INIT FAILED");
    while (true) { delay(1000); }
  }

  Serial.println("LoRa INIT OK");
}

void loop() {
  const unsigned long nowMs = millis();

  feedGps(nowMs);

  bool rainEdgeToTrue = false;
  bool waterDetection = rainStableWet;

  float lat = TinyGPS::GPS_INVALID_F_ANGLE;
  float lon = TinyGPS::GPS_INVALID_F_ANGLE;
  unsigned long ageMs = TinyGPS::GPS_INVALID_AGE;
  const GpsStage stage = getGpsStage(nowMs, lat, lon, ageMs);
  updateLastGoodFixIfLocked(nowMs, stage, lat, lon);

  const bool loraTxDue = (nowMs - lastLoraTxMs >= LORA_TX_INTERVAL_MS);

  
  if (nowMs - lastGpsJsonMs >= GPS_JSON_INTERVAL_MS) {
    lastGpsJsonMs = nowMs;
    const bool minuteBoundary = isMinuteBoundaryNow(nowMs);

    
    if (!minuteBoundary && !loraTxDue) {
      waterDetection = readRainWetDebounced(nowMs, rainEdgeToTrue);
    }

    if (!minuteBoundary) {
      char json[512];
      buildSerialJson(json, sizeof(json), nowMs, stage, lat, lon, ageMs, waterDetection);
      Serial.println(json);
    }
  }

  
  if (loraTxDue) {
    lastLoraTxMs = nowMs;
    char json[240];
    buildLoraJson(json, sizeof(json), nowMs, stage, waterDetection);
    sendLoraPayload(json);
    Serial.print("LoRa TX (scheduled): ");
    Serial.println(json);
  }

  
  if (rainEdgeToTrue) {
    char json[240];
    buildLoraJson(json, sizeof(json), nowMs, stage, waterDetection);
    sendLoraPayload(json);
    Serial.print("LoRa TX (rain analog): ");
    Serial.println(json);
  }

  delay(1);
}
