#!/usr/bin/env python3
"""Backend do Sanders mini. HTTP em 127.0.0.1:3000.
  GET /api/status -> JSON com metricas do sistema (CPU, RAM, disco, processos,
                     bateria, wifi, internet).
  GET /api/...    -> JSON simples (compat / health).
nginx faz reverse_proxy /api/ -> aqui. Sem dependencias (stdlib)."""
import json, os, socket, time, datetime, subprocess, shutil
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST, PORT = "127.0.0.1", 3000

def read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return default

def _cpu_times():
    v = list(map(int, read("/proc/stat").splitlines()[0].split()[1:]))
    idle = v[3] + (v[4] if len(v) > 4 else 0)
    return sum(v), idle

def cpu_percent(interval=0.25):
    t1, i1 = _cpu_times(); time.sleep(interval); t2, i2 = _cpu_times()
    dt, di = t2 - t1, i2 - i1
    return round(100.0 * (dt - di) / dt, 1) if dt > 0 else 0.0

def meminfo():
    d = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, val = line.partition(":")
        if val:
            d[k] = int(val.strip().split()[0])  # kB
    total = d.get("MemTotal", 0); avail = d.get("MemAvailable", 0)
    used = total - avail
    swt = d.get("SwapTotal", 0); swf = d.get("SwapFree", 0)
    return {"total_mb": round(total/1024), "used_mb": round(used/1024),
            "available_mb": round(avail/1024),
            "percent": round(100*used/total, 1) if total else 0,
            "swap_total_mb": round(swt/1024), "swap_used_mb": round((swt-swf)/1024)}

def storage(path="/"):
    st = os.statvfs(path)
    total = st.f_blocks * st.f_frsize
    free = st.f_bavail * st.f_frsize
    used = total - st.f_bfree * st.f_frsize
    return {"mount": path, "total_gb": round(total/1e9, 1),
            "used_gb": round(used/1e9, 1), "free_gb": round(free/1e9, 1),
            "percent": round(100*used/total, 1) if total else 0}

def temps():
    base = "/sys/class/thermal"; cpu = []; gpu = None
    try:
        for z in os.listdir(base):
            if not z.startswith("thermal_zone"):
                continue
            t = read(f"{base}/{z}/type"); raw = read(f"{base}/{z}/temp")
            if not raw:
                continue
            c = int(raw) / 1000.0
            if t.startswith("cpu"): cpu.append(c)
            elif t.startswith("gpu"): gpu = c
    except Exception:
        pass
    return {"cpu_max_c": round(max(cpu), 1) if cpu else None,
            "gpu_c": round(gpu, 1) if gpu is not None else None}

def processes():
    total = running = 0
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        total += 1
        s = read(f"/proc/{pid}/stat")
        try:
            if s[s.rindex(")") + 2] == "R":
                running += 1
        except Exception:
            pass
    return {"total": total, "running": running}

def battery():
    base = "/sys/class/power_supply"
    try:
        for d in os.listdir(base):
            if read(f"{base}/{d}/type") == "Battery":
                cap = read(f"{base}/{d}/capacity")
                return {"present": True,
                        "capacity": int(cap) if cap else None,
                        "status": read(f"{base}/{d}/status") or None}
    except Exception:
        pass
    return {"present": False, "reason": "sem driver de fuel gauge (mainline)"}

def get_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("1.1.1.1", 80)); ip = s.getsockname()[0]; s.close()
        return ip
    except Exception:
        return None

def wifi():
    info = {"iface": "wlan0", "connected": False}
    iw = shutil.which("iw")
    if iw:
        try:
            out = subprocess.run([iw, "dev", "wlan0", "link"],
                                 capture_output=True, text=True, timeout=3).stdout
            for line in out.splitlines():
                line = line.strip()
                if line.startswith("SSID:"): info["ssid"] = line.split(":", 1)[1].strip()
                elif line.startswith("signal:"): info["signal_dbm"] = int(line.split()[1])
                elif line.startswith("freq:"): info["freq_mhz"] = float(line.split(":", 1)[1])
                elif line.startswith("rx bitrate:"): info["rx_mbit"] = line.split(":", 1)[1].strip()
                elif line.startswith("tx bitrate:"): info["tx_mbit"] = line.split(":", 1)[1].strip()
            info["connected"] = "ssid" in info
        except Exception as e:
            info["error"] = str(e)
    if "signal_dbm" in info:
        info["quality"] = max(0, min(100, round(2 * (info["signal_dbm"] + 100))))
    info["ip"] = get_ip()
    return info

def internet():
    t0 = time.time()
    try:
        socket.create_connection(("1.1.1.1", 443), timeout=2).close()
        return {"online": True, "latency_ms": round((time.time() - t0) * 1000)}
    except Exception:
        return {"online": False}

def status():
    up = float(read("/proc/uptime", "0 0").split()[0])
    load = read("/proc/loadavg").split()[:3]
    return {"hostname": socket.gethostname(),
            "time": datetime.datetime.now().astimezone().isoformat(),
            "uptime_seconds": int(up),
            "load": [float(x) for x in load] if load else [],
            "cpu": {"cores": os.cpu_count(), "percent": cpu_percent(), **temps()},
            "mem": meminfo(), "storage": storage("/"), "processes": processes(),
            "battery": battery(), "wifi": wifi(), "internet": internet()}

class H(BaseHTTPRequestHandler):
    server_version = "sanders-demo/2.0"
    def _json(self, code, obj):
        data = (json.dumps(obj, indent=2) + "\n").encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        if path.endswith("status"):
            try:
                self._json(200, status())
            except Exception as e:
                self._json(500, {"error": str(e)})
        else:
            self._json(200, {"status": "ok", "service": "sanders-demo-backend",
                             "host": socket.gethostname(), "path": self.path,
                             "hint": "GET /api/status para metricas do sistema",
                             "time": datetime.datetime.now().astimezone().isoformat()})
    def log_message(self, fmt, *args):
        print("backend:", fmt % args, flush=True)

if __name__ == "__main__":
    srv = ThreadingHTTPServer((HOST, PORT), H)
    print(f"sanders-demo-backend ouvindo em http://{HOST}:{PORT}", flush=True)
    srv.serve_forever()
