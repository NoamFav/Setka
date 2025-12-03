package api

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"

	"github.com/NoamFav/netviz/pkg/models"
	"github.com/gorilla/websocket"
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
