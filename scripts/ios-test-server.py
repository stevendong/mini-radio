#!/usr/bin/env python3
"""Serve silent PCM audio locally for real AVPlayer simulator tests."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import wave

folder = Path("artifacts/ios-audio-fixture")
folder.mkdir(parents=True, exist_ok=True)
with wave.open(str(folder / "tone.wav"), "wb") as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(8000)
    output.writeframes(b"\x00\x00" * 8000 * 120)
audio = (folder / "tone.wav").read_bytes()

class AudioHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_HEAD(self):
        self.send_audio(head=True)

    def do_GET(self):
        self.send_audio(head=False)

    def send_audio(self, head):
        if self.path != "/tone.wav":
            self.send_error(404)
            return
        start, end = 0, len(audio) - 1
        requested = self.headers.get("Range")
        if requested:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", requested.strip())
            if not match or not any(match.groups()):
                self.send_error(400)
                return
            first, last = match.groups()
            if first:
                start = int(first)
                end = min(int(last), end) if last else end
            else:
                start = max(0, len(audio) - int(last))
            if start > end or start >= len(audio):
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{len(audio)}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
        self.send_response(206 if requested else 200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        if requested:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(audio)}")
        self.send_header("Connection", "close")
        self.end_headers()
        if not head:
            try:
                self.wfile.write(audio[start:end + 1])
            except (BrokenPipeError, ConnectionResetError):
                pass

ThreadingHTTPServer(("127.0.0.1", 18767), AudioHandler).serve_forever()
