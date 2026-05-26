#!/bin/bash

# Скрипт полного удаления панели Naivetune из системы
set -e

GREEN='\033[0;32m'
NC='\033[0;0m'

echo -e "${GREEN}=== Останавливаем и отключаем системные службы ===${NC}"
systemctl stop naivetune || true
systemctl disable naivetune || true
systemctl stop caddy || true
systemctl disable caddy || true

echo -e "${GREEN}=== Удаляем конфигурационные файлы служб ===${NC}"
rm -f /etc/systemd/system/naivetune.service
rm -f /etc/systemd/system/caddy.service
systemctl daemon-reload

echo -e "${GREEN}=== Удаляем исполняемые бинарники ===${NC}"
rm -f /usr/local/bin/naivetune-backend
rm -f /usr/local/bin/caddy

echo -e "${GREEN}=== Очищаем созданные директории проекта ===${NC}"
rm -rf /etc/caddy
rm -rf /var/lib/naivetune
rm -rf /var/www/html/*

echo -e "${GREEN}=== Откатываем правила брандмауэра UFW ===${NC}"
if command -v ufw &> /dev/null; then
    ufw delete allow 80/tcp || true
    ufw delete allow 443/tcp || true
    ufw delete allow 8080/tcp || true
    ufw delete deny 8000/tcp || true
fi

echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN} Панель Naivetune полностью удалена из системы! ${NC}"
echo -e "${GREEN}===============================================${NC}"