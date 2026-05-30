#define RAIN_ANALOG 34
#define RAIN_DIGITAL 27

void setup() {
  Serial.begin(115200);

  pinMode(RAIN_DIGITAL, INPUT); 
  Serial.println("Rain sensor test starting...");
}

void loop() {
  int analogValue = analogRead(RAIN_ANALOG);
  int digitalValue = digitalRead(RAIN_DIGITAL);

  Serial.print("Analog: ");
  Serial.print(analogValue);

  Serial.print(" | Digital (L): ");
  Serial.println(digitalValue);

  delay(500);
}
