import io
import json
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from PIL import Image
from service import QwenProvider, validate_draft


class ProviderTests(unittest.TestCase):
    def test_openai_compatible_request_passes_actual_pages_and_decodes_json(self):
        received = []

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                received.append((self.path, self.headers["Authorization"], body))
                draft = {"title": "来自服务商的曲谱", "bars": [{"number": 1, "events": []}]}
                data = json.dumps({"choices": [{"message": {"content": json.dumps(draft)}}]}).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            provider = QwenProvider(f"http://127.0.0.1:{server.server_port}/v1", "test-vision", "test-only", "score prompt")
            data = io.BytesIO()
            Image.new("RGB", (32, 32)).save(data, "JPEG")
            self.assertEqual(provider([data.getvalue()])["title"], "来自服务商的曲谱")
            path, auth, body = received[0]
            self.assertEqual(path, "/v1/chat/completions")
            self.assertEqual(auth, "Bearer test-only")
            self.assertEqual(body["model"], "test-vision")
            content = body["messages"][1]["content"]
            self.assertTrue(content[1]["image_url"]["url"].startswith("data:image/jpeg;base64,"))
            self.assertNotIn("audio", json.dumps(body))
        finally:
            server.shutdown()
            server.server_close()

    def test_error_response_or_unsafe_shape_cannot_become_a_score(self):
        for value in [{"error": "unable to read"}, {"title": "x", "bars": []}, {"title": "x", "bars": [None]},
                      {"title":"x","bars":[{"events":[{"tick":0,"duration":960,"tones":[60,64,67]}]}]}]:
            with self.assertRaises(ValueError):
                validate_draft(value)
        with self.assertRaises(ValueError):
            QwenProvider("http://external.example/v1", "model", "key", "prompt")

    def test_total_deadline_aborts_a_trickling_provider(self):
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args): pass
            def do_POST(self):
                self.rfile.read(int(self.headers["Content-Length"]))
                self.send_response(200); self.send_header("Content-Length", "1000"); self.end_headers()
                try:
                    for _ in range(100):
                        self.wfile.write(b" "); self.wfile.flush(); time.sleep(0.04)
                except (ConnectionError, OSError): pass
        server = ThreadingHTTPServer(("127.0.0.1",0),Handler)
        threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
            provider = QwenProvider(f"http://127.0.0.1:{server.server_port}","model","test-only","prompt",total_timeout=0.4)
            started = time.monotonic()
            with self.assertRaises(TimeoutError): provider([b"test-page"])
            self.assertLess(time.monotonic()-started,1.5)
        finally:
            server.shutdown(); server.server_close()


if __name__ == "__main__":
    unittest.main()
