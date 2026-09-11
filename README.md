# IoT-стенд: MQTT + Node-RED + ESP32

Учебный стенд для JS-разработчика: MQTT-брокер, Node-RED с дашбордом и
готовые прошивки для ESP32. Поднимается одной командой, работает на
Windows и macOS.

Учиться можно сразу — в комплекте виртуальный датчик, который шлёт
правдоподобные данные, пока железо едет с маркетплейса.

---

## Старт

Нужен только [Docker Desktop](https://www.docker.com/products/docker-desktop/)
(и Node.js, если захочешь запускать виртуальный датчик).

```bash
git clone <адрес-репозитория>
cd iot
```

**macOS / Linux:**
```bash
bash scripts/setup.sh
docker compose up -d
```

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
docker compose up -d
```

`setup` сгенерирует пароли и покажет их **один раз** — запиши.
Первый `docker compose up` соберёт образ Node-RED с дашбордом, это пара минут.

Дальше:

| Что | Адрес |
|-----|-------|
| Редактор Node-RED | http://localhost:1880 |
| Дашборд | http://localhost:1880/dashboard |
| MQTT | порт 1883 |

Проверить, что всё живое, без единого датчика:

```bash
npm install
npm run sim        # виртуальный датчик шлёт данные в MQTT
npm run listen     # смотреть сырой поток сообщений
```

Открой дашборд — приборы показывают данные.

---

## Что внутри

```
├── docker-compose.yml          Mosquitto + Node-RED
├── .env                        пароли (создаётся setup, в git не попадает)
├── mosquitto/config/
│   ├── mosquitto.conf          конфиг брокера
│   └── passwd                  пароли MQTT (генерируется)
├── node-red/
│   ├── Dockerfile              Node-RED + Dashboard 2.0
│   └── data/
│       ├── settings.js         настройки, секреты — из переменных окружения
│       └── flows.json          готовые флоу (версионируются git'ом)
├── esp32/
│   ├── esphome/                прошивка на YAML — рекомендуемый путь
│   └── arduino/                та же прошивка на C++, чтобы понять механику
├── scripts/
│   ├── setup.sh / setup.ps1    генерация паролей
│   ├── fake-sensor.js          виртуальный датчик
│   └── mqtt-listen.js          консольный подписчик
└── docs/
    ├── LEARNING.md             план на 4 недели, ссылки, грабли
    ├── HARDWARE.md             что покупать и как подключать
    ├── MQTT-TOPICS.md          схема топиков
    └── TROUBLESHOOTING.md      когда не работает
```

**Начни с [docs/LEARNING.md](docs/LEARNING.md)** — там план обучения и материалы.

---

## Готовые флоу

Вкладка **«Кухня»** — рабочий пример: температура, влажность и давление
с датчика идут на приборы и график, тумблер управляет реле, статус
показывает, жив ли датчик.

Вкладка **«Песочница»** — учебные примеры: inject → function → debug
и генератор фейковых данных прямо внутри Node-RED.

---

## Про безопасность

Стенд сделан так, чтобы его можно было оставить в локальной сети:

- **Анонимный доступ к MQTT закрыт.** Брокер доступен из локальной сети —
  иначе ESP32 до него не достучится — но требует логин и пароль.
- **Вход в Node-RED по паролю.** Иначе любой в той же сети открывает
  редактор и правит твои сценарии.
- **Секреты не попадают в git.** `.env`, `passwd` и `flows_cred.json`
  в `.gitignore`. В `flows.json` лежат только ссылки на переменные окружения.

Чего делать **не надо**: пробрасывать порты 1883 и 1880 через роутер
наружу. Ни MQTT, ни редактор Node-RED не рассчитаны на открытый интернет.
Нужен доступ извне — поднимай VPN (WireGuard) или Tailscale.

---

## Частые команды

```bash
docker compose up -d           # запустить
docker compose down            # остановить
docker compose logs -f         # логи обоих сервисов
docker compose up -d --build   # пересобрать после правки Dockerfile

npm run sim                    # виртуальный датчик (Ctrl+C — стоп)
npm run sim bedroom 10000      # другая комната, период 10 с
npm run listen "home/#"        # подписка на топики
```

Не работает — см. [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).
