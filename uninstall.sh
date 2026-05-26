#!/bin/sh
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт от имени root (через sudo)"
  exit 1
fi

echo "=== 1. Остановка и отключение системных служб ==="
systemctl stop naivetune || true
systemctl disable naivetune || true
systemctl stop caddy || true
systemctl disable caddy || true

echo "=== 2. Удаление конфигураций Systemd ==="
rm -f /etc/systemd/system/naivetune.service
rm -f /etc/systemd/system/caddy.service
systemctl daemon-reload

echo "=== 3. Полная очистка директорий файлов ==="
rm -rf /opt/naivetune
rm -rf /var/lib/naivetune
rm -rf /etc/caddy
rm -rf /var/www/html

echo "=== 4. Удаление исполняемого файла Caddy ==="
rm -f /usr/local/bin/caddy

echo "=== 5. Сброс настроек брандмауэра ==="
# На всякий случай удаляем правила портов веб-сервера
ufw delete allow 80/tcp || true
ufw delete allow 443/tcp || true

echo "========================================================="
echo " Панель Naivetune и Caddy полностью удалены с сервера."
echo " База данных и шаблоны уничтожены."
echo "========================================================="