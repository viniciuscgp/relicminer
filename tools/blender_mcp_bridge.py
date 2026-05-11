from __future__ import annotations

import argparse
import json
import socket
from pathlib import Path


HOST = "localhost"
PORT = 9876


def receive_full_response(sock: socket.socket, buffer_size: int = 8192) -> dict:
    chunks: list[bytes] = []
    sock.settimeout(180.0)

    while True:
        chunk = sock.recv(buffer_size)
        if not chunk:
            break
        chunks.append(chunk)
        try:
            raw = b"".join(chunks).decode("utf-8", errors="replace").rstrip("\x00\r\n\t ")
            return json.loads(raw)
        except json.JSONDecodeError:
            continue

    raw = b"".join(chunks).decode("utf-8", errors="replace").rstrip("\x00\r\n\t ")
    raise RuntimeError(f"Incomplete response from Blender MCP socket: {raw!r}")


def send_command(command_type: str, params: dict | None = None) -> dict:
    payload = {"type": command_type, "params": params or {}}
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.connect((HOST, PORT))
        sock.sendall(json.dumps(payload).encode("utf-8"))
        response = receive_full_response(sock)
    return response


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command")
    parser.add_argument("--params", default="{}")
    parser.add_argument("--code-file")
    args = parser.parse_args()

    params = json.loads(args.params)
    if args.code_file:
        params["code"] = Path(args.code_file).read_text(encoding="utf-8")

    response = send_command(args.command, params)
    print(json.dumps(response, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
