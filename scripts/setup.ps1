<#
  Первичная настройка стенда для Windows (PowerShell).
  Запуск:
      powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
  Повторный запуск перезапишет секреты.
#>
$ErrorActionPreference = "Stop"

Set-Location (Join-Path $PSScriptRoot "..")
$Root = (Get-Location).Path

Write-Host "==> Проверяю Docker"
docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker не запущен. Открой Docker Desktop и повтори."
    exit 1
}

if (Test-Path ".env") {
    $answer = Read-Host ".env уже существует. Перезаписать секреты? [y/N]"
    if ($answer -ne "y" -and $answer -ne "Y") { Write-Host "Отменено."; exit 0 }
}

function New-Password([int]$Length = 24) {
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".ToCharArray()
    $bytes = [byte[]]::new($Length)
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

$MqttUser        = "iot"
$MqttPassword    = New-Password 24
$NodeRedUser     = "admin"
$NodeRedPassword = New-Password 16
$CredentialSecret= New-Password 32

Write-Host "==> Создаю файл паролей Mosquitto"
New-Item -ItemType Directory -Force -Path "mosquitto\config" | Out-Null
docker run --rm -v "${Root}\mosquitto\config:/mosquitto/config" `
    eclipse-mosquitto:2.0 `
    mosquitto_passwd -b -c /mosquitto/config/passwd $MqttUser $MqttPassword
if ($LASTEXITCODE -ne 0) { Write-Error "mosquitto_passwd не отработал"; exit 1 }

Write-Host "==> Генерирую bcrypt-хеш пароля Node-RED"
$NodeRedHash = docker run --rm --entrypoint node nodered/node-red:4.0 `
    -e "console.log(require('bcryptjs').hashSync(process.argv[1], 8))" $NodeRedPassword
if ($LASTEXITCODE -ne 0) { Write-Error "Не удалось сгенерировать хеш"; exit 1 }
$NodeRedHash = $NodeRedHash.Trim()
# bcrypt-хеш содержит $. Docker Compose трактует их в .env как подстановку
# переменной и молча портит хеш. Экранируем: $ -> $$
$NodeRedHashEsc = $NodeRedHash.Replace('$', '$$')

Write-Host "==> Пишу .env"
$envContent = @"
TZ=Europe/Moscow

MQTT_BIND=0.0.0.0
MQTT_HOST=localhost
MQTT_PORT=1883
MQTT_USER=$MqttUser
MQTT_PASSWORD=$MqttPassword

NODERED_BIND=0.0.0.0
NODE_RED_ADMIN_USER=$NodeRedUser
NODE_RED_ADMIN_HASH=$NodeRedHashEsc
NODE_RED_CREDENTIAL_SECRET=$CredentialSecret
"@
# Docker Compose не любит BOM в .env — пишем чистый UTF-8 с LF
$envContent = $envContent -replace "`r`n", "`n"
[System.IO.File]::WriteAllText((Join-Path $Root ".env"), $envContent, `
    (New-Object System.Text.UTF8Encoding $false))

Write-Host "==> Создаю flows_cred.json с плейсхолдерами"
# Node-RED подставляет ${ПЕРЕМЕННЫЕ} внутрь credentials, поэтому реальных
# паролей тут нет - только ссылки на .env.
$credJson = @"
{
    "broker-mosquitto": {
        "user": "`${MQTT_USER}",
        "password": "`${MQTT_PASSWORD}"
    }
}
"@
[System.IO.File]::WriteAllText((Join-Path $Root "node-red\data\flows_cred.json"), `
    ($credJson -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding $false))

$LanIp = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet|WSL' -and $_.IPAddress -notmatch '^169\.' } |
    Select-Object -First 1 -ExpandProperty IPAddress)

Write-Host @"

=====================================================================
 Готово. Секреты записаны в .env (этот файл в git НЕ попадает).

 Node-RED:   http://localhost:1880
   логин:    $NodeRedUser
   пароль:   $NodeRedPassword

 MQTT:       порт 1883
   логин:    $MqttUser
   пароль:   $MqttPassword

 IP для прошивки ESP32: $LanIp

 !! Запиши пароль Node-RED сейчас - в .env лежит только его хеш,
    обратно он не восстанавливается.

 Дальше:  docker compose up -d
=====================================================================
"@
