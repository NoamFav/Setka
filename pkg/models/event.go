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
