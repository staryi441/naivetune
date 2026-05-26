package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
)

// Получаем настройки из переменных окружения или ставим дефолт для VPS
var (
	WebRoot      = getEnv("NAIVETUNE_WEBROOT", "/var/www/html")
	TemplatesDir = getEnv("NAIVETUNE_TEMPLATES", "/var/lib/naivetune/templates")
)

func main() {
	// Инициализация базы данных SQLite
	InitDB()

	// Настройка маршрутизатора Gin
	r := gin.Default()

	// API Маршруты
	api := r.Group("/api")
	{
		api.GET("/users", GetUsers)
		api.POST("/users", CreateUser)
		api.DELETE("/users/:id", DeleteUser)
	}

	// Порт панели (обычно 8000, закрыт снаружи брандмауэром)
	port := getEnv("NAIVETUNE_PORT", "8000")

	log.Printf("Бэкенд панели Naivetune запущен на порту :%s", port)
	if err := r.Run("127.0.0.1:" + port); err != nil {
		log.Fatalf("Не удалось запустить сервер: %v", err)
	}
}

// Вспомогательная функция для чтения переменных окружения
func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}
