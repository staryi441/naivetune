package main

import (
	"time"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

var DB *gorm.DB

type User struct {
	ID        uint           `gorm:"primaryKey" json:"id"`
	Username  string         `gorm:"uniqueIndex" json:"username"`
	UUID      string         `gorm:"uniqueIndex" json:"uuid"`
	IsActive  bool           `gorm:"default:true" json:"is_active"`
	ExpiresAt time.Time      `json:"expires_at"`
	CreatedAt time.Time      `json:"created_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func InitDB() {
	var err error
	DB, err = gorm.Open(sqlite.Open("naivetune.db"), &gorm.Config{})
	if err != nil {
		panic("Failed to connect to database: " + err.Error())
	}

	err = DB.AutoMigrate(&User{})
	if err != nil {
		panic("Failed to migrate database: " + err.Error())
	}
}
