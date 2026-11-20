#!/usr/bin/env python3
"""Lista las ventanas abiertas con su identificador ext-foreign-toplevel-list (JSON por stdout).

Quickshell no expone ese identificador y grim lo necesita para capturar una sola ventana
(`grim -T <identificador>`). Habla el protocolo Wayland directamente por el socket, sin dependencias.
Salida: [{"identifier": "...", "app_id": "...", "title": "..."}, ...]
Con --capture DIR además captura cada ventana (grim -T, en paralelo) y añade "file" a cada entrada.
"""
import json
import os
import socket
import struct
import subprocess
import sys

def sock_path():
    disp = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
    return disp if disp.startswith("/") else os.path.join(os.environ["XDG_RUNTIME_DIR"], disp)

def wl_string(s):
    b = s.encode() + b"\0"
    return struct.pack("<I", len(b)) + b + b"\0" * (-len(b) % 4)

class Conn:
    def __init__(self):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(sock_path())
        self.s.settimeout(3)
        self.buf = b""
        self.next_id = 2                     # 1 = wl_display

    def new_id(self):
        self.next_id += 1
        return self.next_id - 1

    def send(self, obj, opcode, payload=b""):
        size = 8 + len(payload)
        self.s.sendall(struct.pack("<II", obj, (size << 16) | opcode) + payload)

    def events(self):
        while True:
            while len(self.buf) >= 8:
                obj, word = struct.unpack_from("<II", self.buf)
                size, opcode = word >> 16, word & 0xFFFF
                if len(self.buf) < size:
                    break
                body, self.buf = self.buf[8:size], self.buf[size:]
                yield obj, opcode, body
            chunk = self.s.recv(65536)
            if not chunk:
                return
            self.buf += chunk

def read_string(body, off=0):
    (n,) = struct.unpack_from("<I", body, off)
    return body[off + 4: off + 4 + n - 1].decode(errors="replace"), off + 4 + n + (-n % 4)

def main():
    c = Conn()
    registry = c.new_id()
    c.send(1, 1, struct.pack("<I", registry))            # wl_display.get_registry
    sync1 = c.new_id()
    c.send(1, 0, struct.pack("<I", sync1))               # wl_display.sync

    list_obj = None
    handles = {}                                          # id → datos
    sync2 = None
    for obj, op, body in c.events():
        if obj == registry and op == 0:                   # wl_registry.global
            (name,) = struct.unpack_from("<I", body)
            iface, off = read_string(body, 4)
            (version,) = struct.unpack_from("<I", body, off)
            if iface == "ext_foreign_toplevel_list_v1":
                list_obj = c.new_id()
                c.send(registry, 0, struct.pack("<I", name) + wl_string(iface)
                       + struct.pack("<II", min(version, 1), list_obj))
        elif obj == sync1 and op == 0:                    # primer roundtrip: ya conocemos los globales
            if list_obj is None:
                print("[]")
                return 1
            sync2 = c.new_id()
            c.send(1, 0, struct.pack("<I", sync2))
        elif obj == list_obj and op == 0:                 # toplevel(new_id)
            (hid,) = struct.unpack_from("<I", body)
            handles[hid] = {"identifier": "", "app_id": "", "title": ""}
        elif obj in handles:
            if op == 2:
                handles[obj]["title"] = read_string(body)[0]
            elif op == 3:
                handles[obj]["app_id"] = read_string(body)[0]
            elif op == 4:
                handles[obj]["identifier"] = read_string(body)[0]
        elif sync2 is not None and obj == sync2 and op == 0:
            break                                         # segundo roundtrip: lista completa

    wins = [h for h in handles.values() if h["identifier"]]

    if len(sys.argv) >= 3 and sys.argv[1] == "--capture":
        out_dir = sys.argv[2]
        os.makedirs(out_dir, exist_ok=True)
        procs = []
        for i, w in enumerate(wins):
            f = os.path.join(out_dir, "win-%d.png" % i)
            procs.append((w, f, subprocess.Popen(["grim", "-T", w["identifier"], f],
                                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)))
        for w, f, p in procs:
            if p.wait(timeout=10) == 0 and os.path.exists(f):
                w["file"] = f
        wins = [w for w in wins if "file" in w]   # solo las que se pudieron capturar

    print(json.dumps(wins, ensure_ascii=False))
    return 0

if __name__ == "__main__":
    sys.exit(main())
