# Когда что-то не работает

Порядок проверки — сверху вниз. Почти всё ловится на первых трёх шагах.

## Сначала

```bash
docker compose ps                  # оба контейнера Up?
docker compose logs -f mosquitto   # что видит брокер
docker compose logs -f node-red    # что видит Node-RED
npm run listen "#"                 # долетают ли вообще сообщения
```

`npm run listen` — главный инструмент. Он сразу разделяет две очень разные
ситуации: «устройство не шлёт» и «шлёт, но принимающая сторона не видит».

---

## Node-RED: «Connection failed to broker»

**Смотри в логи Mosquitto.** Там написана причина.

| Что в логах Mosquitto | Что это значит |
|---|---|
| `disconnected, not authorised` | Не тот логин/пароль |
| `Socket error`, тишина | Не доходит до брокера вообще |
| `Client ... already connected` | Два клиента с одинаковым clientId выпихивают друг друга |

**not authorised.** Проверь, что `flows_cred.json` существует и содержит
плейсхолдеры `${MQTT_USER}` / `${MQTT_PASSWORD}`, а в `.env` есть эти переменные:

```bash
cat node-red/data/flows_cred.json
grep MQTT_ .env
docker compose exec node-red printenv MQTT_USER MQTT_PASSWORD
```

Если последняя команда печатает пустоту — перезапусти: `docker compose up -d`.
Переменные окружения подхватываются только при пересоздании контейнера,
`restart` их не обновляет.

**Хост брокера.** Внутри docker-сети это `mosquitto`, а не `localhost`.
Для Node-RED в контейнере `localhost` — это он сам.

---

## Не могу войти в Node-RED

Если пароль точно правильный, а вход не проходит — почти наверняка
повреждён bcrypt-хеш. В нём есть символы `$`, и Docker Compose трактует
их в `.env` как подстановку переменной.

Проверка:

```bash
grep NODE_RED_ADMIN_HASH .env                              # должно быть $$2a$$08$$...
docker compose exec node-red printenv NODE_RED_ADMIN_HASH  # должно быть $2a$08$...
```

В `.env` доллары **удвоены**, в контейнере — **одинарные**. Если в логах
`docker compose up` мелькает `The "..." variable is not set` — это оно.
`scripts/setup.sh` экранирует автоматически; если правил `.env` руками,
удвой доллары обратно.

Пароль забыт? Он нигде не хранится в открытом виде — перегенерируй:
`bash scripts/setup.sh` (и заново `docker compose up -d`).

---

## Mosquitto не стартует

```bash
docker compose logs mosquitto
```

| Сообщение | Причина |
|---|---|
| `Error: Unable to open config file` | Не смонтировался `mosquitto.conf` — запускай compose из корня репозитория |
| `Unknown configuration variable` | В конфиг попали CRLF. Виновата настройка git на Windows — см. ниже |
| `Error: Unable to open pwfile` | Нет `mosquitto/config/passwd` — запусти `scripts/setup.sh` |

**`Warning: File ... owner is not root`** — это предупреждение, а не ошибка.
Брокер работает. Возникает из-за того, что файл лежит на хостовой файловой
системе через bind-mount. Игнорируй.

### CRLF после клонирования на Windows

Симптом: Mosquitto ругается на каждую строку конфига.
В репозитории есть `.gitattributes`, который это предотвращает, но если
файлы уже склонированы «криво»:

```bash
git config --global core.autocrlf input
git rm --cached -r .
git reset --hard
```

---

## ESP32 не подключается

**Проверь по порядку:**

1. **Адрес брокера.** В `secrets.yaml` / `secrets.h` должен быть IP компьютера
   в локальной сети, а не `localhost`.
   macOS: `ipconfig getifaddr en0` · Windows: `ipconfig` → IPv4-адрес.
2. **Wi-Fi 2,4 ГГц.** ESP32 не работает с 5 ГГц. Совсем.
3. **Один clientId на устройство.** Два одинаковых — и они будут по очереди
   выкидывать друг друга, выглядит как «постоянно отваливается».
4. **Брандмауэр.** Windows Defender по умолчанию блокирует входящие
   на 1883. Нужно разрешить порт или разрешить Docker Desktop в правилах.
5. **Слушает ли брокер снаружи.** В `.env` должно быть `MQTT_BIND=0.0.0.0`.
   При `127.0.0.1` брокер доступен только с самого компьютера, и плата
   до него не достучится.

**Коды ошибок в мониторе порта (Arduino):**

| rc | Значение |
|----|----------|
| -2 | Не доходит до хоста: не тот IP, брандмауэр, или брокер не слушает |
| 4  | Неверный логин или пароль |
| 5  | Не авторизован |

**Плата перезагружается по кругу.** Обычно питание: USB-порт ноутбука
не тянет пиковые 500 мА. Возьми зарядник на 1 А и более.

**BME280 не найден.** Адрес бывает 0x76 и 0x77 (конфиги пробуют оба),
но чаще виновата проводка: VCC на **3V3**, не на 5 В; SDA → GPIO21,
SCL → GPIO22. В логах ESPHome при `scan: true` видно найденные I²C-адреса.

---

## Дашборд пустой

Открывается, но виджеты без значений.

1. Дошли ли данные до брокера: `npm run listen "home/kitchen/#"`
2. Дошли ли до Node-RED: в редакторе на вкладке «Кухня» под mqtt-нодой
   должна быть надпись `connected`, а справа в панели «Отладка» — сообщения.
3. Нет ли ошибки в function-ноде — она подсвечивается красным.
4. Данные приходят только после подключения. Если датчик публикует с флагом
   `retain`, последнее значение придёт сразу; без retain придётся ждать
   следующей отправки.

Адрес дашборда: **http://localhost:1880/dashboard**
(не `/ui` — это путь старого дашборда 1.x).

---

## Порт занят

```
Bind for 0.0.0.0:1880 failed: port is already allocated
```

Кто-то уже слушает порт.

```bash
# macOS / Linux
lsof -i :1880
# Windows (PowerShell)
Get-NetTCPConnection -LocalPort 1880 | Select-Object OwningProcess
```

Либо освободи порт, либо поменяй его в `docker-compose.yml`
(левое число: `"1881:1880"`).

---

## Начать с нуля

```bash
docker compose down -v          # -v удалит и данные брокера
rm -rf node-red/data/node_modules node-red/data/.config.*
rm -f .env node-red/data/flows_cred.json mosquitto/config/passwd
bash scripts/setup.sh
docker compose up -d --build
```

Флоу (`node-red/data/flows.json`) это не тронет — они в репозитории.
