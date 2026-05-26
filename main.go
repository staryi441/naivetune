package main

import (
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

const (
	Domain       = "crayvex.ru"
	Email        = "admin@crayvex.ru"
	WebRoot      = "/var/www/html"
	TemplatesDir = "/var/lib/naivetune/templates"
)

type CreateUserRequest struct {
	Username    string `json:"username" binding:"required"`
	ExpiresDays int    `json:"expires_days"`
}

type ChangeTemplateRequest struct {
	TemplateName string `json:"template_name" binding:"required"`
}

func main() {
	InitDB()

	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	// Создание юзера
	r.POST("/api/users", func(c *gin.Context) {
		var req CreateUserRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		days := req.ExpiresDays
		if days <= 0 {
			days = 30
		}

		newUser := User{
			Username:  req.Username,
			UUID:      uuid.New().String(),
			IsActive:  true,
			ExpiresAt: time.Now().AddDate(0, 0, days),
		}

		if err := DB.Create(&newUser).Error; err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Username already exists"})
			return
		}

		_ = SyncCaddyConfig(Domain, Email)
		c.JSON(http.StatusCreated, newUser)
	})

	// Список юзеров
	r.GET("/api/users", func(c *gin.Context) {
		var users []User
		DB.Find(&users)
		c.JSON(http.StatusOK, users)
	})

	// Удаление юзера
	r.DELETE("/api/users/:id", func(c *gin.Context) {
		id := c.Param("id")
		var user User
		if err := DB.First(&user, id).Error; err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
			return
		}
		DB.Delete(&user)
		_ = SyncCaddyConfig(Domain, Email)
		c.JSON(http.StatusOK, gin.H{"detail": "User deleted"})
	})

	// Выбор шаблона заглушки
	r.POST("/api/system/template", func(c *gin.Context) {
		var req ChangeTemplateRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		srcDir := filepath.Join(TemplatesDir, req.TemplateName)
		if _, err := os.Stat(srcDir); os.IsNotExist(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Template not found"})
			return
		}

		_ = execCmd("rm", "-rf", WebRoot+"/*")
		err := execCmd("cp", "-r", srcDir+"/.", WebRoot)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to apply template"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"detail": fmt.Sprintf("Template '%s' applied", req.TemplateName)})
	})

	// Список доступных шаблонов
	r.GET("/api/system/templates", func(c *gin.Context) {
		files, err := os.ReadDir(TemplatesDir)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Cannot read templates"})
			return
		}

		var list []string
		for _, f := range files {
			if f.IsDir() {
				list = append(list, f.Name())
			}
		}
		c.JSON(http.StatusOK, gin.H{"templates": list})
	})

	fmt.Println("Naivetune Panel listening locally on http://127.0.0.1:8000")
	_ = r.Run("127.0.0.1:8000")
}

func execCmd(name string, arg ...string) error {
	cmd := exec.Command(name, arg...)
	return cmd.Run()
}
