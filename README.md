# 🌐 Setka

<div align="center">

<img src="https://img.shields.io/badge/go-1.21+-00ADD8.svg?style=for-the-badge&logo=go" alt="Go">
<img src="https://img.shields.io/badge/license-MIT-green.svg?style=for-the-badge" alt="License">

**Real-time network traffic visualization in the browser**

[Installation](#installation) · [Quick Start](#quick-start) · [Options](#options)

</div>

---

Setka captures live packets and streams them to a web dashboard over WebSocket, giving you a real-time view of TCP/UDP flows, traffic direction, and per-connection stats.

```
Capture → Enricher → Processor → API Server → WebSocket → Browser
```

Built with Go + gopacket + gorilla/websocket.

---

## Quick Start

```bash
# Install dependencies
go mod download

# Run (requires root for packet capture)
sudo go run cmd/netviz/main.go -i en0

# Open browser
open http://localhost:8080
```

---

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `-i` | `any` | Network interface to capture on |
| `-addr` | `localhost:8080` | Server address |

---

## Status

| Feature | State |
|---------|-------|
| Live packet capture (TCP/UDP) | ✅ |
| Flow aggregation | ✅ |
| WebSocket streaming | ✅ |
| Basic web UI with stats | ✅ |
| Direction detection (in/out) | ✅ |
| Process→socket mapping | ⚠️ port-based guess |
| DNS resolution | ⚠️ IPs only |
| GeoIP lookup | ⚠️ not yet |

---

## Roadmap

- Real process→socket mapping (`/proc` or `lsof`)
- MaxMind GeoIP database integration
- D3 force-layout graph visualization
- Per-app filtering
- CSV/JSON export

---

## License

MIT — see [LICENSE](LICENSE).

---

<div align="center">
Made with ❤️ by <a href="https://github.com/NoamFav">NoamFav</a>
</div>
