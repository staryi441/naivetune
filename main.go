package main

import (
	"fmt"
	"log"
	"math/rand"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

var (
	// Настройки по умолчанию
	AdminUser = ""
	AdminPass = ""
	Port      = "8000"
)

func main() {
	// 1. Инициализация системы (проверка конфига или создание нового)
	setupInitialConfig()

	// 2. Инициализация базы данных (твоя существующая функция)
	InitDB()

	// 3. Настройка маршрутизатора
	r := gin.Default()

	api := r.Group("/api")
	{
		api.GET("/users", GetUsers)
		api.POST("/users", CreateUser)
		api.DELETE("/users/:id", DeleteUser)
	}

	// 4. Запуск сервера
	log.Printf("Бэкенд запущен на порту :%s", Port)
	r.Run("127.0.0.1:" + Port)
}

func setupInitialConfig() {
	envPath := "/var/lib/naivetune/.env" // Место хранения настроек

	if _, err := os.Stat(envPath); err == nil {
		// Файл есть, читаем из него (код чтения env пропущен для краткости)
		return
	}

	// Генерируем данные
	rand.Seed(time.Now().UnixNano())
	AdminUser = randomString(10)
	AdminPass = randomString(10)
	basePath := "/" + randomString(15) + "/"

	// Сохраняем в файл
	file, _ := os.Create(envPath)
	defer file.Close()
	fmt.Fprintf(file, "ADMIN_USER=%s\nADMIN_PASS=%s\nWEB_BASE_PATH=%s\n", AdminUser, AdminPass, basePath)

	// Вывод сообщения "как на скриншоте"
	fmt.Println("=========================================================")
	fmt.Println("Warning: Panel is not secure with SSL")
	fmt.Printf("username: %s\n", AdminUser)
	fmt.Printf("password: %s\n", AdminPass)
	fmt.Printf("port: %s\n", Port)
	fmt.Printf("webBasePath: %s\n", basePath)
	fmt.Printf("Access URL: http://1.1.1.1:%s%s\n", Port, basePath)
	fmt.Println("=========================================================")
}

func randomString(n int) string {
	const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, n)
	for i := range b {
		b[i] = letters[rand.Intn(len(letters))]
	}
	return string(b)
}
