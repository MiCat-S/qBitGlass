"""本機測試用代理（只監聽 127.0.0.1），用來確認 App 的「經由代理連線」真的經過代理。

同一個連接埠同時支援 HTTP CONNECT 與 SOCKS5，每個連線的目標都會印出來，例如：
  CONNECT 127.0.0.1:8080
  SOCKS5 127.0.0.1:8080

用法：python3 -I scripts/test_proxy.py [port]   預設 18888
"""
import socket, struct, sys, threading


def recv_exact(c, n):
    buf = b""
    while len(buf) < n:
        chunk = c.recv(n - len(buf))
        if not chunk: raise ConnectionError("closed")
        buf += chunk
    return buf


def pipe(a, b):
    try:
        while (d := a.recv(65536)):
            b.sendall(d)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try: s.shutdown(socket.SHUT_RDWR)
            except OSError: pass


def relay(c, host, port):
    u = socket.create_connection((host, port), timeout=10)
    u.settimeout(None)
    threading.Thread(target=pipe, args=(c, u), daemon=True).start()
    pipe(u, c)


def socks5(c):
    _, n = recv_exact(c, 2)
    recv_exact(c, n)
    c.sendall(b"\x05\x00")                       # 不需驗證
    _, cmd, _, atyp = recv_exact(c, 4)
    if atyp == 1: host = socket.inet_ntoa(recv_exact(c, 4))
    elif atyp == 3: host = recv_exact(c, recv_exact(c, 1)[0]).decode()
    else: host = socket.inet_ntop(socket.AF_INET6, recv_exact(c, 16))
    port = struct.unpack(">H", recv_exact(c, 2))[0]
    print(f"SOCKS5 {host}:{port}", flush=True)
    if cmd != 1:
        return c.sendall(b"\x05\x07\x00\x01" + b"\0" * 6)
    c.sendall(b"\x05\x00\x00\x01" + b"\0" * 6)
    relay(c, host, port)


def http_connect(c):
    head = b""
    while b"\r\n\r\n" not in head:
        chunk = c.recv(4096)
        if not chunk: return
        head += chunk
    method, target = head.split(b"\r\n", 1)[0].decode().split(" ")[:2]
    if method != "CONNECT":
        return c.sendall(b"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n")
    print(f"CONNECT {target}", flush=True)
    host, _, port = target.rpartition(":")
    c.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
    relay(c, host.strip("[]"), int(port))


def handle(c):
    try:
        if c.recv(1, socket.MSG_PEEK) == b"\x05": socks5(c)
        else: http_connect(c)
    except (OSError, ValueError, ConnectionError):
        pass
    finally:
        c.close()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18888
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port))
    srv.listen(64)
    print(f"test proxy on 127.0.0.1:{port}", flush=True)
    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()
