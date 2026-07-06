<div align="center">

<img src="https://capsule-render.vercel.app/api?type=venom&height=220&color=gradient&customColorList=12&text=SETKA&fontSize=100&fontColor=fff&animation=twinkling&desc=Live+Network+Traffic%2C+Straight+to+Your+Browser&descSize=17&descAlignY=65&stroke=FFFFFF&strokeWidth=1" alt="Setka Banner" />

<img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&size=19&pause=1000&color=00D9FF&center=true&vCenter=true&multiline=true&repeat=true&width=900&height=60&lines=Packet+capture+%E2%86%92+flow+aggregation+%E2%86%92+WebSocket+%E2%86%92+browser;Go+%C2%B7+libpcap+%C2%B7+%E2%9A%A0%EF%B8%8F+early+but+functional" alt="Typing SVG" />

<br>

[![Go](https://img.shields.io/badge/Go-00ADD8?style=for-the-badge&logo=go&logoColor=white&labelColor=0D1117)](https://go.dev)
[![libpcap](https://img.shields.io/badge/libpcap-required-6A5ACD?style=for-the-badge&labelColor=0D1117)](https://www.tcpdump.org)
[![Status](https://img.shields.io/badge/Status-Early_but_working-FFA500?style=for-the-badge&labelColor=0D1117)](#status)

</div>

<img src="https://user-images.githubusercontent.com/73097560/115834477-dbab4500-a447-11eb-908a-139a6edaec5c.gif" width="100%">

<div align="center">
  <img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&size=26&pause=1000&color=00D9FF&center=true&width=800&lines=%F0%9F%A4%96+WHAT+IS+SETKA+%3F" alt="What is Setka" />
</div>
<br>

Setka ("network" in Russian, internally still module-named `netviz`) captures live TCP/UDP traffic on an interface, aggregates it into flows, and streams them to a browser over WebSocket in real time. Unlike the other early-stage tools in this account, the full pipeline actually runs end-to-end today.

<img src="https://user-images.githubusercontent.com/73097560/115834477-dbab4500-a447-11eb-908a-139a6edaec5c.gif" width="100%">

<div align="center">
  <img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&size=26&pause=1000&color=FF69B4&center=true&width=800&lines=%F0%9F%93%8A+STATUS%3A+TODAY+VS.+PLANNED+%F0%9F%93%8A" alt="Status" />
</div>
<br>

| Stage | Today | Planned |
|-------|-------|---------|
| **Capture** (`internal/capture`) | ✅ Real libpcap capture, BPF-filtered to TCP/UDP | — |
| **Enrich** (`internal/enricher`) | ⚠️ Direction detection is real; process-name attribution is a hardcoded port lookup (e.g. `443 → "browser"`) | Real process lookup via OS APIs |
| **Process** (`internal/processor`) | ✅ Real flow aggregation, idle-flow cleanup every 60s | — |
| **API** (`internal/api`) | ✅ Real WebSocket broadcast to connected browser clients | REST endpoints alongside the socket |
| **Web UI** | ✅ Minimal static page | DNS reverse resolution, GeoIP, D3.js flow graph |

<img src="https://user-images.githubusercontent.com/73097560/115834477-dbab4500-a447-11eb-908a-139a6edaec5c.gif" width="100%">

<div align="center">
  <img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&size=26&pause=1000&color=6A5ACD&center=true&width=800&lines=%E2%9C%A8+QUICKSTART+%E2%9C%A8" alt="Quickstart" />
</div>
<br>

```sh
# macOS: brew install libpcap   ·   Linux: sudo apt-get install libpcap-dev
git clone https://github.com/NoamFav/Setka && cd Setka
go mod download

sudo go run cmd/netviz/main.go        # requires root for packet capture
sudo go run cmd/netviz/main.go -i en0 # or target a specific interface

# then open http://localhost:8080
```

> [!TIP]
> Run `curl google.com` in another terminal while the server is up — the flow should appear in the web UI within a second.

<img src="https://user-images.githubusercontent.com/73097560/115834477-dbab4500-a447-11eb-908a-139a6edaec5c.gif" width="100%">

<div align="center">

<img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&size=20&pause=1000&color=6A5ACD&center=true&width=800&lines=Thanks+for+stopping+by!" alt="Footer typing" />

<br>

Made with ♥ by [NoamFav](https://github.com/NoamFav)

<img src="https://capsule-render.vercel.app/api?type=waving&height=100&color=gradient&customColorList=12&section=footer" />

</div>
