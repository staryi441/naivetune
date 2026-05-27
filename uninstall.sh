#!/bin/bash

# Проверяем, запущен ли скрипт через source/точку. 
# Если запущен неправильно, предупреждаем пользователя, но даем продолжить.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "\033[0;33mПримечание: Чтобы после удаления терминал автоматически перешел в папку projects,\033[0m"
    echo -e "\033[0;33mрекомендуется запускать скрипт так: source ./uninstall.sh\033[0m"
    echo "---------------------------------------------------------"
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Ошибка: Для удаления служб необходимы права sudo!${NC}"
    echo -e "Запустите: ${GREEN}sudo -E bash uninstall.sh${NC} (если обычно) или ${GREEN}sudo -E bash -c \"source ./uninstall.sh\"${NC}"
    exit 1
fi

echo -e "${RED}=== Запуск полного удаления Naivetune ===${NC}"

# 1. Останавливаем и удаляем системные службы systemd
echo -e "${GREEN}--- Остановка и удаление служб systemd ---${NC}"
systemctl stop caddy naivetune 2>/dev/null || true
systemctl disable caddy naivetune 2>/dev/null || true

rm -f /etc/systemd/system/caddy.service
rm -f /etc/systemd/system/naivetune.service
systemctl daemon-reload

# 2. Удаляем бинарники и утилиты управления
echo -e "${GREEN}--- Удаление исполняемых файлов ---${NC}"
rm -f /usr/local/bin/caddy
rm -f /usr/local/bin/naivetune-backend
rm -f /usr/local/bin/naivetune

# 3. Удаляем системные конфигурации и файлы данных
echo -e "${GREEN}--- Удаление конфигураций и баз данных (/var) ---${NC}"
rm -rf /etc/caddy
rm -rf /var/lib/naivetune
rm -rf /var/www/html

# 4. Удаляем автозапуск панели из .bashrc
echo -e "${GREEN}--- Очистка автозапуска терминала ---${NC}"
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER")
else
    USER_HOME=$HOME
fi

if [ -f "$USER_HOME/.bashrc" ]; then
    # Удаляем строчку вызова naivetune, если она там есть
    sed -i '/\/usr\/local\/bin\/naivetune/d' "$USER_HOME/.bashrc"
    sed -i '/^naivetune$/d' "$USER_HOME/.bashrc"
fi

echo -e "${RED}=== Системные компоненты Naivetune успешно удалены! ===${NC}"
echo "---------------------------------------------------------"

# 5. ХИТРОСТЬ: Выкидываем пользователя в папку projects
# Проверяем, находимся ли мы в структуре папок пользователя
CURRENT_DIR=$(pwd)
if [[ "$CURRENT_DIR" == *"/projects/naivetune"* ]]; then
    TARGET_DIR=$(echo "$CURRENT_DIR" | sed 's/\/naivetune.*//')
    echo -e "${GREEN}Перемещаем терминал в рабочую директорию: $TARGET_DIR${NC}"
    cd "$TARGET_DIR"
else
    # Если папка называется иначе, просто выходим на один уровень вверх
    echo -e "${GREEN}Выходим на уровень выше...${NC}"
    cd ..
fi

echo -e "${GREEN}Готово! Теперь вы можете безопасно удалить саму папку исходников командой: rm -rf naivetune${NC}"