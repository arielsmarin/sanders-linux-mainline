# Ralph Loop — Wi-Fi wcn36xx CONFIG_BSS MEM_FAIL=5

**Criado:** 2026-06-07 19:53  
**Atualizar este arquivo após cada iteração.**

---

## Estado da iteração atual

**Iteração:** 8 — Experiment 0007: bssid_index=0 no embedded STA pré-assoc  
**Status:** PAUSADO — MUDANÇA DE PLANO PARA STOCK ROM + ENGENHARIA REVERSA

### Checkpoint 2026-06-07 20:xx — pausa do loop mainline

Plano mudou: instalar ROM stock no Motorola XT1802/sanders e usar Android
funcionando como referência para engenharia reversa do Wi-Fi/CNSS/Pronto.

O teste do exp 0007 **não produziu resultado conclusivo**. Importante: isso não
falsifica a hipótese `bssid_index=0`; o problema foi o harness serial/debug:

- `build/out/boot-sanders.img` 2026-06-07 19:53 foi bootado via `fastboot boot`
  e contém exp 0007.
- O device subiu Arch/mainline e `wlan0` apareceu após recovery WCNSS em pelo
  menos uma execução.
- `debug_mask=0x308`/`0x300` ativou dump HAL/SMD verboso (`HAL >>>`) e saturou
  a serial; isso atrasou comandos, misturou saídas antigas e invalidou a coleta.
- `debug_mask=0x100` é o valor preferível para nova tentativa manual, pois evita
  o dump hex e mantém logs HAL textuais.
- `scripts/serial_test.py` foi modificado durante a tentativa para usar markers,
  CR no terminal serial e `debug_mask=0x100`, mas ainda deve ser tratado como
  experimental/não validado.
- Não foi feito `fastboot flash` durante esta sessão; apenas `fastboot boot`.

Próximo fluxo agora:

1. Instalar/bootar ROM stock.
2. Validar Wi-Fi funcionando no Android stock.
3. Capturar logs de conexão Wi-Fi funcionando (`logcat`, `dmesg` se possível,
   propriedades CNSS/WCNSS, firmware carregado).
4. Extrair/identificar driver prima/CNSS e firmware/NV stock.
5. Comparar a sequência stock equivalente a CONFIG_BSS/CONFIG_STA com o
   wcn36xx mainline instrumentado.

### Hipótese
O firmware Pronto 1.5.1.2 rejeita CONFIG_BSS ADD quando o embedded STA tem
`bssid_index=0xFF` (WCN36XX_HAL_BSS_INVALID_IDX). Em STA mode, o FW espera
`bssid_index=0` para o slot BSS a ser alocado.

### Patch/mudança aplicada
**Arquivo:** `build/linux/drivers/net/wireless/ath/wcn36xx/smd.c` ~linha 1810  
**Mudança inline (não como patch separado):**
```c
// ANTES:
sta->bssid_index = WCN36XX_HAL_BSS_INVALID_IDX;  // 0xFF

// DEPOIS:
sta->bssid_index = 0; /* EXPERIMENTAL 0007: try 0 instead of 0xFF */
```
Dentro do bloco `if (!sta_80211 && vif->type == NL80211_IFTYPE_STATION)`.

### Experimentos ativos em smd.c (todos inline)
| ID | Descrição | Status |
|----|-----------|--------|
| 0004 | Debug detalhado BSS/STA req/rsp com sizeof/offsets/hex | ativo |
| 0006 | Disable HT/VHT/AMPDU globalmente (legacy 11g) | ativo |
| 0007 | bssid_index=0 no embedded STA pré-assoc (ADD) | ativo, NÃO TESTADO |

### Boot image
- `build/out/boot-sanders.img` — gerado 2026-06-07 19:53
- Contém: kernel + DTB + initramfs com firmware WCNSS

### Rollback do exp 0007
```bash
# No repo WSL:
# Editar build/linux/drivers/net/wireless/ath/wcn36xx/smd.c
# Reverter bssid_index = 0 para bssid_index = WCN36XX_HAL_BSS_INVALID_IDX
# Depois:
bash scripts/02-build-kernel.sh && bash scripts/04-build-initramfs.sh && bash scripts/06-build-boot.sh
```

---

## Como testar

### 1. Boot no device (WSL/Windows)
```sh
# PowerShell admin: usbipd attach --wsl --busid <busid>
sudo fastboot boot build/out/boot-sanders.img
# PowerShell: re-attach usbipd
sudo python3 scripts/serial_test.py
```

### 2. Alternativa: manual via picocom
```sh
sudo picocom -b 115200 /dev/ttyACM0
# No device (após firmware recovery):
echo 0x300 > /sys/module/wcn36xx/parameters/debug_mask
pkill wpa_supplicant 2>/dev/null; true
rm -f /run/wpa_supplicant/wlan0
dmesg -C
wpa_supplicant -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf -D nl80211 &
sleep 20
kill %1 2>/dev/null
dmesg | grep -Ei 'hal config bss v1|HAL config bss v1 req:|hal config sta v1|req len=|sizeof_req=|sta bssid|response failure|refusing|status 5|bssid_index' | tail -100
```

### 3. O que procurar no log
- `"bssid_index=0"` na linha `"sta bssid ..."` → exp 0007 está ativo no kernel
- `"hal config bss v1 rsp: status=0"` → CONFIG_BSS ADD passou → próximo: CONFIG_STA
- `"hal config bss v1 rsp: status=5"` → bssid_index NÃO era o problema → exp 0007 falsificado

---

## Matriz de interpretação

| Resultado | Conclusão | Próxima ação |
|-----------|-----------|--------------|
| status=0 em CONFIG_BSS ADD | exp 0007 correto! | Verificar CONFIG_STA, testar WPA2 |
| status=5 ainda, bssid_index=0 visível | bssid_index não é o problema | Hipótese 3: nw_type / outros campos |
| status=5, bssid_index=0xFF no log | exp 0007 não compilou/não ativo | Verificar smd.c, rebuild |
| sem "hal config bss v1" no log | debug_mask errado ou timeout | Aumentar timeout, usar 0x300 |

---

## Histórico de iterações

| Iter | Hipótese | Resultado |
|------|----------|-----------|
| 1 | VHT=1 no embedded STA pré-assoc causa MEM_FAIL | VHT=0 confirmado → MEM_FAIL persiste |
| 2 | debug_mask 0x2 (DXE_DUMP) usado errado como HAL | Corrigido para 0x100/0x300 |
| 3 | struct size incorreta (v0 vs v1) | sizeof_req=482 confirmado OK |
| 4 | bss_index inválido em CONFIG_STA | Guard adicionado, problema não é aí |
| 5 | SMD_DUMP (0x008) gerando flood NV (97 linhas/frag) | grep ajustado para evitar "HAL >>>" |
| 6 | HT/VHT ainda influenciando | Exp 0006: disable total HT/VHT/AMPDU |
| 7 | RSP hex capturada: sta_index=66 (>40) → inválido | Provavelmente consequência do MEM_FAIL, não causa |
| 8 | bssid_index=0xFF rejeitado pelo FW no ADD pré-assoc | **INCONCLUSIVO**: imagem com exp 0007 bootou, mas coleta foi contaminada por flood serial/debug_mask |
| 9 | Usar Android stock como referência | **PRÓXIMO PLANO**: instalar ROM stock e capturar Wi-Fi funcionando |

---

## Próximas hipóteses se exp 0007 falhar

**Hipótese 9:** Campo `nw_type` tem valor errado.
- O enum `wcn36xx_hal_nw_type` tem `MAX_ENUM_SIZE=0x7FFFFFFF` → 4 bytes
- Para 2.4 GHz: deve ser `HAL_11G_NW_TYPE=2`
- Verificar: no hex dump do CONFIG_BSS ADD, bytes na posição do nw_type

**Hipótese 10:** Campo `bss_type` errado.
- `wcn36xx_hal_bss_type` → enum 4 bytes
- Para infrastructure STA: deve ser `HAL_INFRASTRUCTURE_MODE=0`

**Hipótese 11:** Comparar struct byte-a-byte com prima/CAF driver.
- Repo CAF: `drivers/staging/prima/` no kernel msm-3.10 ou msm-4.14
- Função equivalente: `halMsgConfig_Bss()`
- Pegar log de prima funcionando (Android) e comparar campos
- Com ROM stock instalada, priorizar captura real do device antes de buscar CAF.

**Hipótese 12:** Problema no WPA2 crypto path, não no BSS.
- Tentar conectar em **rede aberta** (sem PSK) para isolar
- Se aberta funcionar → bug é no 4-way handshake, não no CONFIG_BSS

**Hipótese 13:** Mainline está divergindo de sequência/ordem de inicialização
CNSS usada pelo stock.
- Capturar ordem stock: firmware load, WCNSS_CTRL, self STA, channel list,
  scan, join/config BSS, config STA.
- Comparar com timestamps/ordem do wcn36xx mainline.

---

## Arquivos chave

```
build/linux/drivers/net/wireless/ath/wcn36xx/smd.c   # modificado (exps 0004/0006/0007)
build/linux/drivers/net/wireless/ath/wcn36xx/hal.h   # structs HAL (não modificado)
build/out/boot-sanders.img                             # imagem pronta para fastboot boot
scripts/serial_test.py                                 # teste automático via serial
scripts/02-build-kernel.sh                             # rebuild kernel
scripts/04-build-initramfs.sh                          # rebuild initramfs
scripts/06-build-boot.sh                               # gera boot-sanders.img
docs/HARDWARE_STATUS.md                                # status de hardware
CLAUDE.md                                              # contexto principal
```

Nota: `scripts/serial_test.py` foi alterado em 2026-06-07 20:xx para tentar
evitar falsos positivos e reduzir flood (`debug_mask=0x100`), mas não foi
validado até um resultado CONFIG_BSS limpo.

---

## Restrições de segurança (permanentes)
- NUNCA colocar senha de Wi-Fi em comando, log ou relatório
- Apenas `fastboot boot` (NUNCA `fastboot flash` sem confirmação explícita do usuário)
- Todas as operações devem ser reversíveis
- EVITAR debug_mask=0xff (causou crash do kernel anteriormente)
