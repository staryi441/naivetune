#!/bin/bash
# Скрипт полного удаления NaiveTune

if [ "$EUID" -ne 0 ]; then echo "Запустите через sudo!"; exit 1; fi

echo "=== Начало процесса удаления NaiveTune ==="

# 1. Остановка и удаление сервисов
echo "Остановка сервисов..."
systemctl stop caddy naivetune 2>/dev/null || true
systemctl disable caddy naivetune 2>/dev/null || true
rm -f /etc/systemd/system/caddy.service
rm -f /etc/systemd/system/naivetune.service
systemctl daemon-reload

# 2. Удаление бинарников и команды naivetune
echo "Удаление файлов..."
rm -f /usr/local/bin/caddy
rm -f /usr/local/bin/naivetune-backend
rm -f /usr/local/bin/naivetune

# 3. Удаление рабочих директорий
rm -rf /var/lib/naivetune
rm -rf /etc/caddy
rm -rf naivetune

# 4. Удаление автозапуска из .bashrc (ищем и удаляем строку с командой)
# Берем для текущего пользователя, если нужно для других - добавить цикл по /home
if [ -f ~/.bashrc ]; then
    sed -i '/naivetune$/d' ~/.bashrc
fi

echo "=== Удаление завершено успешно! ==="