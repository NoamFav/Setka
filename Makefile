.PHONY: run build clean deps

deps:
	go mod download

run:
	@echo "⚠️  Remember to run with sudo for packet capture"
	sudo go run cmd/netviz/main.go

build:
	go build -o bin/netviz cmd/netviz/main.go

clean:
	rm -rf bin/

install-deps-mac:
	brew install libpcap

install-deps-linux:
	sudo apt-get install libpcap-dev
