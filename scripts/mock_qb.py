"""qBittorrent WebUI API v2 模擬伺服器（僅用於本機測試 App）。

依 qBittorrent 5.x 行為實作：SID cookie 登入、未登入回 403、Bearer API Key、
動作端點只接受 POST、sync/maindata rid 增量同步、409/415 等錯誤碼、主機標頭連接埠驗證（401）。

預設模擬 qBittorrent 5.2+：登入成功回 204（無內容）、帳密錯誤回 401、沒有回傳資料的操作回 204。
設定環境變數 MOCK_LEGACY=1 則模擬 5.1 以前：登入回 200「Ok.」／「Fails.」。
MOCK_FAIL=torrents/addTags,torrents/recheck 會讓列出的端點一律回 409，用來測試 App 的錯誤提示。

用法：python3 -I scripts/mock_qb.py [port] [host]   帳號 admin / adminadmin，API Key：qbt_testkey
      host 預設 127.0.0.1；要讓區域網路上的實機連線測試時，可指定本機的區網 IP。
"""
import copy, hashlib, json, os, random, re, secrets, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

USER, PASS, API_KEY = "admin", "adminadmin", "qbt_testkey"
LEGACY = os.environ.get("MOCK_LEGACY") == "1"
FAIL = {x.strip() for x in os.environ.get("MOCK_FAIL", "").split(",") if x.strip()}
LISTEN_PORT = 8080
lock = threading.Lock()
sessions = {}          # sid -> {"rid": int, "snap": dict}
now = int(time.time())

categories = {"電影": {"name": "電影", "savePath": "/data/movies"},
              "Linux": {"name": "Linux", "savePath": "/data/iso"}}
tags = {"4K", "高優先", "長期做種"}
alt_speed = False

def mk(name, size, state, progress, cat="", tg="", tracker="http://tracker.alpha.test:6969/announce", **kw):
    h = hashlib.sha1(name.encode()).hexdigest()
    t = {"hash": h, "name": name, "size": size, "total_size": size, "progress": progress, "state": state,
         "category": cat, "tags": tg, "tracker": tracker, "added_on": now - random.randint(3600, 90 * 86400),
         "completion_on": now - 3600 if progress >= 1 else -1, "dlspeed": 0, "upspeed": 0, "eta": 8640000,
         "ratio": round(random.uniform(0, 3), 3), "num_seeds": random.randint(0, 40), "num_complete": random.randint(10, 300),
         "num_leechs": random.randint(0, 20), "num_incomplete": random.randint(0, 100), "force_start": False,
         "seq_dl": False, "f_l_piece_prio": False, "auto_tmm": False, "super_seeding": False, "priority": 0,
         "save_path": "/data/downloads", "content_path": "/data/downloads/" + name, "dl_limit": 0, "up_limit": 0,
         "downloaded": int(size * progress), "uploaded": int(size * random.uniform(0, 2)), "availability": 1.0,
         "amount_left": int(size * (1 - progress)), "completed": int(size * progress), "time_active": random.randint(600, 900000),
         "seeding_time": random.randint(0, 500000), "last_activity": now - random.randint(0, 86400), "isPrivate": False,
         "magnet_uri": f"magnet:?xt=urn:btih:{h}&dn={name}", "trackers_count": 1}
    t.update(kw)
    return t

GB = 1024 ** 3
torrents = {t["hash"]: t for t in [
    mk("ubuntu-24.04.1-desktop-amd64.iso", int(5.7 * GB), "downloading", 0.42, "Linux", "高優先", dlspeed=8_400_000, upspeed=120_000, eta=420),
    mk("Big.Buck.Bunny.2008.1080p.BluRay.x264.mkv", int(2.1 * GB), "uploading", 1.0, "電影", "長期做種", upspeed=650_000),
    mk("Sintel.2010.2160p.HDR.HEVC.mkv", int(11.4 * GB), "stoppedDL", 0.18, "電影", "4K", tracker="http://open.beta.test/announce"),
    mk("debian-12.7.0-amd64-netinst.iso", 660 * 1024 ** 2, "stalledUP", 1.0, "Linux", "", tracker="http://open.beta.test/announce"),
    mk("archlinux-2026.10.01-x86_64.iso", int(1.2 * GB), "forcedDL", 0.77, "Linux", "高優先", force_start=True, dlspeed=15_200_000, eta=35),
    mk("Tears.of.Steel.2012.4K.mkv", int(6.3 * GB), "stalledDL", 0.05, "電影", "4K", tracker=""),
    mk("Elephants.Dream.2006.mp4", 812 * 1024 ** 2, "stoppedUP", 1.0, "", "長期做種"),
    mk("Cosmos.Laundromat.2015.1080p.mkv", int(1.6 * GB), "error", 0.63, "電影", "", tracker="http://tracker.gamma.test/announce"),
    mk("Fedora-Workstation-Live-41.iso", int(2.3 * GB), "queuedDL", 0.0, "Linux", ""),
    mk("Spring.2019.Blender.Open.Movie.mkv", int(3.4 * GB), "metaDL", 0.0, "", "", tracker="http://tracker.gamma.test/announce"),
]}
trackers_of = {h: ([t["tracker"]] if t["tracker"] else []) for h, t in torrents.items()}

def stopped(s): return s in ("stoppedDL", "stoppedUP", "pausedDL", "pausedUP")

def snapshot():
    trk = {}
    for h, urls in trackers_of.items():
        if h in torrents:
            for u in urls: trk.setdefault(u, []).append(h)
    dl = sum(t["dlspeed"] for t in torrents.values()); ul = sum(t["upspeed"] for t in torrents.values())
    return {"torrents": copy.deepcopy(torrents), "categories": copy.deepcopy(categories), "tags": sorted(tags),
            "trackers": trk, "server_state": {"dl_info_speed": dl, "up_info_speed": ul, "dl_info_data": 52 * GB,
            "up_info_data": 31 * GB, "free_space_on_disk": 812 * GB, "use_alt_speed_limits": alt_speed,
            "connection_status": "connected", "dht_nodes": 312, "total_peer_connections": 57, "global_ratio": "1.42",
            "alltime_dl": 3200 * GB, "alltime_ul": 4100 * GB, "dl_rate_limit": 0, "up_rate_limit": 0, "queueing": True}}

def maindata(sid, rid):
    s = sessions.setdefault(sid, {"rid": 0, "snap": None})
    cur = snapshot()
    prev = s["snap"]
    s["rid"] += 1
    out = {"rid": s["rid"]}
    if not rid or prev is None or rid != s.get("sent_rid"):
        out.update(full_update=True, **cur)
    else:
        ch = {}
        for h, t in cur["torrents"].items():
            old = prev["torrents"].get(h)
            if old is None: ch[h] = t
            else:
                d = {k: v for k, v in t.items() if old.get(k) != v}
                if d: ch[h] = d
        if ch: out["torrents"] = ch
        rem = [h for h in prev["torrents"] if h not in cur["torrents"]]
        if rem: out["torrents_removed"] = rem
        cc = {k: v for k, v in cur["categories"].items() if prev["categories"].get(k) != v}
        if cc: out["categories"] = cc
        cr = [k for k in prev["categories"] if k not in cur["categories"]]
        if cr: out["categories_removed"] = cr
        ta = [t for t in cur["tags"] if t not in prev["tags"]]
        if ta: out["tags"] = ta
        tr = [t for t in prev["tags"] if t not in cur["tags"]]
        if tr: out["tags_removed"] = tr
        tc = {u: hs for u, hs in cur["trackers"].items() if prev["trackers"].get(u) != hs}
        if tc: out["trackers"] = tc
        trr = [u for u in prev["trackers"] if u not in cur["trackers"]]
        if trr: out["trackers_removed"] = trr
        ss = {k: v for k, v in cur["server_state"].items() if prev["server_state"].get(k) != v}
        if ss: out["server_state"] = ss
    s["snap"] = cur; s["sent_rid"] = s["rid"]
    return out

def tick():
    while True:
        time.sleep(1)
        with lock:
            for t in torrents.values():
                if t["state"] in ("downloading", "forcedDL"):
                    t["progress"] = min(1.0, t["progress"] + t["dlspeed"] / max(t["size"], 1))
                    t["dlspeed"] = max(500_000, int(t["dlspeed"] * random.uniform(0.85, 1.15)))
                    left = int(t["size"] * (1 - t["progress"]))
                    t.update(amount_left=left, completed=t["size"] - left, downloaded=t["size"] - left,
                             eta=int(left / t["dlspeed"]) if t["dlspeed"] else 8640000)
                    if t["progress"] >= 1:
                        t.update(state="forcedUP" if t["force_start"] else "uploading", dlspeed=0, eta=8640000,
                                 completion_on=int(time.time()), amount_left=0)
                if t["state"] in ("uploading", "forcedUP"):
                    t["upspeed"] = max(20_000, int((t["upspeed"] or 300_000) * random.uniform(0.8, 1.2)))
                    t["uploaded"] += t["upspeed"]; t["ratio"] = round(t["uploaded"] / max(t["size"], 1), 3)
                if t["state"].startswith("checking"):
                    t["state"] = "stalledUP" if t["progress"] >= 1 else "stalledDL"

def resume(t):
    if t["progress"] >= 1: t.update(state="forcedUP" if t["force_start"] else "uploading")
    else: t.update(state="forcedDL" if t["force_start"] else "downloading", dlspeed=t["dlspeed"] or 3_000_000)

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, fmt, *a): sys.stderr.write("[mock] " + (fmt % a) + "\n")

    def reply(self, code=200, body=b"", ctype="text/plain; charset=UTF-8", cookie=None):
        if isinstance(body, str): body = body.encode()
        if not isinstance(body, bytes): body = json.dumps(body, ensure_ascii=False).encode(); ctype = "application/json"
        self.send_response(code)
        self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body)))
        if cookie: self.send_header("Set-Cookie", f"QBT_SID_8080={cookie}; HttpOnly; SameSite=Strict; path=/")
        self.end_headers(); self.wfile.write(body)

    def sid(self):
        m = re.search(r"QBT_SID_8080=([A-Za-z0-9]+)", self.headers.get("Cookie", ""))
        return m.group(1) if m and m.group(1) in sessions else None

    def csrf_bad(self):
        host = self.headers.get("Host", "")
        for h in ("Origin", "Referer"):
            v = self.headers.get(h)
            if v and urlparse(v).netloc != host: return True
        return False

    def do_GET(self): self.handle_req("GET")
    def do_POST(self): self.handle_req("POST")

    def handle_req(self, method):
        u = urlparse(self.path)
        path = u.path.split("/api/v2/", 1)[-1] if "/api/v2/" in u.path else None
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        if path is None: return self.reply(404, "Not Found")
        # 與 qBittorrent 相同：Host 標頭帶的連接埠與實際監聽的連接埠不同時回 401（主機標頭驗證）
        hp = urlparse("//" + self.headers.get("Host", "")).port
        if hp is not None and hp != LISTEN_PORT: return self.reply(401, "Unauthorized")
        if self.csrf_bad(): return self.reply(401, "Unauthorized")
        q = {k: v[-1] for k, v in parse_qs(u.query, keep_blank_values=True).items()}
        form, files = {}, []
        ctype = self.headers.get("Content-Type", "")
        if "application/x-www-form-urlencoded" in ctype:
            form = {k: v[-1] for k, v in parse_qs(raw.decode(), keep_blank_values=True).items()}
        elif "multipart/form-data" in ctype:
            b = ctype.split("boundary=")[1].encode()
            for part in raw.split(b"--" + b)[1:-1]:
                head, _, body = part.partition(b"\r\n\r\n"); body = body[:-2]
                name = re.search(rb'name="([^"]+)"', head).group(1).decode()
                fn = re.search(rb'filename="([^"]*)"', head)
                if fn: files.append((fn.group(1).decode(), body))
                else: form[name] = body.decode()
        p = {**q, **form}

        if path == "auth/login":
            if method != "POST": return self.reply(405, "Method Not Allowed")
            if p.get("username") == USER and p.get("password") == PASS:
                s = secrets.token_hex(16); sessions[s] = {"rid": 0, "snap": None}
                return self.reply(200, "Ok.", cookie=s) if LEGACY else self.reply(204, cookie=s)
            return self.reply(200, "Fails.") if LEGACY else self.reply(401, "Unauthorized")
        auth = self.headers.get("Authorization", "")
        sid = self.sid()
        if auth == f"Bearer {API_KEY}": sid = sid or "apikey"
        if not sid: return self.reply(403, "Forbidden")
        if path == "auth/logout": sessions.pop(sid, None); return self.reply(200)

        readonly = {"app/webapiVersion", "app/version", "sync/maindata", "torrents/info", "torrents/files",
                    "torrents/trackers", "torrents/properties", "torrents/categories", "torrents/tags", "transfer/info"}
        if path not in readonly and method != "POST": return self.reply(405, "Method Not Allowed")
        if path in FAIL: return self.reply(409, "Mock failure")

        global alt_speed
        with lock:
            hs = p.get("hashes", "")
            sel = list(torrents) if hs == "all" else [h for h in hs.split("|") if h in torrents]
            if path == "app/webapiVersion": return self.reply(200, "2.11.4" if LEGACY else "2.14.1")
            if path == "app/version": return self.reply(200, "v5.1.2" if LEGACY else "v5.2.3")
            if path == "sync/maindata": return self.reply(200, maindata(sid, int(p.get("rid", 0) or 0)))
            if path == "torrents/info": return self.reply(200, list(torrents.values()))
            if path in ("torrents/files", "torrents/trackers", "torrents/properties"):
                t = torrents.get(p.get("hash", ""))
                if not t: return self.reply(404, "Not Found")
                if path == "torrents/files":
                    pr = t.setdefault("_prio", [1, 1, 6, 0])
                    names = [f"{t['name']}/{t['name']}", f"{t['name']}/Subs/zh-Hant.srt", f"{t['name']}/Sample/sample.mkv", f"{t['name']}/README.txt"]
                    sizes = [int(t["size"] * 0.97), 120_000, int(t["size"] * 0.03) - 124_000, 4000]
                    return self.reply(200, [{"index": i, "name": n, "size": s, "progress": t["progress"] if pr[i] else 0,
                                             "priority": pr[i], "availability": 1} for i, (n, s) in enumerate(zip(names, sizes))])
                if path == "torrents/trackers":
                    base = [{"url": "** [DHT] **", "status": 2, "tier": -1, "num_peers": 12, "num_seeds": 0, "num_leeches": 0, "num_downloaded": 0, "msg": ""},
                            {"url": "** [PeX] **", "status": 2, "tier": -1, "num_peers": 3, "num_seeds": 0, "num_leeches": 0, "num_downloaded": 0, "msg": ""}]
                    for u in trackers_of.get(t["hash"], []):
                        bad = "gamma" in u
                        base.append({"url": u, "status": 4 if bad else 2, "tier": 0, "num_peers": t["num_seeds"] + t["num_leechs"],
                                     "num_seeds": t["num_seeds"], "num_leeches": t["num_leechs"], "num_downloaded": 812,
                                     "msg": "Connection timed out" if bad else ""})
                    return self.reply(200, base)
                return self.reply(200, {"save_path": t["save_path"], "creation_date": t["added_on"] - 86400, "piece_size": 4194304,
                                        "comment": "Blender Foundation open movie test", "total_wasted": 1_048_576, "nb_connections": 23,
                                        "pieces_num": t["size"] // 4194304 + 1, "pieces_have": int((t["size"] // 4194304 + 1) * t["progress"]),
                                        "created_by": "qBittorrent v5.2.3", "is_private": False})
            if path in ("torrents/start", "torrents/resume"):
                for h in sel: resume(torrents[h])
            elif path in ("torrents/stop", "torrents/pause"):
                for h in sel:
                    t = torrents[h]; t.update(state="stoppedUP" if t["progress"] >= 1 else "stoppedDL", dlspeed=0, upspeed=0, eta=8640000)
            elif path == "torrents/setForceStart":
                v = p.get("value") == "true"
                for h in sel:
                    t = torrents[h]; t["force_start"] = v
                    if v or not stopped(t["state"]): resume(t)
            elif path == "torrents/delete":
                for h in sel: torrents.pop(h, None)
            elif path == "torrents/recheck":
                for h in sel: torrents[h]["state"] = "checkingUP" if torrents[h]["progress"] >= 1 else "checkingDL"
            elif path == "torrents/reannounce": pass
            elif path == "torrents/setCategory":
                c = p.get("category", "")
                if c and c not in categories: return self.reply(409, "Incorrect category name")
                for h in sel: torrents[h]["category"] = c
            elif path == "torrents/createCategory":
                c = p.get("category", "")
                if not c: return self.reply(400, "Category name cannot be empty")
                categories[c] = {"name": c, "savePath": p.get("savePath", "")}
            elif path in ("torrents/addTags", "torrents/removeTags"):
                new = [x.strip() for x in p.get("tags", "").split(",") if x.strip()]
                for h in sel:
                    cur = [x for x in torrents[h]["tags"].split(", ") if x]
                    cur = sorted(set(cur) | set(new)) if path.endswith("addTags") else [x for x in cur if x not in new]
                    torrents[h]["tags"] = ", ".join(cur)
                if path.endswith("addTags"): tags.update(new)
            elif path == "torrents/createTags":
                tags.update(x.strip() for x in p.get("tags", "").split(",") if x.strip())
            elif path == "torrents/setLocation":
                for h in sel: torrents[h]["save_path"] = p.get("location", "")
            elif path == "torrents/rename":
                t = torrents.get(p.get("hash", ""))
                if not t: return self.reply(404, "Not Found")
                t["name"] = p.get("name", t["name"])
            elif path in ("torrents/topPrio", "torrents/bottomPrio", "torrents/increasePrio", "torrents/decreasePrio"): pass
            elif path == "torrents/toggleSequentialDownload":
                for h in sel: torrents[h]["seq_dl"] = not torrents[h]["seq_dl"]
            elif path == "torrents/toggleFirstLastPiecePrio":
                for h in sel: torrents[h]["f_l_piece_prio"] = not torrents[h]["f_l_piece_prio"]
            elif path == "torrents/filePrio":
                t = torrents.get(p.get("hash", ""))
                if not t: return self.reply(404, "Not Found")
                pr = t.setdefault("_prio", [1, 1, 6, 0])
                for i in p.get("id", "").split("|"): pr[int(i)] = int(p.get("priority", 1))
            elif path == "torrents/add":
                urls = [x for x in p.get("urls", "").splitlines() if x.strip()]
                if not urls and not files: return self.reply(415, "Torrent file is not valid")
                for i, src in enumerate(urls + [f[0] for f in files]):
                    m = re.search(r"dn=([^&]+)", src)
                    name = m.group(1) if m else src.rsplit("/", 1)[-1].replace(".torrent", "") or f"new-{i}"
                    st = "stoppedDL" if p.get("stopped") == "true" or p.get("paused") == "true" else "metaDL"
                    t = mk(name, int(1.5 * GB), st, 0.0, p.get("category", ""), ", ".join(x for x in p.get("tags", "").split(",") if x))
                    t["added_on"] = int(time.time()); torrents[t["hash"]] = t; trackers_of[t["hash"]] = [t["tracker"]]
                return self.reply(200, "Ok.")
            elif path == "transfer/toggleSpeedLimitsMode": alt_speed = not alt_speed
            else: return self.reply(404, "Not Found")
            return self.reply(200, "") if LEGACY else self.reply(204)

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    LISTEN_PORT = port
    threading.Thread(target=tick, daemon=True).start()
    mode = "qBittorrent ≤ 5.1" if LEGACY else "qBittorrent 5.2+"
    print(f"mock {mode} on http://{host}:{port}  (admin/adminadmin, API key {API_KEY})", flush=True)
    ThreadingHTTPServer((host, port), H).serve_forever()
