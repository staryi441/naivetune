package main

import (
	"bufio"
	"log"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
)

// Глобальные переменные для доступа к настройкам
var (
	AdminUser = ""
	AdminPass = ""
	Port      = "2283" // Порт из твоего инсталлятора
	WebPath   = ""
)

func main() {
	// 1. Загружаем настройки из .env, созданного инсталлятором
	loadConfig()

	// 2. Инициализация базы данных
	InitDB()

	// 3. Настройка Gin
	r := gin.Default()

	// 4. API маршруты
	api := r.Group("/api")
	{
		api.GET("/users", GetUsers)
		api.POST("/users", CreateUser)
		api.DELETE("/users/:id", DeleteUser)
	}

	// 5. Запуск сервера
	log.Printf("Панель Naivetune запущена. Путь: %s, Порт: %s", WebPath, Port)
	r.Run("127.0.0.1:" + Port)
}

// Функция чтения настроек из файла, созданного install.sh
func loadConfig() {
	envPath := "/var/lib/naivetune/.env"
	file, err := os.Open(envPath)
	if err != nil {
		log.Fatalf("Ошибка: файл настроек не найден. Запустите install.sh. %v", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := parts[0]
		val := parts[1]

		switch key {
		case "ADMIN_USER":
			AdminUser = val
		case "ADMIN_PASS":
			AdminPass = val
		case "WEB_BASE_PATH":
			WebPath = val
		}
	}
	log.Println("Настройки успешно загружены из .env")
}
