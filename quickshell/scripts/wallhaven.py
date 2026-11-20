#!/usr/bin/env python3
"""Ayudante de Wallhaven para el selector de fondos de Quickshell (sin dependencias).

  wallhaven.py search '<json>'   → busca y descarga las miniaturas que falten (caché); imprime JSON
  wallhaven.py download ID URL   → descarga la imagen completa a ~/Pictures/Wallpapers
                                   (imprime "P bytes total" mientras descarga y "OK ruta" al final)

Solo contenido apto (purity=100). Las miniaturas se guardan en ~/.cache/quickshell/wallhaven/
y nunca se vuelven a descargar. Cada respuesta incluye "bytes": lo que se gastó de datos.
"""
import json
import os
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://wallhaven.cc/api/v1/search"
UA = {"User-Agent": "quickshell-wallpaper-picker"}
HOME = os.path.expanduser("~")
CACHE = os.path.join(HOME, ".cache/quickshell/wallhaven")
WALLS = os.path.join(HOME, "Pictures/Wallpapers")


def get(url, timeout=20):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return r.read()


def thumb(item):
    """Miniatura en caché; devuelve (ruta, bytes descargados)."""
    f = os.path.join(CACHE, item["id"] + ".jpg")
    if os.path.exists(f) and os.path.getsize(f) > 0:
        return f, 0
    try:
        data = get(item["thumbs"]["large"], timeout=15)
        with open(f + ".part", "wb") as fh:
            fh.write(data)
        os.replace(f + ".part", f)
        return f, len(data)
    except Exception:
        return "", 0


def local_path(item):
    ext = item["path"].rsplit(".", 1)[-1]
    return os.path.join(WALLS, "wallhaven-%s.%s" % (item["id"], ext))


def search(opts):
    os.makedirs(CACHE, exist_ok=True)
    params = {
        "q": opts.get("q", ""),
        "categories": opts.get("categories", "110"),     # general, anime, personas
        "purity": "100",                                  # solo contenido apto
        "sorting": opts.get("sorting", "toplist"),
        "order": "desc",
        "atleast": opts.get("atleast", "1920x1080"),
        "ratios": opts.get("ratios", "16x9,16x10"),
        "page": str(opts.get("page", 1)),
    }
    if params["sorting"] == "toplist":
        params["topRange"] = opts.get("topRange", "1M")
    if opts.get("seed"):
        params["seed"] = opts["seed"]
    url = API + "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v != ""})
    raw = get(url)
    data = json.loads(raw)
    items = data.get("data", [])
    with ThreadPoolExecutor(max_workers=6) as pool:
        thumbs = list(pool.map(thumb, items))
    out = []
    for it, (t, _) in zip(items, thumbs):
        lp = local_path(it)
        out.append({
            "id": it["id"],
            "thumb": t,
            "url": it["path"],
            "resolution": it["resolution"],
            "size": it["file_size"],
            "category": it["category"],
            "colors": it.get("colors", []),
            "favorites": it.get("favorites", 0),
            "local": lp if os.path.exists(lp) else "",
        })
    meta = data.get("meta", {})
    return {
        "items": out,
        "page": meta.get("current_page", 1),
        "lastPage": meta.get("last_page", 1),
        "total": meta.get("total", 0),
        "seed": meta.get("seed"),
        "bytes": len(raw) + sum(b for _, b in thumbs),
    }


def download(wid, url):
    os.makedirs(WALLS, exist_ok=True)
    ext = url.rsplit(".", 1)[-1]
    dest = os.path.join(WALLS, "wallhaven-%s.%s" % (wid, ext))
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        print("OK", dest, flush=True)
        return
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r, open(dest + ".part", "wb") as fh:
        total = int(r.headers.get("Content-Length", 0))
        done = 0
        while True:
            chunk = r.read(65536)
            if not chunk:
                break
            fh.write(chunk)
            done += len(chunk)
            print("P", done, total, flush=True)
    os.replace(dest + ".part", dest)
    print("OK", dest, flush=True)


if __name__ == "__main__":
    try:
        if sys.argv[1] == "search":
            print(json.dumps(search(json.loads(sys.argv[2]) if len(sys.argv) > 2 else {})))
        elif sys.argv[1] == "download":
            download(sys.argv[2], sys.argv[3])
    except Exception as e:
        if sys.argv[1] == "search":
            print(json.dumps({"error": str(e)}))
        else:
            print("ERR", e, flush=True)
        sys.exit(1)
