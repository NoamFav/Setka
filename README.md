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
