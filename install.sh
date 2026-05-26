#!/bin/bash

# Скрипт автоматического развертывания Naivetune (Универсальный: VPS / WSL)
set -e

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0;0m'

echo -e "${GREEN}=== Проверка операционной системы ===${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}Ошибка: невозможно определить ОС.${NC}"
    exit 1
fi

if [ "$OS" != "ubuntu" ] && [ "$OS" != "debian" ]; then
    echo -e "${RED}Скрипт поддерживает только Ubuntu или Debian.${NC}"
    exit 1
fi

echo -e "${GREEN}=== 1. Установка системных зависимостей ($OS) ===${NC}"
apt-get update || true
apt-get install -y wget curl git ufw tar gzip

echo -e "${GREEN}=== 2. Установка среды Go ===${NC}"
if ! command -v go &> /dev/null; then
    GO_VERSION="1.22.2"
    wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    rm go${GO_VERSION}.linux-amd64.tar.gz
    ln -sf /usr/local/go/bin/go /usr/bin/go
fi
echo "Go версия: $(go version)"

echo -e "${GREEN}=== 3. Сборка кастомного Caddy с NaiveProxy ===${NC}"
if [ ! -f ./caddy ]; then
    if ! command -v xcaddy &> /dev/null; then
        go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
        ln -sf ~/go/bin/xcaddy /usr/bin/xcaddy
	fi
    # Сборка caddy с плагином маскировочного прокси
    xcaddy build --with github.com/caddyserver/forwardproxy@master=github.com/klzgrad/forwardproxy@naive
fi

# Перенос бинарника Caddy в системную папку
cp ./caddy /usr/local/bin/caddy
chmod +x /usr/local/bin/caddy

echo -e "${GREEN}=== 4. Подготовка структуры папок ===${NC}"
mkdir -p /etc/caddy
mkdir -p /var/lib/naivetune/templates
mkdir -p /var/www/html

# Копирование шаблона конфигурации и заглушек сайтов
cp ./Caddyfile.template /var/lib/naivetune/Caddyfile.template

if [ -d "./templates" ]; then
    cp -r ./templates/* /var/lib/naivetune/templates/
    # Берем один из шаблонов (landing1) как дефолтный сайт-маскировку
    if [ -d "./templates/landing1" ]; then
        cp -r ./templates/landing1/* /var/www/html/
	fi
fi

echo -e "${GREEN}=== 5. Компиляция бэкенда панели ===${NC}"
export GOPROXY=https://proxy.golang.org,direct
go build -o naivetune-backend *.go
cp ./naivetune-backend /usr/local/bin/naivetune-backend
chmod +x /usr/local/bin/naivetune-backend

echo -e "${GREEN}=== 6. Создание служб Systemd ===${NC}"
# Служба для Caddy
cat <<EOF > /etc/systemd/system/caddy.service
[Unit]
Description=Caddy Server with NaiveProxy
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF

# Служба для Бэкенда Naivetune
cat <<EOF > /etc/systemd/system/naivetune.service
[Unit]
Description=Naivetune Panel Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/lib/naivetune
ExecStart=/usr/local/bin/naivetune-backend
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Первичная генерация базового Caddyfile при первой установке
if [ ! -f /etc/caddy/Caddyfile ]; then
    
fi

systemctl daemon-reload
systemctl enable caddy
systemctl enable naivetune

echo -e "${GREEN}=== 7. Настройка брандмауэра UFW ===${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 8080/tcp
    ufw allow 22/tcp   # Чтобы не заблокировать доступ к VPS по SSH
    ufw deny 8000/tcp  # Закрываем порт управления снаружи ради безопасности
    ufw --force enable
fi

# Принудительный старт служб (для WSL и серверов)
echo -e "${GREEN}=== 8. Запуск служб ===${NC}"
systemctl start naivetune || true
systemctl start caddy || true

echo -e "${GREEN}=========================================================${NC}"
echo -e "${GREEN} Скрипт успешно завершил универсальную установку!${NC}"
echo -e "${GREEN} Панель готова к работе как локально, так и на VPS.${NC}"
echo -e "${GREEN}=========================================================${NC}"