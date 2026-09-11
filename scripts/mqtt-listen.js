#!/usr/bin/env node
/**
 * Подписывается на всё подряд и печатает в консоль.
 * Первый инструмент отладки: «доходят ли вообще сообщения до брокера?»
 *
 * Запуск:  npm run listen
 *          node scripts/mqtt-listen.js "home/kitchen/#"
 */
require('dotenv').config();
const mqtt = require('mqtt');

const TOPIC = process.argv[2] || '#';
const client = mqtt.connect(`mqtt://${process.env.MQTT_HOST || 'localhost'}:${process.env.MQTT_PORT || 1883}`, {
  username: process.env.MQTT_USER || 'iot',
  password: process.env.MQTT_PASSWORD,
  clientId: `listener-${Math.random().toString(16).slice(2, 8)}`,
});

client.on('connect', () => {
  console.log(`Слушаю "${TOPIC}". Ctrl+C для выхода.\n`);
  client.subscribe(TOPIC);
});

client.on('message', (topic, payload, packet) => {
  const time = new Date().toLocaleTimeString('ru-RU');
  const flag = packet.retain ? ' [retained]' : '';
  console.log(`${time}  ${topic}${flag}\n          ${payload.toString()}`);
});

client.on('error', (e) => console.error('Ошибка:', e.message));
