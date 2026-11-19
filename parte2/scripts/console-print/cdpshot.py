"""Captura de pagina via Chrome DevTools Protocol (so stdlib). Uso: cdpshot.py <port> <url> <out.png> <espera_s>"""
import base64, json, os, socket, struct, sys, time, urllib.request

port, url, out, wait = int(sys.argv[1]), sys.argv[2], sys.argv[3], float(sys.argv[4])

def ws_connect(ws_url):
    host_port, path = ws_url[len("ws://"):].split("/", 1)
    host, p = host_port.split(":")
    s = socket.create_connection((host, int(p)), timeout=60)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall((f"GET /{path} HTTP/1.1\r\nHost: {host_port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
    resp = b""
    while b"\r\n\r\n" not in resp:
        resp += s.recv(4096)
    assert b" 101 " in resp.split(b"\r\n")[0], resp[:100]
    return s

def send(s, obj):
    data = json.dumps(obj).encode(); mask = os.urandom(4); n = len(data)
    hdr = bytes([0x81]) + (bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack(">H", n) if n < 65536 else bytes([0x80 | 127]) + struct.pack(">Q", n))
    s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

def recv_exact(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk: raise EOFError
        buf += chunk
    return buf

def recv(s):
    msg = b""
    while True:
        b1, b2 = recv_exact(s, 2); n = b2 & 0x7F
        if n == 126: n = struct.unpack(">H", recv_exact(s, 2))[0]
        elif n == 127: n = struct.unpack(">Q", recv_exact(s, 8))[0]
        msg += recv_exact(s, n)
        if b1 & 0x80: return json.loads(msg)

def call(s, i, method, params=None):
    send(s, {"id": i, "method": method, "params": params or {}})
    while True:
        m = recv(s)
        if m.get("id") == i: return m

for _ in range(50):
    try:
        tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=2)); break
    except Exception: time.sleep(0.3)
page = [t for t in tabs if t.get("type") == "page"][0]
s = ws_connect(page["webSocketDebuggerUrl"])
call(s, 1, "Emulation.setDeviceMetricsOverride", {"width": 1600, "height": 1000, "deviceScaleFactor": 1, "mobile": False})
call(s, 2, "Page.navigate", {"url": url})
time.sleep(wait)
r = call(s, 3, "Page.captureScreenshot", {"format": "png"})
open(out, "wb").write(base64.b64decode(r["result"]["data"]))
print("ok", out)
