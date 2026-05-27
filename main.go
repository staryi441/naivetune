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

// Глобальные переменные для доступа к настройкам
var (
	AdminUser = ""
	AdminPass = ""
	Port      = "2283" // Порт из твоего инсталлятора
	WebPath   = ""
)

// Системные константы путей для работы внутри WSL/Ubuntu
const (
	BaseDir  = "/var/lib/naivetune"
	HtmlRoot = "/var/www/html"
)

func main() {
	// 1. Загружаем настройки из .env, созданного инсталлятором
	loadConfig()

	// 2. Инициализация базы данных
	InitDB()

	// 3. Настройка Gin
	gin.SetMode(gin.ReleaseMode) // Переводим в релиз, чтобы логи были чистыми
	r := gin.Default()

	// Загружаем HTML-шаблон панели управления админа
	r.LoadHTMLFiles(filepath.Join(BaseDir, "templates", "admin.html"))

	// Создаем изолированную админ-группу на основе секретного WebPath с Basic Auth защитой
	adminGroup := r.Group(WebPath, gin.BasicAuth(gin.Accounts{
		AdminUser: AdminPass,
	}))

	// Роут: Рендеринг главной страницы админки
	adminGroup.GET("/", func(c *gin.Context) {
		c.HTML(http.StatusOK, "admin.html", gin.H{
			"CurrentWebPath": WebPath,
		})
	})

	// Роут API: Получение списка доступных папок-заглушек (blog, landing1 и т.д.)
	adminGroup.GET("/api/templates", func(c *gin.Context) {
		templatesDir := filepath.Join(BaseDir, "templates")
		files, err := os.ReadDir(templatesDir)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Не удалось прочитать папку шаблонов"})
			return
		}

		var templates []string
		for _, f := range files {
			// Выводим только подпапки, игнорируя сам файл admin.html
			if f.IsDir() {
				templates = append(templates, f.Name())
			}
		}
		c.JSON(http.StatusOK, templates)
	})

	// Роут API: Активация выбранного шаблона в качестве заглушки на домене
	adminGroup.POST("/api/templates/apply", func(c *gin.Context) {
		var req struct {
			TemplateName string `json:"template_name" binding:"required"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Неверный формат запроса"})
			return
		}

		// Защита от выхода за пределы директории шаблонов (Path Traversal)
		if strings.Contains(req.TemplateName, "..") || strings.Contains(req.TemplateName, "/") {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Недопустимое имя шаблона"})
			return
		}

		srcDir := filepath.Join(BaseDir, "templates", req.TemplateName)
		if _, err := os.Stat(srcDir); os.IsNotExist(err) {
			c.JSON(http.StatusNotFound, gin.H{"error": "Выбранный шаблон не найден на сервере"})
			return
		}

		// Полностью очищаем директорию старой активной заглушки Caddy
		_ = os.RemoveAll(HtmlRoot)
		_ = os.MkdirAll(HtmlRoot, 0755)

		// Копируем файлы выбранного шаблона в корень веб-сервера (/var/www/html)
		if err := copyTemplateDirectory(srcDir, HtmlRoot); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Ошибка развертывания: %v", err)})
			return
		}

		c.JSON(http.StatusOK, gin.H{"message": "Сайт-заглушка успешно изменен!"})
	})

	// Роут статики: Позволяет iframe внутри админки безопасно подгружать превью стилей и картинок сайтов
	adminGroup.StaticFS("/preview", http.Dir(filepath.Join(BaseDir, "templates")))

	// 4. API маршруты (Твои старые роуты, остались без изменений)
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

// Вспомогательная функция для рекурсивного копирования файлов шаблона
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
