package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/yourusername/netviz/internal/api"
	"github.com/yourusername/netviz/internal/capture"
	"github.com/yourusername/netviz/internal/enricher"
	"github.com/yourusername/netviz/internal/processor"
)

func main() {
	iface := flag.String("i", "any", "Network interface to capture")
	addr := flag.String("addr", "localhost:8080", "Server address")
	flag.Parse()

	if os.Geteuid() != 0 {
		log.Fatal("❌ Must run as root for packet capture (use sudo)")
	}

	// Build pipeline
	capturer := capture.New(*iface)
	enricher := enricher.New(capturer.Output())
	processor := processor.New(enricher.Output())
	server := api.New(processor.Output())

	// Start components
	go func() {
		if err := capturer.Start(); err != nil {
			log.Fatalf("Capture failed: %v", err)
		}
	}()
	go enricher.Start()
	processor.Start()

	// Graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigChan
		log.Println("\n👋 Shutting down...")
		os.Exit(0)
	}()

	// Start server (blocks)
	log.Fatal(server.Start(*addr))
}
