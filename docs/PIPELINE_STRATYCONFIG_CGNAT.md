# Pipeline stratyconfig.com — acesso remoto sob CGNAT

Deployment **específico** deste device: expor o mini-servidor (ver
[`MINI_SERVER.md`](MINI_SERVER.md)) na internet com HTTPS público **mesmo o link
estando atrás de CGNAT** (sem IP público), usando o domínio `stratyconfig.com`.

Resumo: **Cloudflare Tunnel** (conexão de saída — fura CGNAT, sem
port-forward) + **Cloudflare Access** na frente do SSH (anti-brute-force, já que
este kernel não tem firewall).

```
você / internet
   │  HTTPS (TLS termina na borda da Cloudflare) / Access (auth)
   ▼
Cloudflare edge
   │  túnel outbound (cloudflared)
   ▼
cloudflared.service (device)  ──►  localhost:80  (nginx / web)
                              └─►  localhost:22  (sshd)
```

---

## 1. Pré-requisito: domínio na Cloudflare
`stratyconfig.com` precisa usar os **nameservers da Cloudflare** (zona "Active").
Sem isso os hostnames não podem ser roteados pelo tunnel.

## 2. Tunnel nomeado (gerenciado pelo dashboard / token)
Criado em **Zero Trust → Networks → Tunnels → Create a tunnel**:
- Tipo **Cloudflared**, nome ex. `sanders`.
- **Install and run connectors**: o painel mostra comandos por SO. Como o
  `cloudflared` já está instalado no Arch, ignore-os e use só o **token**. No
  device:
  ```sh
  cloudflared service install <TOKEN>
  ```
  Cria e habilita o `cloudflared.service`. **O token é credencial — nunca em
  log/relatório.**
- A config de ingress/rota fica **no painel** (não em `config.yml` local).

### Public Hostnames (aba do Tunnel)
| Hostname | Type | URL | Para |
|---|---|---|---|
| `cloudflared.stratyconfig.com` | HTTP | `localhost:80` | web / dashboard (nginx) |
| `ssh.stratyconfig.com` | SSH | `localhost:22` | SSH remoto |

Cada Public Hostname cria automaticamente um **CNAME proxied** no DNS da zona.

---

## 3. SSH remoto seguro (Access em vez de firewall)

⚠️ **Firewall não é possível neste kernel**: netfilter é modular
(`NF_CONNTRACK=m`, `IP_NF_IPTABLES=m`) e os módulos não foram instalados no
rootfs → `nft`/`iptables`/`fail2ban` falham (`Protocol not supported`). Logo, a
proteção anti-brute-force vem do **Cloudflare Access**. (TODO: `NF_TABLES`/
`NF_CONNTRACK` builtin num próximo rebuild de kernel.)

### Cloudflare Access (gate do SSH)
**Zero Trust → Access → Applications → Add → Self-hosted**:
- Domínio: `ssh.stratyconfig.com`
- Política: ex. **OTP por e-mail** pro seu endereço.

Com isso, ninguém alcança o sshd sem passar pelo Access primeiro.

### sshd no device (senha + chave, endurecido)
Drop-in `/etc/ssh/sshd_config.d/10-sanders-hardening.conf`:
```
PasswordAuthentication yes      # login por senha (estilo VPS), atrás do Access
PubkeyAuthentication yes
PermitRootLogin yes
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AllowUsers root
MaxAuthTries 3
LoginGraceTime 20
X11Forwarding no
AllowAgentForwarding no
```
Extra: `LLMNR=no` + `MulticastDNS=no` no systemd-resolved (fecha 5353/5355).
**Trocar a senha de root** antes de expor: `ssh -t root@<ip-lan> passwd`.

---

## 4. Cliente (máquina de onde você conecta)

1. Instalar `cloudflared` (Linux/macOS/Windows; binário arm64/amd64 do GitHub).
2. `~/.ssh/config`:
   ```
   Host ssh.stratyconfig.com
       User root
       IdentityFile ~/.ssh/id_ed25519
       ProxyCommand /caminho/cloudflared access ssh --hostname %h
   ```
3. Login do Access (uma vez por sessão de token):
   ```sh
   cloudflared access login ssh.stratyconfig.com
   ```
   Abre URL no navegador → autentica (OTP) → token salvo em `~/.cloudflared`.
4. Conectar de qualquer lugar:
   ```sh
   ssh root@ssh.stratyconfig.com
   ```
   (Access pede auth, depois vem o login SSH. `SSH_CONNECTION` chega como
   `::1 → ::1:22` — loopback, pois o cloudflared entrega em `localhost:22`.)

### Gotcha cliente sem IPv6 (ex.: WSL2)
O hostname resolve A + AAAA (IPs anycast da Cloudflare). Em cliente **sem rota
IPv6** (WSL2 default), o `cloudflared` pega o AAAA e falha
(`network is unreachable`). Fix: fixar o IPv4 no `/etc/hosts` do cliente, ex.:
```
104.21.93.134 ssh.stratyconfig.com
172.67.210.48 ssh.stratyconfig.com
```
(ou usar um cliente com IPv6 funcional).

---

## Camadas de segurança (resumo)
1. **CGNAT** — zero inbound WAN; só o tunnel (outbound) entrega tráfego.
2. **Cloudflare Access** — gate de autenticação na frente do SSH (substitui o
   firewall/fail2ban ausentes).
3. **sshd endurecido** — `MaxAuthTries`, `AllowUsers root`, grace curto, sem
   X11/agent-forward.
4. **Serviços sensíveis em localhost** — backend `:3000` e métricas só no loopback.

## Renovação
O token do Access expira (duração configurável no painel). Quando expirar:
`cloudflared access login ssh.stratyconfig.com` de novo.
