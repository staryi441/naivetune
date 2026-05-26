package main

import (
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

// Модель пользователя в БД
type User struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Username  string    `gorm:"unique;not null" json:"username"`
	UUID      string    `gorm:"unique;not null" json:"uuid"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
}

var DB *gorm.DB

// Инициализация SQLite базы данных
func InitDB() {
	var err error
	DB, err = gorm.Open(sqlite.Open("naivetune.db"), &gorm.Config{})
	if err != nil {
		log.Fatalf("Ошибка подключения к БД: %v", err)
	}

	// Автоматическое создание таблиц
	err = DB.AutoMigrate(&User{})
	if err != nil {
		log.Fatalf("Ошибка миграции БД: %v", err)
	}
}

// Получение списка всех пользователей
func GetUsers(c *gin.Context) {
	var users []User
	if err := DB.Find(&users).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Не удалось получить пользователей"})
		return
	}
	c.JSON(http.StatusOK, users)
}

// Создание нового пользователя
func CreateUser(c *gin.Context) {
	var input struct {
		Username    string `json:"username" binding:"required"`
		ExpiresDays int    `json:"expires_days" binding:"required"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Генерация уникального UUID для NaiveProxy
	newUUID := uuid.New().String()
	expireTime := time.Now().AddDate(0, 0, input.ExpiresDays)

	user := User{
		Username:  input.Username,
		UUID:      newUUID,
		ExpiresAt: expireTime,
	}

	if err := DB.Create(&user).Error; err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "Пользователь уже существует или данные некорректны"})
		return
	}

	// Передаем текущий хост запроса, чтобы Caddyfile сгенерировался под нужный домен или localhost автоматически
	if err := UpdateCaddyConfig(c.Request.Host); err != nil {
		log.Printf("Ошибка обновления Caddyfile: %v", err)
	}

	c.JSON(http.StatusCreated, user)
}

// Удаление пользователя
func DeleteUser(c *gin.Context) {
	id := c.Param("id")
	var user User

	if err := DB.First(&user, id).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Пользователь не найден"})
		return
	}

	if err := DB.Delete(&user).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Не удалось удалить пользователя"})
		return
	}

	// Перегенерация Caddyfile после удаления пользователя
	if err := UpdateCaddyConfig(c.Request.Host); err != nil {
		log.Printf("Ошибка обновления Caddyfile: %v", err)
	}

	c.JSON(http.StatusOK, gin.H{"message": "Пользователь успешно удален"})
}
