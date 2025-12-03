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
