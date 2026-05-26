package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

const (
	TemplatePath     = "Caddyfile.template"
	CaddyfileOutputs = "/etc/caddy/Caddyfile"
)

func SyncCaddyConfig(domain string, email string) error {
	templateBytes, err := os.ReadFile(TemplatePath)
	if err != nil {
		return fmt.Errorf("error reading template: %v", err)
	}
	templateStr := string(templateBytes)

	var activeUsers []User
	now := time.Now()
	result := DB.Where("is_active = ? AND expires_at > ?", true, now).Find(&activeUsers)
	if result.Error != nil {
		return fmt.Errorf("error fetching active users: %v", result.Error)
	}

	var authLines []string
	for _, user := range activeUsers {
		line := fmt.Sprintf("        auth_user %s %s", user.Username, user.UUID)
		authLines = append(authLines, line)
	}
	authUsersStr := strings.Join(authLines, "\n")

	finalConfig := strings.ReplaceAll(templateStr, "{domain}", domain)
	finalConfig = strings.ReplaceAll(finalConfig, "{email}", email)
	finalConfig = strings.ReplaceAll(finalConfig, "{auth_users}", authUsersStr)

	err = os.WriteFile(CaddyfileOutputs, []byte(finalConfig), 0644)
	if err != nil {
		return fmt.Errorf("error writing Caddyfile: %v", err)
	}

	cmd := exec.Command("caddy", "reload", "--config", CaddyfileOutputs)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("error reloading caddy: %v", err)
	}

	fmt.Println("Caddy successfully reloaded.")
	return nil
}
