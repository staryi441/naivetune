package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const (
	CaddyfilePath = "/etc/caddy/Caddyfile"
	TemplatePath  = "/var/lib/naivetune/Caddyfile.template"
)

// Функция вытягивает юзеров из БД, подставляет в шаблон и перезапускает Caddy
func UpdateCaddyConfig(currentHost string) error {
	var users []User
	if err := DB.Find(&users).Error; err != nil {
		return fmt.Errorf("ошибка чтения пользователей из БД: %w", err)
	}

	// Формируем строки вида: auth_user имя uuid
	var authLines []string
	for _, user := range users {
		authLines = append(authLines, fmt.Sprintf("        auth_user %s %s", user.Username, user.UUID))
	}
	authUsersBlock := strings.Join(authLines, "\n")

	// Читаем шаблон Caddyfile.template
	templateContent, err := os.ReadFile(TemplatePath)
	if err != nil {
		return fmt.Errorf("ошибка чтения шаблона Caddyfile: %w", err)
	}

	// Очищаем хост от порта, если он передан (например, localhost:8000 -> localhost)
	host := currentHost
	if strings.Contains(host, ":") {
		host = strings.Split(host, ":")[0]
	}

	// Определяем блок домена: для локалки отключаем TLS, на боевом VPS оставляем чистый домен для авто-SSL
	domainBlock := host
	if host == "localhost" || host == "127.0.0.1" {
		domainBlock = "http://localhost:8080"
	}

	// Подставляем данные в шаблон
	newConfig := strings.ReplaceAll(string(templateContent), "{domain}", domainBlock)
	newConfig = strings.ReplaceAll(newConfig, "{auth_users}", authUsersBlock)

	// Записываем готовый Caddyfile в системную папку
	err = os.WriteFile(CaddyfilePath, []byte(newConfig), 0644)
	if err != nil {
		return fmt.Errorf("ошибка записи системного Caddyfile: %w", err)
	}

	// Мягко перезапускаем службу Caddy без разрыва текущих соединений
	cmd := exec.Command("systemctl", "reload", "caddy")
	if err := cmd.Run(); err != nil {
		// Если reload не сработал (например, служба была выключена), делаем жесткий рестарт
		exec.Command("systemctl", "restart", "caddy").Run()
	}

	return nil
}
