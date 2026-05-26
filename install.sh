#!/bin/sh
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт от имени root (через sudo)"
  exit 1
fi

echo "=== Проверка операционной системы ==="
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Не удалось определить ОС. Скрипт поддерживает только Debian и Ubuntu."
    exit 1
fi

if [ "$OS" != "ubuntu" ] && [ "$OS" != "debian" ]; then
    echo "Ошибка: Данный скрипт предназначен только для Debian или Ubuntu (обнаружена: $OS)."
    exit 1
fi

echo "=== 1. Установка системных зависимостей ($OS) ==="
apt-get update
apt-get install -y wget curl git ufw tar gzip Coreutils

echo "=== 2. Установка среды Go ==="
if ! command -v go >/dev/null 2>&1; then
    GO_VER="1.21.6"
    wget https://golang.org/dl/go${GO_VER}.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf go${GO_VER}.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
    rm go${GO_VER}.linux-amd64.tar.gz
else
    export PATH=$PATH:/usr/local/go/bin
fi

echo "=== 3. Сборка кастомного Caddy с NaiveProxy ==="
if [ ! -f /usr/local/bin/caddy ]; then
    go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
    ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@master=github.com/klzgrad/forwardproxy@naive
    mv caddy /usr/local/bin/
    chmod +x /usr/local/bin/caddy
fi

echo "=== 4. Подготовка структуры папок ==="
mkdir -p /etc/caddy
mkdir -p /var/www/html
mkdir -p /var/lib/naivetune/templates

# Перенос шаблонов в системную директорию панели
if [ -d "templates" ]; then
    cp -r templates/* /var/lib/naivetune/templates/
fi

# Инициализируем дефолтный сайт, если пусто
if [ ! -f /var/www/html/index.html ] && [ -d "/var/lib/naivetune/templates/landing1" ]; then
    cp -r /var/lib/naivetune/templates/landing1/* /var/www/html/
fi

echo "=== 5. Компиляция бэкенда панели ==="
mkdir -p /opt/naivetune
cp -r ./* /opt/naivetune/
cd /opt/naivetune
go mod tidy
go build -o naivetune-backend .

echo "=== 6. Создание служб Systemd ==="
cat <<EOF > /etc/systemd/system/caddy.service
[Unit]
Description=Caddy Server with NaiveProxy
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/naivetune.service
[Unit]
Description=Naivetune Panel Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/naivetune
ExecStart=/opt/naivetune/naivetune-backend
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable caddy
systemctl enable naivetune

echo "=== 7. Настройка брандмауэра UFW (Порт 8000 закрыт снаружи) ==="
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "========================================================="
echo " Скрипт успешно завершил установку на $OS!"
echo " Внешний порт 8000 заблокирован ради маскировки."
echo " Подключитесь через SSH-туннель для управления:"
echo " ssh -L 8000:127.0.0.1:8000 root@IP_СЕРВЕРА"
echo " После чего откройте: http://localhost:8000"
echo "========================================================="