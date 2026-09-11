#!/usr/bin/env node
/**
 * Виртуальный датчик: шлёт в MQTT правдоподобные температуру/влажность/давление,
 * как это делал бы настоящий ESP32. Нужен, чтобы учить Node-RED,
 * пока железо едет с маркетплейса.
 *
 * Запуск:  npm install && npm run sim
 * Стоп:    Ctrl+C
 */
require('dotenv').config();
const mqtt = require('mqtt');

const HOST     = process.env.MQTT_HOST     || 'localhost';
const PORT     = process.env.MQTT_PORT     || 1883;
const USER     = process.env.MQTT_USER     || 'iot';
const PASSWORD = process.env.MQTT_PASSWORD;
const ROOM     = process.argv[2] || 'kitchen';
const PERIOD   = Number(process.argv[3] || 5000);

if (!PASSWORD) {
  console.error('Нет MQTT_PASSWORD. Запусти сначала scripts/setup.sh (или setup.ps1).');
  process.exit(1);
}

const base = `home/${ROOM}`;

const client = mqtt.connect(`mqtt://${HOST}:${PORT}`, {
  username: USER,
  password: PASSWORD,
  clientId: `fake-sensor-${ROOM}-${Math.random().toString(16).slice(2, 8)}`,
  // Last Will: брокер сам скажет "offline", если процесс умрёт некрасиво
  will: { topic: `${base}/status`, payload: 'offline', qos: 0, retain: true },
});

// Состояние «физического мира»: плавно дрейфует, а не прыгает случайно
let temp = 22.0, hum = 45.0, press = 1013.0;
const drift = (v, step, min, max) =>
  Math.min(max, Math.max(min, v + (Math.random() - 0.5) * step));

client.on('connect', () => {
  console.log(`Подключился к ${HOST}:${PORT}, комната "${ROOM}", период ${PERIOD} мс`);
  client.publish(`${base}/status`, 'online', { retain: true });
  client.subscribe(`${base}/relay/set`);

  setInterval(() => {
    temp  = drift(temp, 0.4, 15, 30);
    hum   = drift(hum, 1.5, 30, 70);
    press = drift(press, 0.6, 990, 1030);

    const send = (topic, value) =>
      client.publish(`${base}/${topic}`, value.toFixed(2), { retain: true });

    send('temperature', temp);
    send('humidity', hum);
    send('pressure', press);

    console.log(`-> ${base}: ${temp.toFixed(1)}°C  ${hum.toFixed(0)}%  ${press.toFixed(0)} гПа`);
  }, PERIOD);
});

// Реагируем на команды реле — как настоящая плата
client.on('message', (topic, payload) => {
  const cmd = payload.toString().trim();
  console.log(`<- ${topic}: ${cmd}`);
  if (topic === `${base}/relay/set`) {
    const on = ['ON', 'on', '1', 'true'].includes(cmd);
    client.publish(`${base}/relay`, on ? 'ON' : 'OFF', { retain: true });
  }
});

client.on('error', (err) => {
  console.error('Ошибка MQTT:', err.message);
  if (err.message.includes('Not authorized') || err.code === 5) {
    console.error('Логин/пароль не подошли. Сверь MQTT_USER и MQTT_PASSWORD в .env');
  }
});

process.on('SIGINT', () => {
  client.publish(`${base}/status`, 'offline', { retain: true }, () => {
    client.end(false, () => process.exit(0));
  });
});
