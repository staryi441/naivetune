package main

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

var (
	AdminUser = ""
	AdminPass = ""
	Port      = "8080" // Бэкенд слушает внутренний порт 8080
	WebPath   = ""
)

const (
	BaseDir  = "/var/lib/naivetune"
	HtmlRoot = "/var/www/html"
)

func main() {
	loadConfig()
	InitDB()

	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	r.RedirectTrailingSlash = true
	r.RedirectFixedPath = true

	// Загружаем HTML-шаблон админки
	r.LoadHTMLFiles(filepath.Join(BaseDir, "templates", "admin.html"))

	// Создаем изолированную админ-группу с Basic Auth
	adminGroup := r.Group(WebPath, gin.BasicAuth(gin.Accounts{
		AdminUser: AdminPass,
	}))

	// Главная страница админки
	adminGroup.GET("/", func(c *gin.Context) {
		c.HTML(http.StatusOK, "admin.html", gin.H{
			"CurrentWebPath": WebPath,
		})
	})

	// !!! ВАЖНО: Переносим API внутрь adminGroup, чтобы пути совпадали и были защищены !!!
	api := adminGroup.Group("/api")
	{
		api.GET("/users", GetUsers)
		api.POST("/users", CreateUser)
		api.DELETE("/users/:id", DeleteUser)

		// Роут получения шаблонов
		api.GET("/templates", func(c *gin.Context) {
			templatesDir := filepath.Join(BaseDir, "templates")
			files, err := os.ReadDir(templatesDir)
			if err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": "Не удалось прочитать папку шаблонов"})
				return
			}

			var templates []string
			for _, f := range files {
				if f.IsDir() {
					templates = append(templates, f.Name())
				}
			}
			c.JSON(http.StatusOK, templates)
		})

		// Роут применения шаблона
		api.POST("/templates/apply", func(c *gin.Context) {
			var req struct {
				TemplateName string `json:"template_name" binding:"required"`
			}
			if err := c.ShouldBindJSON(&req); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Неверный формат запроса"})
				return
			}

			if strings.Contains(req.TemplateName, "..") || strings.Contains(req.TemplateName, "/") {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Недопустимое имя шаблона"})
				return
			}

			srcDir := filepath.Join(BaseDir, "templates", req.TemplateName)
			if _, err := os.Stat(srcDir); os.IsNotExist(err) {
				c.JSON(http.StatusNotFound, gin.H{"error": "Шаблон не найден"})
				return
			}

			_ = os.RemoveAll(HtmlRoot)
			_ = os.MkdirAll(HtmlRoot, 0755)

			if err := copyTemplateDirectory(srcDir, HtmlRoot); err != nil {
				c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Ошибка: %v", err)})
				return
			}

			c.JSON(http.StatusOK, gin.H{"message": "Сайт-заглушка успешно изменен!"})
		})
	}

	// Статика для превью (картинки, стили шаблонов)
	adminGroup.StaticFS("/preview", http.Dir(filepath.Join(BaseDir, "templates")))

	log.Printf("Бэкенд Naivetune запущен локально на порту %s", Port)
	// Слушаем только локальный интерфейс, внешние запросы пойдут через Caddy
	r.Run("127.0.0.1:" + Port)
}

func loadConfig() {
	envPath := "/var/lib/naivetune/.env"
	file, err := os.Open(envPath)
	if err != nil {
		log.Fatalf("Ошибка: файл настроек не найден: %v", err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key, val := parts[0], parts[1]

		switch key {
		case "ADMIN_USER":
			AdminUser = val
		case "ADMIN_PASS":
			AdminPass = val
		case "WEB_BASE_PATH":
			path := val
			if !strings.HasPrefix(path, "/") {
				path = "/" + path
			}
			path = strings.TrimSuffix(path, "/")
			WebPath = path
		}
	}
}

func copyTemplateDirectory(src string, dst string) error {
	return filepath.Walk(src, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)

		if info.IsDir() {
			return os.MkdirAll(target, info.Mode())
		}

		srcFile, err := os.Open(path)
		if err != nil {
			return err
		}
		defer srcFile.Close()

		dstFile, err := os.Create(target)
		if err != nil {
			return err
		}
		defer dstFile.Close()

		_, err = io.Copy(dstFile, srcFile)
		return err
	})
}
