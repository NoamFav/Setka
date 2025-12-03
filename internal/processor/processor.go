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
