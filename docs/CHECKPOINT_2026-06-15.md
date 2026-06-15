# Checkpoint — 2026-06-15

Savepoint antes de iniciar a fase do **driver de fuel gauge** (bateria).
Resume o estado do sanders como **mini-servidor headless** e o que está
versionado no repo.

## Estado funcional (validado)
- **Arch Linux ARM** persistente na eMMC, kernel mainline `7.1.0-rc4`.
- **Wi-Fi WCN3680B**: WPA2 + DHCP + ping OK. Agora em **5 GHz** (`CASAA_5G`,
  canal 153) com fallback automático para `CASA_2.4G` (priority no 5G).
- **SSH** por chave + senha (endurecido), via LAN e via Cloudflare Tunnel.
- **Mini-servidor** no ar: `nginx` (web + reverse_proxy + dashboard `/api/status`)
  + backend Python (`:3000`), exposto por Cloudflare Tunnel (HTTPS público sob
  CGNAT). Boot limpo: `is-system-running` = running, 0 falhas.
- **Bluetooth** WCN3680B funcional (MAC de fábrica restaurado).

## Versionado neste checkpoint (`rootfs-overlay/mini/`)
Artefatos reais do device trazidos pro repo (config-as-code, **sem segredos**):
- `etc/nginx/nginx.conf` — web + `reverse_proxy /api/` (root `/srv/www/sanders`).
- `srv/www/sanders/index.html` — dashboard de status (auto-refresh, lê `/api/status`).
- `usr/local/bin/sanders-demo-backend.py` — backend stdlib (`/api/status`: CPU/RAM/
  disco/proc/wifi/internet; bateria/cpufreq = indisponíveis no mainline).
- `etc/systemd/system/sanders-demo-backend.service` — unit (`DynamicUser`).
- `etc/ssh/sshd_config.d/10-sanders-hardening.conf` — sshd endurecido (senha+chave).
- `etc/systemd/resolved.conf.d/10-sanders-hardening.conf` — LLMNR/mDNS off.
- `etc/systemd/system/systemd-networkd-wait-online.service.d/wlan0.conf` — só wlan0.
- `etc/systemd/network/10-usb0.network` — fix do egress (sem Gateway/rota default).

## Intencionalmente NÃO versionado (segredos / específico do deployment)
- `wpa_supplicant-wlan0.conf` com PSK real → fica só no device (overlay tem template).
- cloudflared (`/etc/cloudflared`, token, service) e o domínio/Access →
  documentado em `PIPELINE_STRATYCONFIG_CGNAT.md`, não em arquivos do repo.

## Documentação
- `MINI_SERVER.md` — pipeline padrão (genérico) do mini-servidor.
- `PIPELINE_STRATYCONFIG_CGNAT.md` — deployment próprio (CGNAT + domínio + acesso remoto).
- `HARDWARE_STATUS.md` — Wi-Fi/Bluetooth ✅; bateria/áudio/painel pendentes.

## Pendências conhecidas (precisam rebuild de kernel)
- **Firewall**: netfilter modular sem módulos instalados → `nft`/`iptables` falham.
  Mitigado por Cloudflare Access. TODO: `NF_TABLES`/`NF_CONNTRACK` builtin.
- **Bateria**: sem fuel-gauge/charger no mainline (PMI8950: `qpnp-fg`/`SMBCHG`).
  VADC (tensão/temp) seria possível com canal `VBAT_SNS` + driver builtin.

## Próxima fase
**Driver de fuel gauge do PMI8950** — ver investigação a iniciar (downstream
`qpnp-fg`, VADC, perfil de bateria, registro SRAM da FG).
