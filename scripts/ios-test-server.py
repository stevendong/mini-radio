#!/usr/bin/env python3
"""Serve silent PCM audio locally for real AVPlayer simulator tests."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import wave

folder = Path("artifacts/ios-audio-fixture")
folder.mkdir(parents=True, exist_ok=True)
with wave.open(str(folder / "tone.wav"), "wb") as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(8000)
    output.writeframes(b"\x00\x00" * 8000 * 120)
ThreadingHTTPServer(("127.0.0.1", 18767), partial(SimpleHTTPRequestHandler, directory=str(folder))).serve_forever()
