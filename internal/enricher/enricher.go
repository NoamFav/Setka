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
