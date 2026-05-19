# Contribuindo

Obrigado pelo interesse! Este é um projeto comunitário em estágio
inicial — qualquer contribuição é bem-vinda.

## Antes de começar

1. Leia o [`README.md`](../README.md), [`STEP_BY_STEP.md`](STEP_BY_STEP.md)
   e [`HARDWARE_STATUS.md`](HARDWARE_STATUS.md).
2. Tenha um Moto G5s Plus desbloqueado (e seja capaz de aceitar o risco
   de bricar — embora `fastboot boot` torne o risco baixo).
3. Familiarize-se com o ciclo de iteração rápida descrito em
   `STEP_BY_STEP.md`.

## Áreas onde ajuda é mais valiosa (em ordem de prioridade)

### 🔴 Prioridade alta — sem isso, sistema não é usável

1. **Resolver `dwc3: failed to initialize core`**
   - Sem CDC ACM, não há console interativo via cabo USB.
   - Hipóteses em `HARDWARE_STATUS.md#usb-dwc3`.
   - Como debugar: ler `pstore`/`ramoops` após reboot; comparar com
     pmOS potter.

2. **Habilitar touchscreen Synaptics RMI4**
   - DTS já descreve em `&i2c_3`. Falta apenas:
     ```
     CONFIG_RMI4_CORE=y
     CONFIG_RMI4_I2C=y
     CONFIG_RMI4_F11=y
     ```
     em `kernel/sanders.config.fragment`.
   - Teste: após boot, verificar `/dev/input/eventN`, `cat /proc/bus/input/devices`.

### 🟡 Prioridade média — torna o sistema utilizável

3. **Wi-Fi (QCA wcnss)**
   - Driver `wcn36xx` mainline.
   - Firmware: extrair de Android stock dump.
   - Validar com `iw dev wlan0 scan`.

4. **Painel real (Tianma NT35596 ou DJN ILI7807D)**
   - Sub-projeto. Verificar drivers similares em `drivers/gpu/drm/panel/`.
   - `lk2nd:panel` reporta qual painel a unidade tem; G5s Plus pode ter os dois.

### 🟢 Prioridade baixa — qualidade de vida

5. **Áudio (`q6asm`, etc.)** — requer firmware proprietário e configuração
   ALSA UCM extensa.
6. **GPU Adreno 506** — `freedreno` mainline geralmente funciona em
   msm8953 com pouco trabalho.
7. **Modem (telefonia)** — extremamente complexo. Veja postmarketOS
   `qrtr`/`msm-modem` para referência.
8. **Sensores** — drivers existem; precisa habilitar e descrever no DTS.
9. **Painel rotacionado** — corrigir orientação do framebuffer
   console pra rotacionar 90°.

## Fluxo de PR

1. Fork do repo.
2. Crie branch descritiva: `git checkout -b feat/touchscreen-rmi4`.
3. Cada PR deve:
   - **Compilar limpo** (sem warnings adicionais no kernel).
   - **Bootar até `archlinuxarm login:`** no pelo menos uma variante (P1, P2, P3, P4).
   - Atualizar `docs/HARDWARE_STATUS.md` se mudou o status de algum
     componente.
   - Incluir foto/screenshot do device se possível.
4. Descrição do PR: o quê, por quê, como testou.

## Convenções

- **Idioma:** README + comentários em código preferencialmente em
  inglês para alcance comunitário; docs longos podem ser em
  pt-BR + inglês.
- **Commit messages:** [Conventional Commits](https://www.conventionalcommits.org/).
  Exemplos:
  - `feat(dts): enable Synaptics RMI4 touchscreen`
  - `fix(initramfs): correct switch_root path`
  - `docs(troubleshoot): add note about CONFIG_TC busybox break`
- **DTS:** preserve o cabeçalho BSD-3-Clause original.

## Relatar bugs

Issues bem-vindos! Inclua:

- Variante do device (P1/P2/P3/P4 — descubra com `fastboot getvar lk2nd:device`).
- Output completo de `git log -1` no kernel mainline (commit usado).
- `dmesg` ou foto da tela.
- Cmdline usado.

## Código de conduta

Trate todos com respeito. Este é um espaço aberto para todos os
níveis de experiência — perguntas "básicas" são bem-vindas.
