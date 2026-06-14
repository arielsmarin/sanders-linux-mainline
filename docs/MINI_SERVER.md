# Mini-servidor web + storage (sanders)

Estado: **✅ no ar** — `nginx` servindo uma **dashboard de status do sistema** +
um backend HTTP; storage (`filebrowser`) instalado, config pendente.

Este documento descreve o **mini-servidor em si** (genérico). A camada de
**exposição pública** deste deployment específico (domínio próprio + HTTPS de
fora sob CGNAT) está em
[`PIPELINE_STRATYCONFIG_CGNAT.md`](PIPELINE_STRATYCONFIG_CGNAT.md).

Device: Motorola XT1802 (`sanders`, MSM8953) · Arch Linux ARM aarch64 ·
2.7 GB RAM · 8 cores · ~21 GB livres em `/`.

---

## Arquitetura (local)

```
[ exposição pública — Cloudflare Tunnel — ver PIPELINE_STRATYCONFIG_CGNAT.md ]
        │  HTTP
        ▼
nginx :80
   ├─ /            → /srv/www/sanders/index.html (dashboard de status)
   └─ /api/         → reverse_proxy 127.0.0.1:3000 (backend)
        ├─ /api/status → métricas do sistema (JSON)
        └─ /api/...    → health / echo
```

Decisão de desenho: **um único servidor HTTP local (nginx)**. O `caddy` fica
instalado, porém ocioso — empilhar nginx + caddy seria redundante (ambos servem
estático + reverse_proxy).

---

## Componentes instalados

| Pacote | Versão | Origem | Papel |
|---|---|---|---|
| `nginx` | 1.30.2 | pacman (`extra`) | web server + reverse_proxy |
| `cloudflared` | 2026.6.0 | pacman | exposição pública (ver pipeline doc) |
| `filebrowser` | 2.63.15 | binário arm64 (GitHub) | UI web de storage (config pendente) |
| `caddy` | 2.11.4 | pacman (`extra`) | instalado, **ocioso** (alternativa) |
| `python` | 3.14 | pacman | runtime do backend / `/api/status` |

---

## Serviços (systemd) — `enabled` (sobrevivem a reboot)

| Unit | Função |
|---|---|
| `nginx.service` | serve a dashboard + reverse_proxy pro backend |
| `sanders-demo-backend.service` | backend HTTP em `127.0.0.1:3000` (`DynamicUser`) |
| `cloudflared.service` | túnel de exposição pública (config no pipeline doc) |

---

## Arquivos no device

```
/etc/nginx/nginx.conf                       # reescrito (original em .orig)
/srv/www/sanders/index.html                 # dashboard de status (auto-refresh)
/usr/local/bin/sanders-demo-backend.py      # backend (stdlib http.server)
/etc/systemd/system/sanders-demo-backend.service
```

### nginx.conf (essência)

```nginx
server {
    listen 80 default_server;
    server_name _;
    root  /srv/www/sanders;
    index index.html;

    location / { try_files $uri $uri/ =404; }

    location = /api  { return 302 /api/; }
    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## Dashboard de status + `/api/status`

O `index.html` é uma dashboard (auto-refresh a cada 3 s) que consome o endpoint
`/api/status` do backend. Útil porque o device é **headless** (sem display) — a
página é o "monitor".

`/api/status` (JSON, sem dependências — lê `/proc` e `/sys`) reporta:

| Campo | Fonte |
|---|---|
| CPU % (amostra de `/proc/stat`), nº de cores, load 1/5/15m | `/proc/stat`, `/proc/loadavg` |
| Temp CPU/GPU | `/sys/class/thermal/*` |
| Memória (usada/disp/total, swap) | `/proc/meminfo` |
| Armazenamento (`/`) | `statvfs` |
| Processos (total + running) | `/proc/[pid]/stat` |
| Wi-Fi (SSID, sinal dBm, qualidade, bitrate, IP) | `iw dev wlan0 link` |
| Internet (online + latência) | TCP a `1.1.1.1:443` |
| Bateria | `/sys/class/power_supply` → **indisponível** (sem driver de fuel-gauge no mainline) |

Observações de hardware (mainline msm8953): **bateria** (capacidade/charging) e
**frequência de CPU** (`cpufreq`) não são expostas pelo kernel atual; aparecem
como indisponíveis na dashboard.

---

## Verificação (local, no device)

```sh
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/      # 200 (dashboard)
curl -s http://127.0.0.1/api/status                              # JSON de métricas
curl -s http://127.0.0.1/api/                                    # health/echo
```

---

## Trocar pelo conteúdo real

- **Página/site:** substituir `/srv/www/sanders/index.html` (ou apontar `root`
  do nginx para outro diretório).
- **Backend real:** parar/desabilitar `sanders-demo-backend.service` e apontar o
  `proxy_pass` do nginx para a porta do seu serviço (Node/Python/Go/etc).

---

## 🔜 Pendente — storage (filebrowser)

`filebrowser` (v2.63.15) já está em `/usr/local/bin/filebrowser`. Falta: definir
o diretório de dados (storage), criar usuário admin, criar a unit systemd e
expor atrás do nginx (num path `/files/` ou hostname próprio).

---

## Notas / armadilhas resolvidas no bring-up

- **Egress IPv4 "blackholed"**: o `10-usb0.network` definia `Gateway=` + rota
  default; com o `usb0` em `linkdown`, o kernel (que **não** ignora rota linkdown
  por padrão) jogava toda a saída no buraco. Removidos `Gateway`/`[Route]` do
  `usb0` (rede de serviço, só `Address`) → default só via `wlan0`. Sem isso o
  `pacman` nem baixava.
- **Posse do rootfs**: `/`, `/etc`, `/usr` vinham `owned by alarm` (artefato do
  build) e quebravam hooks pós-install do pacman; corrigido para `root:root`.
- Veja também `TROUBLESHOOTING.md`.
