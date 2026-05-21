# Ideias de uso — sanders rodando Linux mainline

Brainstorm de coisas interessantes pra fazer com o Moto G5s Plus rodando
Arch Linux ARM + kernel mainline. Organizadas por "esforço pra começar".
Marca o que está bloqueado por hardware ainda não suportado (ver
`HARDWARE_STATUS.md`).

Estado atual relevante:
- ✅ USB ACM + ECM (console + rede via cabo)
- ✅ Touchscreen, display via SimpleDRM (software render)
- ✅ Bluetooth WCN3680B (BR/EDR + BLE, BNEP/HID/RFCOMM/A2DP-capable)
- ❌ Wi-Fi (firmware MEM_FAIL, upstream-blocked)
- ❌ Modem/GSM, sensores, áudio, painel real/GPU

---

## Frutos baixos (dá pra tentar já)

### 1. Internet via BT PAN (substituto do Wi-Fi)
Pareia com um phone Android e usa BT tethering (NAP). O kernel já tem
`CONFIG_BT_BNEP=y`. Resolve "phone Linux sem rede sem cabo" — útil pra
sair do laboratório.

- Setup: `bluetoothctl connect <mac>` → `nm-connection-editor` ou
  `bt-network -c <mac> nap` → `dhclient bnep0`.
- Throughput esperado: 1–3 Mbps (BR/EDR limit), suficiente pra ssh,
  apt, pacman.

### 2. Hub/Scanner BLE
Phone como ferramenta de bancada pra IoT BLE. Zero hardware extra.

- `bluetoothctl scan le` lista beacons.
- `btmon` + Wireshark via ECM = sniffer HCI completo.
- Python `bleak` pra ler sensores próprios (Xiaomi temp/hum, RuuviTag).
- Daemon que coleta e expõe via MQTT pelo ECM USB.

### 3. Teclado/mouse BT (Phosh usável de verdade)
Phosh roda mas é apertado pra digitar. Teclado BT vira um mini-laptop
estilo "Linux no bolso".

- `bluetoothctl pair <kbd-mac>` → driver HIDP já builtin.
- Combina bem com a flavor `desktop`.

### 4. "Writer deck" foco-total
TTY puro + teclado BT + framebuffer (TER16x32 já configurado). Bateria
dura horas, sem distração.

- `getty@tty1` + `vim`/`micro` + `git` local.
- Sync por BT PAN ou ECM USB quando dock.

### 5. Receptor de Smartwatch / wearables
Smartwatches genéricos falam BLE GATT. Dá pra logar notificações,
batimento, passos sem usar app proprietário do fabricante.

- Projetos: `bandbridge`, `huawei-band-research`, `gadgetbridge` server.

---

## Médio prazo (depende de codec de áudio funcionar)

### 6. Speaker BT caseiro
Phone vira receptor A2DP, sai pelo P2 (ou amplificador externo) — recicla
qualquer caixa burra.

- `bluez` + `pipewire` + `wireplumber` + perfil A2DP-sink.
- Bloqueia até codec WCD9335/AMP funcionarem mainline.

### 7. Internet radio / podcast player
Mesma cadeia. UI via Phosh com `gnome-podcasts` ou CLI com `mpd`.

### 8. Babá eletrônica / interfone
Mic do phone + transmissão A2DP/SCO pra outro device BT. Latência ok pra
voz.

---

## Médio prazo (depende do modem mainline — `qcom-q6v5-mss`)

### 9. Phone "de verdade" sem stock
Habilitar Q6V5 modem + ModemManager + oFono = voz, SMS, dados móveis.
Junto com Phosh já há UI de discagem (`gnome-calls`).

### 10. Gateway 4G → BT PAN
Phone recebe internet pelo modem celular e redistribui via BT PAN pra
outros devices. Hotspot móvel rodando Linux puro.

### 11. SMS gateway / 2FA receiver
Servidor local que recebe SMS e expõe via API REST pro PC. Útil pra
codes 2FA quando o phone fica numa gaveta.

---

## Automação / casa

### 12. Presença por RSSI
Scan contínuo dos MACs BT/BLE conhecidos da família, publica
"casa.pessoa.presente" via MQTT. Casa burra → casa esperta.

### 13. Home Assistant edge node
HA Core roda em ARM64 com pouca RAM. Phone embaixo da mesa, alimentado
por carregador, como hub BT/BLE da casa (sensores Xiaomi, Govee, IKEA).

### 14. Pi-hole-like sobre ECM
Phone como gateway DNS pro PC via USB. Bloqueia ads via DNS sinkhole.
Combo com BT PAN como uplink fecha o ciclo sem Wi-Fi.

### 15. Botão físico universal
Volume keys + script = controle remoto pra qualquer coisa (luz, música,
casa). 2 botões físicos viram macro pad.

---

## Pesquisa / security (com autorização)

### 16. BLE MITM / pentest
Estilo `gattacker`/`btlejack`: clona um device BLE, proxia tráfego, audita
implementações próprias. Phone como dropbox barato.

### 17. War-walking de beacons
Coleta passiva de BLE + GPS (quando sensores funcionarem) pra mapear
beacons de varejo, AirTags etc. Phone no bolso, daemon escrevendo CSV.

### 18. Honeypot BT
Anuncia um nome chamativo ("Free_Earbuds", "AirPods Pro") e loga quem
tenta parear. Estudo de comportamento em ambientes públicos.

### 19. Ferramenta de bancada pra fuzzing HCI
btmon + scapy + bluez vira lab de fuzz de stack BT alheia. Phone barato
+ Linux puro + acesso HCI cru = setup difícil de bater.

---

## Maluco / divertido

### 20. Servidor caseiro de baixíssimo consumo
8-core A53 + 4GB RAM + bateria embutida (UPS grátis!) + Linux mainline.
Roda Syncthing, Gitea, Vaultwarden, Jellyfin (audio-only por ora).

### 21. eBook reader / leitor RSS
Foliate ou klar via Phosh. Pouca CPU, bateria boa. Tela de 5.5" FHD é
ótima pra ler.

### 22. "Carteira fria" offline
Phone nunca conecta na rede. Gera/assina txs Bitcoin/Ethereum, exporta
QR. ECM desligado, BT desligado. Wallet hardware faça-você-mesmo.

### 23. Mini DAW portátil
ardour/lmms + teclado BT/MIDI USB. Latência ruim com pixman, mas pra
composição sequencial funciona.

### 24. Captive portal de eventos
Phone com hotspot ECM serve uma página de check-in/quiz/menu. Útil pra
festa, sala de aula, demo.

### 25. Time machine de logs
Phone sentado num cantinho rodando journald+loki, recebe logs via syslog
de routers e IoT da casa. 3 anos de retenção em 32GB.

### 26. Câmera de segurança (depois que a câmera funcionar)
motion/zoneminder + sensor da câmera traseira. Stream via BT PAN ou
4G. Babá eletrônica com IA simples (motion detect → notif).

### 27. Distro de demonstração
Imagem `headless` super-enxuta que outras pessoas curiosas possam
flashar e brincar. "Linux puro num phone que tava na gaveta".

### 28. Lab de USB gadget
Já temos ACM+ECM. Dá pra rodar qualquer gadget: HID (phone vira
teclado/mouse pro PC), Mass Storage (pendrive virtual), MIDI, Audio.
Phone como periférico programável.

---

## "Cool but probably not"

- **Cluster de phones** — bonito no papel, terrível na prática (consumo,
  calor, gerência).
- **Mineração** — Adreno 506 sem driver = lixo de hashrate, e mesmo com
  freedreno não compensa eletricidade.
- **Rodar Windows** — qemu-user só roda binário, não kernel; KVM no A53
  é lento; gpu passthrough impossível.

---

## Próximas prioridades naturais

Olhando o estado de hardware, os fronts que destravam mais ideias dessa
lista, em ordem:

1. **Sensores** (acel/giro/prox) — destrava autorotate + presença + UX
   geral do Phosh. Baixa complexidade.
2. **Painel real** (Tianma/DJN) — destrava freedreno/Adreno, fim do
   software render, todas ideias com UI ganham qualidade.
3. **Áudio** (WCD9335 + speaker amp) — destrava ideias 6, 7, 8, 23, 26.
4. **Modem** (Q6V5) — destrava 9, 10, 11. Mais complexo, firmware
   proprietário, mas existe trabalho upstream pro msm8953.

Wi-Fi continua bloqueado upstream (MEM_FAIL no firmware). BT PAN cobre
boa parte das ideias de rede.
