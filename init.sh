#!/bin/bash
set -e

PROJECT_NAME="netviz"
echo "🚀 Creating NetViz project structure..."

# Create root directory
mkdir -p $PROJECT_NAME
cd $PROJECT_NAME

# Create Go module
cat >go.mod <<'EOF'
module github.com/yourusername/netviz

go 1.21

require (
	github.com/google/gopacket v1.1.19
	github.com/gorilla/websocket v1.5.1
)
EOF

# Create directory structure
mkdir -p cmd/netviz
mkdir -p internal/{capture,enricher,processor,api}
mkdir -p web/{src,public}
mkdir -p pkg/models

# ============================================
# MODELS
# ============================================
cat >pkg/models/event.go <<'EOF'
package models

import (
	"net"
	"time"
)

type RawPacket struct {
	Timestamp time.Time
	SrcIP     net.IP
	DstIP     net.IP
	SrcPort   uint16
	DstPort   uint16
	Protocol  string
	Bytes     uint32
}

type NetworkEvent struct {
	RawPacket
	ProcessName string
	Direction   string // "inbound" | "outbound"
}

type Flow struct {
	ID          string    `json:"id"`
	LocalIP     string    `json:"local_ip"`
	RemoteIP    string    `json:"remote_ip"`
	RemotePort  uint16    `json:"remote_port"`
	Protocol    string    `json:"protocol"`
	ProcessName string    `json:"process_name"`
	Direction   string    `json:"direction"`
	BytesSent   uint64    `json:"bytes_sent"`
	BytesRecv   uint64    `json:"bytes_recv"`
	PacketCount uint32    `json:"packet_count"`
	FirstSeen   time.Time `json:"first_seen"`
	LastSeen    time.Time `json:"last_seen"`
}
EOF

# ============================================
# CAPTURE LAYER
# ============================================
cat >internal/capture/capture.go <<'EOF'
package capture

import (
	"fmt"
	"log"
	"net"
	"time"

	"github.com/google/gopacket"
	"github.com/google/gopacket/layers"
	"github.com/google/gopacket/pcap"
	"github.com/yourusername/netviz/pkg/models"
)

type Capturer struct {
	iface  string
	output chan models.RawPacket
}

func New(iface string) *Capturer {
	return &Capturer{
		iface:  iface,
		output: make(chan models.RawPacket, 1000),
	}
}

func (c *Capturer) Start() error {
	handle, err := pcap.OpenLive(c.iface, 1600, true, pcap.BlockForever)
	if err != nil {
		return fmt.Errorf("pcap open: %w", err)
	}
	defer handle.Close()

	// Filter for TCP and UDP only
	if err := handle.SetBPFFilter("tcp or udp"); err != nil {
		return fmt.Errorf("set filter: %w", err)
	}

	log.Printf("📡 Capturing on interface: %s", c.iface)

	packetSource := gopacket.NewPacketSource(handle, handle.LinkType())
	for packet := range packetSource.Packets() {
		c.processPacket(packet)
	}

	return nil
}

func (c *Capturer) processPacket(packet gopacket.Packet) {
	var srcIP, dstIP net.IP
	var srcPort, dstPort uint16
	var protocol string

	// Network layer
	if ipLayer := packet.Layer(layers.LayerTypeIPv4); ipLayer != nil {
		ip := ipLayer.(*layers.IPv4)
		srcIP = ip.SrcIP
		dstIP = ip.DstIP
	} else if ipLayer := packet.Layer(layers.LayerTypeIPv6); ipLayer != nil {
		ip := ipLayer.(*layers.IPv6)
		srcIP = ip.SrcIP
		dstIP = ip.DstIP
	} else {
		return
	}

	// Transport layer
	if tcpLayer := packet.Layer(layers.LayerTypeTCP); tcpLayer != nil {
		tcp := tcpLayer.(*layers.TCP)
		srcPort = uint16(tcp.SrcPort)
		dstPort = uint16(tcp.DstPort)
		protocol = "TCP"
	} else if udpLayer := packet.Layer(layers.LayerTypeUDP); udpLayer != nil {
		udp := udpLayer.(*layers.UDP)
		srcPort = uint16(udp.SrcPort)
		dstPort = uint16(udp.DstPort)
		protocol = "UDP"
	} else {
		return
	}

	raw := models.RawPacket{
		Timestamp: time.Now(),
		SrcIP:     srcIP,
		DstIP:     dstIP,
		SrcPort:   srcPort,
		DstPort:   dstPort,
		Protocol:  protocol,
		Bytes:     uint32(len(packet.Data())),
	}

	select {
	case c.output <- raw:
	default:
		// Drop packet if buffer full
	}
}

func (c *Capturer) Output() <-chan models.RawPacket {
	return c.output
}
EOF

# ============================================
# ENRICHER
# ============================================
cat >internal/enricher/enricher.go <<'EOF'
package enricher

import (
	"net"

	"github.com/yourusername/netviz/pkg/models"
)

type Enricher struct {
	localIP net.IP
	input   <-chan models.RawPacket
	output  chan models.NetworkEvent
}

func New(input <-chan models.RawPacket) *Enricher {
	return &Enricher{
		localIP: getLocalIP(),
		input:   input,
		output:  make(chan models.NetworkEvent, 1000),
	}
}

func (e *Enricher) Start() {
	for raw := range e.input {
		event := models.NetworkEvent{
			RawPacket:   raw,
			ProcessName: e.guessProcess(raw.DstPort),
			Direction:   e.getDirection(raw.SrcIP, raw.DstIP),
		}

		select {
		case e.output <- event:
		default:
		}
	}
}

func (e *Enricher) getDirection(srcIP, dstIP net.IP) string {
	if isLocalIP(srcIP) {
		return "outbound"
	}
	return "inbound"
}

func (e *Enricher) guessProcess(port uint16) string {
	// Mock: guess based on common ports
	portMap := map[uint16]string{
		80:   "browser",
		443:  "browser",
		22:   "ssh",
		3000: "dev-server",
	}
	if name, ok := portMap[port]; ok {
		return name
	}
	return "unknown"
}

func (e *Enricher) Output() <-chan models.NetworkEvent {
	return e.output
}

func getLocalIP() net.IP {
	// Simple heuristic: first non-loopback interface
	addrs, _ := net.InterfaceAddrs()
	for _, addr := range addrs {
		if ipnet, ok := addr.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			if ipnet.IP.To4() != nil {
				return ipnet.IP
			}
		}
	}
	return net.IPv4(127, 0, 0, 1)
}

func isLocalIP(ip net.IP) bool {
	return ip.IsLoopback() || ip.IsPrivate()
}
EOF

# ============================================
# PROCESSOR
# ============================================
cat >internal/processor/processor.go <<'EOF'
package processor

import (
	"crypto/sha256"
	"fmt"
	"sync"
	"time"

	"github.com/yourusername/netviz/pkg/models"
)

type Processor struct {
	input  <-chan models.NetworkEvent
	flows  map[string]*models.Flow
	mu     sync.RWMutex
	output chan []models.Flow
}

func New(input <-chan models.NetworkEvent) *Processor {
	return &Processor{
		input:  input,
		flows:  make(map[string]*models.Flow),
		output: make(chan []models.Flow, 10),
	}
}

func (p *Processor) Start() {
	go p.aggregate()
	go p.broadcast()
}

func (p *Processor) aggregate() {
	for event := range p.input {
		flowID := p.makeFlowID(event)

		p.mu.Lock()
		flow, exists := p.flows[flowID]
		if !exists {
			flow = &models.Flow{
				ID:          flowID,
				LocalIP:     getLocalIP(event),
				RemoteIP:    getRemoteIP(event),
				RemotePort:  getRemotePort(event),
				Protocol:    event.Protocol,
				ProcessName: event.ProcessName,
				Direction:   event.Direction,
				FirstSeen:   event.Timestamp,
			}
			p.flows[flowID] = flow
		}

		// Update aggregates
		flow.LastSeen = event.Timestamp
		flow.PacketCount++
		if event.Direction == "outbound" {
			flow.BytesSent += uint64(event.Bytes)
		} else {
			flow.BytesRecv += uint64(event.Bytes)
		}
		p.mu.Unlock()
	}
}

func (p *Processor) broadcast() {
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		p.mu.RLock()
		snapshot := make([]models.Flow, 0, len(p.flows))
		for _, flow := range p.flows {
			snapshot = append(snapshot, *flow)
		}
		p.mu.RUnlock()

		select {
		case p.output <- snapshot:
		default:
		}

		// Cleanup old flows (>60s idle)
		p.cleanup()
	}
}

func (p *Processor) cleanup() {
	p.mu.Lock()
	defer p.mu.Unlock()

	cutoff := time.Now().Add(-60 * time.Second)
	for id, flow := range p.flows {
		if flow.LastSeen.Before(cutoff) {
			delete(p.flows, id)
		}
	}
}

func (p *Processor) makeFlowID(e models.NetworkEvent) string {
	key := fmt.Sprintf("%s:%d-%s:%d-%s",
		e.SrcIP, e.SrcPort, e.DstIP, e.DstPort, e.Protocol)
	hash := sha256.Sum256([]byte(key))
	return fmt.Sprintf("%x", hash[:8])
}

func (p *Processor) Output() <-chan []models.Flow {
	return p.output
}

func getLocalIP(e models.NetworkEvent) string {
	if e.Direction == "outbound" {
		return e.SrcIP.String()
	}
	return e.DstIP.String()
}

func getRemoteIP(e models.NetworkEvent) string {
	if e.Direction == "outbound" {
		return e.DstIP.String()
	}
	return e.SrcIP.String()
}

func getRemotePort(e models.NetworkEvent) uint16 {
	if e.Direction == "outbound" {
		return e.DstPort
	}
	return e.SrcPort
}
EOF

# ============================================
# API SERVER
# ============================================
cat >internal/api/server.go <<'EOF'
package api

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
	"github.com/yourusername/netviz/pkg/models"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type Server struct {
	input   <-chan []models.Flow
	clients map[*websocket.Conn]bool
	mu      sync.RWMutex
}

func New(input <-chan []models.Flow) *Server {
	return &Server{
		input:   input,
		clients: make(map[*websocket.Conn]bool),
	}
}

func (s *Server) Start(addr string) error {
	http.HandleFunc("/ws", s.handleWebSocket)
	http.Handle("/", http.FileServer(http.Dir("./web/public")))

	go s.broadcast()

	log.Printf("🌐 Server running on http://%s", addr)
	return http.ListenAndServe(addr, nil)
}

func (s *Server) handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade failed: %v", err)
		return
	}

	s.mu.Lock()
	s.clients[conn] = true
	s.mu.Unlock()

	log.Printf("✅ Client connected (total: %d)", len(s.clients))

	// Keep connection alive
	defer func() {
		s.mu.Lock()
		delete(s.clients, conn)
		s.mu.Unlock()
		conn.Close()
		log.Printf("❌ Client disconnected (total: %d)", len(s.clients))
	}()

	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			break
		}
	}
}

func (s *Server) broadcast() {
	for flows := range s.input {
		data, err := json.Marshal(flows)
		if err != nil {
			log.Printf("JSON marshal error: %v", err)
			continue
		}

		s.mu.RLock()
		for client := range s.clients {
			if err := client.WriteMessage(websocket.TextMessage, data); err != nil {
				log.Printf("Write error: %v", err)
			}
		}
		s.mu.RUnlock()
	}
}
EOF

# ============================================
# MAIN
# ============================================
cat >cmd/netviz/main.go <<'EOF'
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
EOF

# ============================================
# FRONTEND
# ============================================
cat >web/public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NetViz - Network Traffic Monitor</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: #0a0e27;
            color: #e0e0e0;
            padding: 20px;
        }
        h1 {
            font-size: 2em;
            margin-bottom: 10px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .status {
            padding: 10px;
            border-radius: 8px;
            margin-bottom: 20px;
            font-size: 0.9em;
        }
        .status.connected { background: #1a472a; color: #4ade80; }
        .status.disconnected { background: #4a1a1a; color: #f87171; }

        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: #1a1f3a;
            padding: 20px;
            border-radius: 12px;
            border: 1px solid #2a2f4a;
        }
        .stat-card h3 { font-size: 0.85em; color: #888; margin-bottom: 8px; }
        .stat-card .value { font-size: 2em; font-weight: bold; color: #667eea; }

        table {
            width: 100%;
            background: #1a1f3a;
            border-radius: 12px;
            overflow: hidden;
            border-collapse: collapse;
        }
        th {
            background: #2a2f4a;
            padding: 15px;
            text-align: left;
            font-weight: 600;
            font-size: 0.9em;
            color: #a0a0a0;
        }
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #2a2f4a;
        }
        tr:hover { background: #252a45; }

        .direction {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 0.75em;
            font-weight: 600;
        }
        .direction.outbound { background: #1e3a5f; color: #60a5fa; }
        .direction.inbound { background: #3a1e5f; color: #c084fc; }

        .bytes { color: #4ade80; font-weight: 500; }
        .protocol {
            font-family: 'Courier New', monospace;
            background: #2a2f4a;
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.85em;
        }
    </style>
</head>
<body>
    <h1>⚡ NetViz</h1>
    <div id="status" class="status disconnected">🔴 Connecting...</div>

    <div class="stats">
        <div class="stat-card">
            <h3>ACTIVE FLOWS</h3>
            <div class="value" id="flowCount">0</div>
        </div>
        <div class="stat-card">
            <h3>TOTAL SENT</h3>
            <div class="value" id="totalSent">0 KB</div>
        </div>
        <div class="stat-card">
            <h3>TOTAL RECEIVED</h3>
            <div class="value" id="totalRecv">0 KB</div>
        </div>
    </div>

    <table>
        <thead>
            <tr>
                <th>Process</th>
                <th>Remote IP</th>
                <th>Port</th>
                <th>Protocol</th>
                <th>Direction</th>
                <th>Sent</th>
                <th>Received</th>
                <th>Packets</th>
            </tr>
        </thead>
        <tbody id="flowTable"></tbody>
    </table>

    <script>
        const ws = new WebSocket('ws://localhost:8080/ws');
        const statusEl = document.getElementById('status');
        const flowTableEl = document.getElementById('flowTable');
        const flowCountEl = document.getElementById('flowCount');
        const totalSentEl = document.getElementById('totalSent');
        const totalRecvEl = document.getElementById('totalRecv');

        ws.onopen = () => {
            statusEl.textContent = '🟢 Connected';
            statusEl.className = 'status connected';
        };

        ws.onclose = () => {
            statusEl.textContent = '🔴 Disconnected';
            statusEl.className = 'status disconnected';
        };

        ws.onmessage = (event) => {
            const flows = JSON.parse(event.data);
            renderFlows(flows);
        };

        function renderFlows(flows) {
            flowCountEl.textContent = flows.length;

            let totalSent = 0, totalRecv = 0;

            const rows = flows
                .sort((a, b) => (b.bytes_sent + b.bytes_recv) - (a.bytes_sent + a.bytes_recv))
                .map(flow => {
                    totalSent += flow.bytes_sent;
                    totalRecv += flow.bytes_recv;

                    return `
                        <tr>
                            <td><strong>${flow.process_name}</strong></td>
                            <td><code>${flow.remote_ip}</code></td>
                            <td>${flow.remote_port}</td>
                            <td><span class="protocol">${flow.protocol}</span></td>
                            <td><span class="direction ${flow.direction}">${flow.direction}</span></td>
                            <td class="bytes">${formatBytes(flow.bytes_sent)}</td>
                            <td class="bytes">${formatBytes(flow.bytes_recv)}</td>
                            <td>${flow.packet_count}</td>
                        </tr>
                    `;
                }).join('');

            flowTableEl.innerHTML = rows || '<tr><td colspan="8" style="text-align:center;color:#666;">No active flows</td></tr>';
            totalSentEl.textContent = formatBytes(totalSent);
            totalRecvEl.textContent = formatBytes(totalRecv);
        }

        function formatBytes(bytes) {
            if (bytes < 1024) return bytes + ' B';
            if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
            return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
        }
    </script>
</body>
</html>
EOF

# ============================================
# README
# ============================================
cat >README.md <<'EOF'
# NetViz v0.1

Real-time network traffic visualization tool.

## Quick Start

```bash
# Install dependencies
go mod download

# Run (requires root for packet capture)
sudo go run cmd/netviz/main.go -i en0

# Open browser
open http://localhost:8080
```

## Options

- `-i` - Network interface (default: "any")
- `-addr` - Server address (default: "localhost:8080")

## What's Working

✅ Live packet capture (TCP/UDP)
✅ Flow aggregation
✅ WebSocket streaming
✅ Basic web UI with stats
✅ Direction detection (in/out)

## What's Mocked

⚠️ Process name lookup (port-based guess)
⚠️ DNS resolution (shows IPs)
⚠️ GeoIP lookup

## Next Steps

- Add real process→socket mapping (/proc or lsof)
- Integrate MaxMind GeoIP database
- Add graph visualization (D3 force layout)
- Per-app filtering
- Export to CSV/JSON

## Architecture

```
Capture → Enricher → Processor → API Server → WebSocket → Browser
```

Built with Go + gopacket + gorilla/websocket.
EOF

# ============================================
# MAKEFILE
# ============================================
cat >Makefile <<'EOF'
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
EOF

# ============================================
# GITIGNORE
# ============================================
cat >.gitignore <<'EOF'
bin/
*.log
.DS_Store
EOF

# ============================================
# Final instructions
# ============================================
cat >INSTRUCTIONS.txt <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║                   NETVIZ SETUP COMPLETE                      ║
╚══════════════════════════════════════════════════════════════╝

📦 Project structure created successfully!

🚀 TO RUN:

  1. Install libpcap (if not already installed):

     macOS:   brew install libpcap
     Linux:   sudo apt-get install libpcap-dev

  2. Download dependencies:

     go mod download

  3. Run NetViz (requires sudo for packet capture):

     sudo go run cmd/netviz/main.go

     Or specify interface:
     sudo go run cmd/netviz/main.go -i en0

  4. Open browser:

     http://localhost:8080

🔍 WHAT YOU'LL SEE:

  - Real-time list of network flows
  - Process names (mocked for now)
  - Bytes sent/received per flow
  - Inbound/outbound direction
  - Active connection count

💡 QUICK TEST:

  Open a new terminal and run:

  curl google.com

  You should see it appear in the web UI!

📝 FILES CREATED:

  cmd/netviz/main.go          - Entry point
  internal/capture/           - Packet capture layer
  internal/enricher/          - Metadata enrichment
  internal/processor/         - Flow aggregation
  internal/api/               - WebSocket server
  pkg/models/                 - Data structures
  web/public/index.html       - Frontend UI

🎯 NEXT IMPROVEMENTS:

  1. Replace mocked process names with real lookups
  2. Add DNS reverse resolution
  3. Integrate GeoIP database
  4. Add D3.js graph visualization
  5. Add filtering by process/domain

═══════════════════════════════════════════════════════════════

Run into issues? Check:
- Are you running with sudo?
- Is libpcap installed?
- Is port 8080 available?
- Try a specific interface: -i en0 (Mac) or -i eth0 (Linux)

Happy hacking! 🎉
EOF

echo ""
echo "✅ Project created successfully!"
echo ""
cat INSTRUCTIONS.txt

chmod +x Makefile

echo ""
echo "📁 Project location: $(pwd)"
echo ""

EOF
