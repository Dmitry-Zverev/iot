#!/usr/bin/env bash
# =====================================================================
#  Первичная настройка стенда: генерирует пароли и файл .env
#  Запуск (macOS / Linux / Git Bash в Windows):
#     bash scripts/setup.sh
#  Повторный запуск перезапишет секреты — понадобится заново указать
#  пароль в MQTT-нодах Node-RED.
# =====================================================================
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "==> Проверяю Docker"
if ! docker info >/dev/null 2>&1; then
  echo "Docker не запущен. Открой Docker Desktop и повтори." >&2
  exit 1
fi

if [ -f .env ]; then
  printf ".env уже существует. Перезаписать секреты? [y/N] "
  read -r answer
  [ "$answer" = "y" ] || [ "$answer" = "Y" ] || { echo "Отменено."; exit 0; }
fi

# Генератор пароля. head закрывает канал раньше, чем tr закончит читать,
# tr получает SIGPIPE — и при set -o pipefail это убило бы весь скрипт.
# Поэтому изолируем в подоболочке с выключенным pipefail.
rand() { ( set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${1:-24}" ); }

MQTT_USER="iot"
MQTT_PASSWORD="$(rand 24)"
NODE_RED_ADMIN_USER="admin"
NODE_RED_ADMIN_PASSWORD="$(rand 16)"
NODE_RED_CREDENTIAL_SECRET="$(rand 32)"

echo "==> Создаю файл паролей Mosquitto"
mkdir -p mosquitto/config
docker run --rm -v "$ROOT/mosquitto/config:/mosquitto/config" \
  eclipse-mosquitto:2.0 \
  mosquitto_passwd -b -c /mosquitto/config/passwd "$MQTT_USER" "$MQTT_PASSWORD"

echo "==> Генерирую bcrypt-хеш пароля Node-RED"
NODE_RED_ADMIN_HASH="$(docker run --rm --entrypoint node nodered/node-red:4.0 \
  -e "console.log(require('bcryptjs').hashSync(process.argv[1], 8))" \
  "$NODE_RED_ADMIN_PASSWORD")"

# bcrypt-хеш содержит символы $. Docker Compose трактует их в .env как
# подстановку переменной и молча съедает кусок хеша — логин потом не работает.
# Экранируем: $ -> $$
NODE_RED_ADMIN_HASH_ESC="${NODE_RED_ADMIN_HASH//\$/\$\$}"

echo "==> Пишу .env"
cat > .env <<EOF
TZ=Europe/Moscow

MQTT_BIND=0.0.0.0
MQTT_HOST=localhost
MQTT_PORT=1883
MQTT_USER=$MQTT_USER
MQTT_PASSWORD=$MQTT_PASSWORD

NODERED_BIND=0.0.0.0
NODE_RED_ADMIN_USER=$NODE_RED_ADMIN_USER
NODE_RED_ADMIN_HASH=$NODE_RED_ADMIN_HASH_ESC
NODE_RED_CREDENTIAL_SECRET=$NODE_RED_CREDENTIAL_SECRET
EOF

echo "==> Создаю flows_cred.json с плейсхолдерами"
# Node-RED умеет подставлять ${ПЕРЕМЕННЫЕ} внутрь credentials, поэтому
# здесь нет реальных паролей — только ссылки на .env.
# Файл всё равно в .gitignore: после первого «Deploy» Node-RED перезапишет
# его зашифрованным содержимым, и это уже не место для git.
cat > node-red/data/flows_cred.json <<'CRED'
{
    "broker-mosquitto": {
        "user": "${MQTT_USER}",
        "password": "${MQTT_PASSWORD}"
    }
}
CRED

# Определяем LAN-IP, он понадобится для прошивки ESP32
LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo '')"

cat <<EOF

=====================================================================
 Готово. Секреты записаны в .env (этот файл в git НЕ попадает).

 Node-RED:   http://localhost:1880
   логин:    $NODE_RED_ADMIN_USER
   пароль:   $NODE_RED_ADMIN_PASSWORD

 MQTT:       порт 1883
   логин:    $MQTT_USER
   пароль:   $MQTT_PASSWORD

 IP для прошивки ESP32: ${LAN_IP:-<узнай сам: ipconfig / ipconfig getifaddr en0>}

 !! Запиши пароль Node-RED сейчас — в .env лежит только его хеш,
    обратно он не восстанавливается.

 Дальше:  docker compose up -d
=====================================================================
EOF
