"""Speak MCP over stdio to the given command and print the tool names (one per line)."""
import json
import os
import subprocess
import sys

proc = subprocess.Popen(sys.argv[1:], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)


def send(msg):
    proc.stdin.write(json.dumps(msg) + "\n")
    proc.stdin.flush()


def recv(want_id):
    for line in proc.stdout:
        msg = json.loads(line)
        if msg.get("id") == want_id:
            return msg
    sys.exit("server closed stdout")


send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
    "protocolVersion": "2025-06-18", "capabilities": {},
    "clientInfo": {"name": "smoke", "version": "0"}}})
recv(1)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})
send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
tools = recv(2)["result"]["tools"]
for t in sorted(tools, key=lambda t: t["name"]):
    print(t["name"], "ro" if (t.get("annotations") or {}).get("readOnlyHint") else "rw")
if os.environ.get("MCP_CALL"):
    send({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": json.loads(os.environ["MCP_CALL"])})
    print("CALL", json.dumps(recv(3).get("result")))
proc.terminate()
