/* =====================================================================
 *  ESP32 + BME280 -> MQTT, «руками» на Arduino C++
 *
 *  Это альтернатива ESPHome для тех, кто хочет понимать, что происходит
 *  под капотом. ESPHome делает ровно то же самое, но за тебя.
 *
 *  Подготовка в Arduino IDE:
 *   1. File > Preferences > Additional Boards Manager URLs:
 *      https://espressif.github.io/arduino-esp32/package_esp32_index.json
 *   2. Tools > Board > Boards Manager > поставить "esp32 by Espressif"
 *   3. Tools > Board > ESP32 Dev Module
 *   4. Sketch > Include Library > Manage Libraries, поставить:
 *        - PubSubClient (Nick O'Leary)
 *        - Adafruit BME280 Library (подтянет Adafruit Unified Sensor)
 *   5. Скопировать secrets.h.example -> secrets.h и заполнить
 *
 *  Распиновка BME280 (I2C):
 *    VCC -> 3V3   GND -> GND   SCL -> GPIO22   SDA -> GPIO21
 *  Реле:
 *    IN  -> GPIO23   VCC -> 5V (VIN)   GND -> GND
 * ===================================================================== */

#include <WiFi.h>
#include <PubSubClient.h>
#include <Wire.h>
#include <Adafruit_BME280.h>
#include "secrets.h"

// --- Топики. Схема описана в docs/MQTT-TOPICS.md ---
const char* TOPIC_TEMP   = "home/kitchen/temperature";
const char* TOPIC_HUM    = "home/kitchen/humidity";
const char* TOPIC_PRESS  = "home/kitchen/pressure";
const char* TOPIC_STATUS = "home/kitchen/status";
const char* TOPIC_RELAY       = "home/kitchen/relay";
const char* TOPIC_RELAY_SET   = "home/kitchen/relay/set";

const int RELAY_PIN = 23;
const unsigned long PUBLISH_INTERVAL_MS = 30000;

WiFiClient   net;
PubSubClient mqtt(net);
Adafruit_BME280 bme;

unsigned long lastPublish = 0;
bool bmeFound = false;

// ---------------------------------------------------------------------
// Приходящие команды: home/kitchen/relay/set  <-  "ON" / "OFF"
// ---------------------------------------------------------------------
void onMessage(char* topic, byte* payload, unsigned int length) {
  String msg;
  for (unsigned int i = 0; i < length; i++) msg += (char)payload[i];
  msg.trim();

  Serial.printf("[MQTT] %s = %s\n", topic, msg.c_str());

  if (String(topic) == TOPIC_RELAY_SET) {
    bool on = (msg == "ON" || msg == "on" || msg == "1" || msg == "true");
    digitalWrite(RELAY_PIN, on ? HIGH : LOW);
    // Подтверждаем новое состояние с retain, чтобы Node-RED увидел его
    // сразу при подключении, а не ждал следующего переключения.
    mqtt.publish(TOPIC_RELAY, on ? "ON" : "OFF", true);
  }
}

void connectWiFi() {
  Serial.printf("WiFi: подключаюсь к %s", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.printf("\nWiFi: есть. IP = %s\n", WiFi.localIP().toString().c_str());
}

void connectMQTT() {
  while (!mqtt.connected()) {
    String clientId = "esp32-kitchen-" + String((uint32_t)ESP.getEfuseMac(), HEX);
    Serial.printf("MQTT: подключаюсь к %s:%d ... ", MQTT_HOST, MQTT_PORT);

    // Last Will: если плата молча отвалится (питание/WiFi),
    // брокер сам разошлёт "offline" в топик статуса.
    bool ok = mqtt.connect(
        clientId.c_str(),
        MQTT_USER, MQTT_PASSWORD,
        TOPIC_STATUS, 0, true, "offline");

    if (ok) {
      Serial.println("есть");
      mqtt.publish(TOPIC_STATUS, "online", true);
      mqtt.subscribe(TOPIC_RELAY_SET);
    } else {
      // rc=-2 сеть//хост недоступен, rc=4 неверный логин-пароль, rc=5 не авторизован
      Serial.printf("ошибка, rc=%d. Повтор через 5 с\n", mqtt.state());
      delay(5000);
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);

  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);

  Wire.begin(21, 22);
  // У разных модулей адрес 0x76 или 0x77 — пробуем оба
  bmeFound = bme.begin(0x76) || bme.begin(0x77);
  if (!bmeFound) Serial.println("BME280 не найден! Проверь провода и адрес I2C.");

  connectWiFi();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(onMessage);
  mqtt.setBufferSize(512);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) connectWiFi();
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();   // обязательно: качает входящие сообщения и держит keepalive

  if (millis() - lastPublish >= PUBLISH_INTERVAL_MS) {
    lastPublish = millis();
    if (!bmeFound) return;

    char buf[16];

    dtostrf(bme.readTemperature(), 1, 2, buf);
    mqtt.publish(TOPIC_TEMP, buf, true);
    Serial.printf("-> %s = %s\n", TOPIC_TEMP, buf);

    dtostrf(bme.readHumidity(), 1, 2, buf);
    mqtt.publish(TOPIC_HUM, buf, true);

    // Па -> гПа
    dtostrf(bme.readPressure() / 100.0F, 1, 2, buf);
    mqtt.publish(TOPIC_PRESS, buf, true);
  }
}
