#!/usr/bin/env python3
"""List listening TCP sockets from /proc (no ss/lsof needed): one line per socket: <port> <pid|-> <cwd|->."""
import os, sys

def listening():
    ports = {}   # inode -> port
    for f in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            rows = open(f).read().splitlines()[1:]
        except OSError:
            continue
        for r in rows:
            c = r.split()
            if c[3] == "0A":   # LISTEN
                ports[c[9]] = int(c[1].rsplit(":", 1)[1], 16)
    return ports

def owners(inodes):
    found = {}
    for p in filter(str.isdigit, os.listdir("/proc")):
        try:
            for fd in os.listdir(f"/proc/{p}/fd"):
                t = os.readlink(f"/proc/{p}/fd/{fd}")
                if t.startswith("socket:[") and t[8:-1] in inodes:
                    found.setdefault(t[8:-1], p)
        except OSError:
            continue
    return found

if __name__ == "__main__":
    ino = listening()
    own = owners(ino) if ino else {}
    for i, port in sorted(ino.items(), key=lambda x: x[1]):
        pid = own.get(i)
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd") if pid else "-"
        except OSError:
            cwd = "-"
        print(port, pid or "-", cwd)
