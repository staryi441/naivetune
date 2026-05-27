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
    export GOPATH=$HOME/go
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    ln -sf $GOPATH/bin/xcaddy /usr/bin/xcaddy
fi
xcaddy build --with github.com/caddyserver/forwardproxy@master=github.com/klzgrad/forwardproxy@naive
cp ./caddy /usr/local/bin/caddy && chmod +x /usr/local/bin/caddy

# Сборка Бэкенда с предварительной проверкой зависимостей
echo -e "${GREEN}--- Подготовка модулей Go ---${NC}"
export GOPROXY=https://proxy.golang.org,direct
[ ! -f "go.mod" ] && go mod init naivetune
go mod tidy

echo -e "${GREEN}--- Компиляция бэкенда ---${NC}"
go build -o naivetune-backend *.go
cp ./naivetune-backend /usr/local/bin/naivetune-backend && chmod +x /usr/local/bin/naivetune-backend

# --- БЛОК 4: Настройка структуры, данных и Caddyfile ---
echo -e "${GREEN}=== 4. Настройка системы и конфигурации ===${NC}"
mkdir -p /etc/caddy /var/lib/naivetune/templates /var/www/html

# Очищаем старые шаблоны в системной директории перед копированием свежих из репозитория
rm -rf /var/lib/naivetune/templates/*
if [ -d "./templates" ]; then
    cp -r ./templates/* /var/lib/naivetune/templates/
fi

ENV_FILE="/var/lib/naivetune/.env"
if [ ! -f "$ENV_FILE" ]; then
    # Данных нет — генерируем новые
    ADMIN_USER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    ADMIN_PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    WEB_PATH_RAW=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
    WEB_PATH="/${WEB_PATH_RAW}/"
    
    echo "ADMIN_USER=$ADMIN_USER" > $ENV_FILE
    echo "ADMIN_PASS=$ADMIN_PASS" >> $ENV_FILE
    echo "WEB_BASE_PATH=$WEB_PATH" >> $ENV_FILE
else
    # Данные уже есть — парсим их аккуратно без source (на случай специфических символов)
    ADMIN_USER=$(grep ADMIN_USER "$ENV_FILE" | cut -d '=' -f2)
    ADMIN_PASS=$(grep ADMIN_PASS "$ENV_FILE" | cut -d '=' -f2)
    WEB_PATH=$(grep WEB_BASE_PATH "$ENV_FILE" | cut -d '=' -f2)
fi

# Генерируем Caddyfile с разделением портов:
# Порт 80 — для внешних пользователей (отдает выбранный из админки шаблон из /var/www/html)
# Порт 2283 — для входа в панель управления
cat << EOF > /etc/caddy/Caddyfile
# Сайт-заглушка для внешних запросов по домену или IP
:80 {
    root * /var/www/html
    file_server
}

# Админ-панель NaiveTune
:2283 {
    reverse_proxy $WEB_PATH* 127.0.0.1:2283
    
    root * /var/www/html
    file_server
}
EOF

# Создание системных сервисов
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

# --- БЛОК 5: Создание утилиты naivetune ---
echo -e "${GREEN}=== 5. Создание утилиты контроля naivetune ===${NC}"
cat << 'EOF' > /usr/local/bin/naivetune
#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Раздельный опрос статуса служб
if systemctl is-active --quiet caddy; then CADDY_ST="${GREEN}RUNNING${NC}"; else CADDY_ST="${RED}STOPPED${NC}"; fi
if systemctl is-active --quiet naivetune; then BACKEND_ST="${GREEN}RUNNING${NC}"; else BACKEND_ST="${RED}STOPPED${NC}"; fi

if [ "$CADDY_ST" == "${GREEN}RUNNING${NC}" ] && [ "$BACKEND_ST" == "${GREEN}RUNNING${NC}" ]; then
    SYS_STATUS="${GREEN}OK (ALL RUNNING)${NC}"
else
    SYS_STATUS="${RED}ATTENTION (SOME SERVICES DOWN)${NC}"
fi

if [ -f "/var/lib/naivetune/.env" ]; then
    ADMIN_USER=$(grep ADMIN_USER "/var/lib/naivetune/.env" | cut -d '=' -f2)
    ADMIN_PASS=$(grep ADMIN_PASS "/var/lib/naivetune/.env" | cut -d '=' -f2)
    WEB_PATH=$(grep WEB_BASE_PATH "/var/lib/naivetune/.env" | cut -d '=' -f2)
fi

SERVER_IP=$(hostname -I | awk '{print $1}')
[ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"

clear
figlet NaiveTune
echo -e "========================================================="
echo -e "System Status: ${SYS_STATUS}"
echo -e "-> Caddy Server:  ${CADDY_ST}"
echo -e "-> Panel Backend: ${BACKEND_ST}"
echo -e "---------------------------------------------------------"
echo -e "username: ${GREEN}${ADMIN_USER:-N/A}${NC}"
echo -e "password: ${GREEN}${ADMIN_PASS:-N/A}${NC}"
echo -e "Access:   http://${SERVER_IP}:2283${WEB_PATH}"
echo -e "========================================================="

if [ "$CADDY_ST" == "${RED}STOPPED${NC}" ] || [ "$BACKEND_ST" == "${RED}STOPPED${NC}" ]; then
    echo -e "${RED}Рестарт служб: sudo systemctl restart caddy naivetune${NC}"
fi
EOF
chmod +x /usr/local/bin/naivetune

# --- БЛОК 6: Привязка к автозапуску терминала и вывод панели ---
if ! grep -q "naivetune" ~/.bashrc; then
    echo "naivetune" >> ~/.bashrc
fi

# Финальный вызов панели, чтобы сразу показать результат
naivetune