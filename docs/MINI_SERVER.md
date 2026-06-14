# Mini-servidor HTTPS web + storage (sanders)

Estado: **✅ no ar** — `https://cloudflared.stratyconfig.com` servindo uma
página estática + um backend de teste, com HTTPS público mesmo o link estando
**atrás de CGNAT** (sem IP público). Storage (filebrowser) instalado, config
pendente.

Device: Motorola XT1802 (`sanders`, MSM8953) · Arch Linux ARM aarch64 ·
2.7 GB RAM · 8 cores · ~21 GB livres em `/`.

---

## Arquitetura

```
Internet
   │  HTTPS (TLS termina na borda da Cloudflare)
   ▼
Cloudflare edge (GRU / São Paulo)
   │  túnel outbound (cloudflared) — fura CGNAT, sem port-forward
   ▼
cloudflared.service  ───►  nginx :80
                              ├─ /         → /srv/www/sanders/index.html (estático)
                              └─ /api/      → reverse_proxy 127.0.0.1:3000 (backend)
```

Decisão de desenho: **um único servidor HTTP local (nginx)**. Como o
Cloudflare Tunnel termina o TLS na borda e entrega HTTP puro ao device, **não
faz sentido empilhar nginx + caddy** (seriam redundantes). O `caddy` fica
instalado, porém ocioso.

Por que Cloudflare Tunnel: o provedor está sob **CGNAT** (sem IP público
único), então port-forwarding não é opção. O `cloudflared` abre uma conexão
**de saída** para a Cloudflare; o tráfego de entrada chega por ela. Bônus:
HTTPS/cert gerenciado pela Cloudflare de graça.

---

## Componentes instalados

| Pacote | Versão | Origem | Papel |
|---|---|---|---|
| `nginx` | 1.30.2 | pacman (`extra`) | web server + reverse_proxy |
| `cloudflared` | 2026.6.0 | pacman | túnel Cloudflare (outbound) |
| `filebrowser` | 2.63.15 | binário arm64 (GitHub) | UI web de storage (config pendente) |
| `caddy` | 2.11.4 | pacman (`extra`) | instalado, **ocioso** (alternativa) |
| `python` | 3.14 | pacman | runtime do backend demo |

---

## Serviços (systemd) — todos `enabled` (sobrevivem a reboot)

| Unit | Função |
|---|---|
| `nginx.service` | serve a página + reverse_proxy |
| `sanders-demo-backend.service` | backend demo Python em `127.0.0.1:3000` (`DynamicUser`) |
| `cloudflared.service` | túnel nomeado (criado por `cloudflared service install <TOKEN>`) |

Unit efêmera (NÃO habilitada, usada só durante o bring-up):
`sanders-quicktunnel` (via `systemd-run`), que dá uma URL temporária
`*.trycloudflare.com` sem precisar de conta/domínio. Já desligada.

---

## Arquivos no device

```
/etc/nginx/nginx.conf                       # reescrito (original em .orig)
/srv/www/sanders/index.html                 # página de teste (botão chama /api/)
/usr/local/bin/sanders-demo-backend.py      # backend demo (stdlib http.server)
/etc/systemd/system/sanders-demo-backend.service
/etc/systemd/system/cloudflared.service     # criado pelo `cloudflared service install`
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

## Como o túnel nomeado foi criado (caminho via dashboard / token)

Usado o fluxo **Zero Trust → Networks → Tunnels → Create a tunnel** (túnel
gerenciado remotamente; a config de hostname/rota vive no painel, não em um
`config.yml` local):

1. **Select tunnel type** → `Cloudflared`.
2. **Name your tunnel** → ex. `sanders`.
3. **Install and run connectors** → o painel mostra comandos por SO; como o
   `cloudflared` já estava instalado no Arch, ignoramos esses comandos e
   usamos só o **token**. No device:
   ```sh
   cloudflared service install <TOKEN>
   ```
   Isso cria e habilita o `cloudflared.service`. **O token é credencial** —
   não colar em logs/relatórios.
4. **Route tunnel → Public Hostname**: Subdomain `cloudflared`, Domain
   `stratyconfig.com`, Type `HTTP`, URL `localhost:80`. Cria o CNAME
   `cloudflared.stratyconfig.com` apontando para o túnel.

Pré-requisito: o domínio `stratyconfig.com` precisa já estar na conta
Cloudflare (nameservers apontados e zona "Active") para aparecer no dropdown.

### Alternativa: túnel local (CLI), caso queira config em arquivo
`cloudflared tunnel login` → `cloudflared tunnel create sanders` →
`/etc/cloudflared/config.yml` com `ingress:` → `cloudflared tunnel route dns`
→ `cloudflared service install`. (Não é o caminho usado aqui.)

---

## Verificação

```sh
# local, no device
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/         # 200
curl -s http://127.0.0.1/api/                                       # JSON do backend

# externo (de qualquer lugar)
curl -s -o /dev/null -w '%{http_code}\n' https://cloudflared.stratyconfig.com/
curl -s https://cloudflared.stratyconfig.com/api/
```

O backend ecoa `path` (com query string), `host`, `time` — útil pra confirmar
que o caminho Cloudflare → cloudflared → nginx → backend está íntegro
ponta a ponta.

---

## Trocar pelo conteúdo real

- **Página/site:** substituir `/srv/www/sanders/index.html` (ou apontar `root`
  do nginx para outro diretório).
- **Backend real:** parar/desabilitar `sanders-demo-backend.service` e apontar
  o `proxy_pass` do nginx para a porta do seu serviço (Node/Python/Go/etc).
- **Mais hostnames:** adicionar Public Hostnames no painel da Cloudflare
  (ex. `files.stratyconfig.com` → filebrowser).

---

## 🔜 Pendente — storage (filebrowser)

`filebrowser` (v2.63.15) já está em `/usr/local/bin/filebrowser`. Falta:
definir o diretório de dados (storage), criar usuário admin, criar a unit
systemd e expor atrás do nginx — seja num path (`/files/`) ou num subdomínio
próprio do túnel (ex. `files.stratyconfig.com`).

---

## Notas / armadilhas resolvidas no bring-up

- **Egress IPv4 estava "blackholed"**: o `10-usb0.network` definia
  `Gateway=` + rota default; com o `usb0` em `linkdown`, o kernel (que **não**
  ignora rota linkdown por padrão) jogava toda a saída no buraco. Removidos
  `Gateway`/`[Route]` do `usb0` (rede de serviço, só `Address`) → default só
  via `wlan0`. Sem isso o `pacman` nem baixava.
- **Posse do rootfs**: `/`, `/etc`, `/usr` vinham `owned by alarm` (artefato do
  build) e quebravam hooks pós-install do pacman; corrigido para `root:root`.
- Veja também `docs/TROUBLESHOOTING.md`.
