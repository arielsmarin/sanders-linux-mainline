#!/usr/bin/env python3
"""
Interação automática com o dispositivo via /dev/ttyACM0.
Envia sequência de teste wcn36xx e captura output do dmesg.
"""

import os
import sys
import time
import termios
import tty
import threading
import select
import re
import itertools

DEV = "/dev/ttyACM0"
BAUD = termios.B115200
LOG = "/tmp/sanders-serial.log"

def open_serial(dev, baud):
    fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attr = termios.tcgetattr(fd)
    attr[0] = 0  # iflag
    attr[1] = 0  # oflag
    attr[2] = termios.CS8 | termios.CREAD | termios.CLOCAL | baud  # cflag
    attr[3] = 0  # lflag: raw
    attr[4] = baud
    attr[5] = baud
    attr[6][termios.VMIN] = 0
    attr[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attr)
    os.set_blocking(fd, False)
    return fd

def write_all(fd, data, timeout=5):
    deadline = time.time() + timeout
    view = memoryview(data)
    while view and time.time() < deadline:
        try:
            written = os.write(fd, view)
            view = view[written:]
        except BlockingIOError:
            select.select([], [fd], [], 0.1)
    if view:
        raise TimeoutError("serial write timed out")

def send(fd, cmd, delay=0.3):
    line = ("\r" + cmd + "\r").encode()
    write_all(fd, line)
    print(f">>> {cmd}", flush=True)
    time.sleep(delay)

_marker_counter = itertools.count()

def run_cmd(fd, cmd, timeout=10, log_fn=None):
    marker = f"__SERIAL_DONE_{next(_marker_counter)}__"
    line = f"{cmd}; echo {marker}:$?"
    write_all(fd, ("\r" + line + "\r").encode())
    print(f">>> {cmd}", flush=True)

    buf = ""
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.2)
        if not r:
            continue
        chunk = os.read(fd, 4096)
        if not chunk:
            continue
        text = chunk.decode("utf-8", errors="replace")
        buf += text
        sys.stdout.write(text)
        sys.stdout.flush()
        if log_fn:
            log_fn(text)
        if re.search(rf"{re.escape(marker)}:\d+", buf):
            return buf
    return buf

def read_all(fd, timeout=2.0):
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            chunk = os.read(fd, 4096)
            if chunk:
                buf += chunk
    return buf.decode("utf-8", errors="replace")

def wait_for(fd, pattern, timeout=30):
    buf = ""
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            chunk = os.read(fd, 4096)
            if chunk:
                text = chunk.decode("utf-8", errors="replace")
                buf += text
                sys.stdout.write(text)
                sys.stdout.flush()
                if pattern in buf:
                    return True, buf
    return False, buf

def has_exact_line(text, expected):
    return any(line.strip() == expected for line in text.splitlines())

def has_wlan0(text):
    return re.search(r"wlan0:\s", text) is not None

def main():
    print(f"[serial_test] Abrindo {DEV}...")
    fd = open_serial(DEV, BAUD)
    logfile = open(LOG, "w")

    def log(text):
        logfile.write(text)
        logfile.flush()

    # Flush buffer inicial
    read_all(fd, timeout=1.0)
    send(fd, "")  # Enter para ver prompt

    out = read_all(fd, timeout=2.0)
    log(out)
    print(out, end="")

    print("\n[serial_test] === STEP 0: Silenciar runs anteriores ===")
    run_cmd(fd, "echo 0 > /sys/module/wcn36xx/parameters/debug_mask 2>/dev/null; pkill wpa_supplicant 2>/dev/null || true; rm -f /run/wpa_supplicant/wlan0; true", timeout=20, log_fn=log)
    read_all(fd, timeout=3.0)

    print("\n[serial_test] === STEP 1: Firmware recovery ===")
    out = run_cmd(fd, "[ -e /lib/firmware/wcnss.mdt ] && echo FW_ALREADY_OK || echo FW_MISSING", timeout=8, log_fn=log)

    if has_exact_line(out, "FW_MISSING") or not has_exact_line(out, "FW_ALREADY_OK"):
        print("[serial_test] Fazendo firmware recovery...")
        run_cmd(fd, "mkdir -p /mnt/modem && mount -o ro /dev/disk/by-partlabel/modem /mnt/modem 2>/dev/null; true", timeout=8, log_fn=log)
        run_cmd(fd, "cp -v /mnt/modem/image/wcnss.mdt /mnt/modem/image/wcnss.b* /lib/firmware/ 2>/dev/null; true", timeout=12, log_fn=log)

    print("[serial_test] Verificando remoteproc...")
    out = run_cmd(fd, "cat /sys/class/remoteproc/remoteproc0/state 2>/dev/null || echo unknown", timeout=8, log_fn=log)
    if has_exact_line(out, "offline") or has_exact_line(out, "unknown"):
        print("[serial_test] remoteproc offline; iniciando WCNSS (NV download leva ~70s)...")
        run_cmd(fd, "echo start > /sys/class/remoteproc/remoteproc0/state", timeout=15, log_fn=log)
        read_all(fd, timeout=10.0)

    print("\n[serial_test] === STEP 2: Verificar wlan0 (aguarda até 90s para NV download) ===")
    out = run_cmd(fd, "for i in $(seq 1 90); do ip -o link show wlan0 2>/dev/null && break; sleep 1; done", timeout=95, log_fn=log)

    if not has_wlan0(out):
        print("[serial_test] wlan0 não encontrado, tentando recovery completo...")
        run_cmd(fd, "echo stop  > /sys/class/remoteproc/remoteproc0/state 2>/dev/null; true", timeout=20, log_fn=log)
        run_cmd(fd, "echo start > /sys/class/remoteproc/remoteproc0/state", timeout=20, log_fn=log)
        read_all(fd, timeout=10.0)
        out = run_cmd(fd, "for i in $(seq 1 90); do ip -o link show wlan0 2>/dev/null && break; sleep 1; done", timeout=95, log_fn=log)

    if not has_wlan0(out):
        print("[serial_test] ERRO: wlan0 não apareceu após recovery; abortando antes do wpa_supplicant.")
        logfile.close()
        os.close(fd)
        return

    print("\n[serial_test] === STEP 3: Setup debug mask e wpa_supplicant ===")
    run_cmd(fd, "echo 0x100 > /sys/module/wcn36xx/parameters/debug_mask", timeout=8, log_fn=log)
    run_cmd(fd, "pkill wpa_supplicant 2>/dev/null || true; rm -f /run/wpa_supplicant/wlan0", timeout=8, log_fn=log)
    run_cmd(fd, "ip link set wlan0 down 2>/dev/null || true", timeout=8, log_fn=log)
    run_cmd(fd, "ip link set wlan0 up", timeout=15, log_fn=log)
    run_cmd(fd, "dmesg -C", timeout=8, log_fn=log)
    run_cmd(fd, "wpa_supplicant -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant-wlan0.conf -D nl80211 -B", timeout=10, log_fn=log)

    print("\n[serial_test] === STEP 4: Aguardando resultado (30s) ===")
    # Espera por outcome: falha ou sucesso
    run_cmd(fd, """timeout 32 sh -c '
  while true; do
    dmesg | grep -qEi "response failure: 5|4WAY_HANDSHAKE_TIMEOUT|deauthenticated|refusing config_sta" && echo OUTCOME_FAIL && break
    dmesg | grep -qEi "CTRL-EVENT-CONNECTED|wlan0.*associated" && echo OUTCOME_OK && break
    sleep 1
  done
  echo OUTCOME_TIMEOUT
'""", timeout=40, log_fn=log)

    print("\n[serial_test] === STEP 5: Capturando dmesg ===")
    # Grep específico para CONFIG_BSS/STA — sem 'HAL >>>' para evitar flood de NV download
    # 'HAL config bss v1 req:' captura o dump inline (WCN36XX_DBG_HAL_DUMP=0x200)
    # 'hal config bss v1' captura as linhas de texto (WCN36XX_DBG_HAL=0x100)
    run_cmd(fd, r"dmesg | grep -Ei 'hal config bss v1|HAL config bss v1 req:|hal config sta v1|HAL config sta v1|req len=|sizeof_req=|sta bssid|response failure|refusing|TIMEOUT|associated|deauth|hal config bss rsp|hal config bss response|rsp status|refusing config_sta|status 5' | tail -200 | tee /tmp/wcn36xx-bss-capture.log", timeout=12, log_fn=log)

    print("\n[serial_test] === STEP 6: dmesg completo para arquivo ===")
    run_cmd(fd, "dmesg > /tmp/wcn36xx-test.log && echo LOG_SAVED", timeout=8, log_fn=log)

    logfile.close()
    os.close(fd)
    print(f"\n[serial_test] Concluído. Log local: {LOG}")

if __name__ == "__main__":
    main()
