#!/bin/bash
set -e
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# --- БЛОК 1: Подготовка и проверка ---
if [ "$EUID" -ne 0 ]; then echo -e "${RED}Запустите через sudo!${NC}"; exit 1; fi

echo -e "${GREEN}=== Проверка ОС ===${NC}"
if [ -f /etc/os-release ]; then . /etc/os-release; else echo "Ошибка ОС"; exit 1; fi
if [ "$ID" != "ubuntu" ] && [ "$ID" != "debian" ]; then echo "Только Ubuntu/Debian"; exit 1; fi

echo -e "${GREEN}=== 1. Установка системных зависимостей ===${NC}"
apt-get update && apt-get install -y wget curl git ufw tar gzip figlet

# --- БЛОК 2: Установка Go ---
if ! command -v go &> /dev/null; then
    echo -e "${GREEN}=== 2. Установка среды Go ===${NC}"
    wget -q https://go.dev/dl/go1.22.2.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz
    rm go1.22.2.linux-amd64.tar.gz
    ln -sf /usr/local/go/bin/go /usr/bin/go
fi

# --- БЛОК 3: Сборка Caddy и Бэкенда ---
echo -e "${GREEN}=== 3. Сборка Caddy и Бэкенда ===${NC}"

# Сборка Caddy
if ! command -v xcaddy &> /dev/null; then
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    ln -sf ~/go/bin/xcaddy /usr/bin/go/bin/xcaddy # Исправил путь, если go в /usr/local/go
fi
xcaddy build --with github.com/caddyserver/forwardproxy@master=github.com/klzgrad/forwardproxy@naive
cp ./caddy /usr/local/bin/caddy && chmod +x /usr/local/bin/caddy

# Сборка Бэкенда с предварительной проверкой зависимостей
echo -e "${GREEN}--- Подготовка модулей Go ---${NC}"
export GOPROXY=https://proxy.golang.org,direct
# Если go.mod нет, инициализируем
[ ! -f "go.mod" ] && go mod init naivetune
# Скачиваем и чистим зависимости
go mod tidy

echo -e "${GREEN}--- Компиляция бэкенда ---${NC}"
go build -o naivetune-backend *.go
cp ./naivetune-backend /usr/local/bin/naivetune-backend && chmod +x /usr/local/bin/naivetune-backend

# --- БЛОК 4: Структура и Systemd ---
echo -e "${GREEN}=== 4. Настройка системы ===${NC}"
mkdir -p /etc/caddy /var/lib/naivetune/templates /var/www/html
[ -f "./Caddyfile.template" ] && cp ./Caddyfile.template /var/lib/naivetune/
[ -d "./templates" ] && cp -r ./templates/* /var/lib/naivetune/templates/

# Создание сервисов
cat << EOF > /etc/systemd/system/caddy.service
[Unit]
Description=Caddy Server
After=network.target
[Service]
ExecStart=/usr/local/bin/caddy run --config /etc/caddy/Caddyfile
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /etc/systemd/system/naivetune.service
[Unit]
Description=Naivetune Panel
After=network.target
[Service]
WorkingDirectory=/var/lib/naivetune
ExecStart=/usr/local/bin/naivetune-backend
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable caddy naivetune
systemctl restart caddy naivetune

# --- ГЕНЕРАЦИЯ АДМИН-ДАННЫХ ПРИ ПЕРВОЙ УСТАНОВКЕ ---
ENV_FILE="/var/lib/naivetune/.env"

if [ ! -f "$ENV_FILE" ]; then
    # Генерируем рандомные данные
    ADMIN_USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    ADMIN_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    WEB_PATH="/"$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)"/"
    
    # Записываем их в файл
    echo "ADMIN_USER=$ADMIN_USER" > $ENV_FILE
    echo "ADMIN_PASS=$ADMIN_PASS" >> $ENV_FILE
    echo "WEB_BASE_PATH=$WEB_PATH" >> $ENV_FILE
    
    # Выводим «красивую» панель
    clear
    figlet NaiveTune
    echo -e "========================================================="
    echo -e "Warning: Panel is not secure with SSL"
    echo -e "username: ${GREEN}$ADMIN_USER${NC}"
    echo -e "password: ${GREEN}$ADMIN_PASS${NC}"
    echo -e "port: 2283"
    echo -e "webBasePath: ${GREEN}$WEB_PATH${NC}"
    echo -e "Access URL: http://<ВАШ_IP>:2283$WEB_PATH"
    echo -e "========================================================="
else
    echo -e "${GREEN}Настройки уже существуют, пропускаем генерацию.${NC}"
fi=