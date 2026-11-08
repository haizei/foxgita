"""Contract tests use a deterministic provider; they do not claim OMR accuracy."""
import base64
import io
import json
import sqlite3
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from PIL import Image

from service import JobStore, QwenProvider, RecognitionServer, validate_pages


def page(color="white"):
    data = io.BytesIO()
    Image.new("RGB", (32, 32), color).save(data, "JPEG")
    return base64.b64encode(data.getvalue()).decode()


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.calls = 0
        self.release = threading.Event()

        def provider(pages):
            self.calls += 1
            self.release.wait(3)
            return {"title": "测试谱", "bars": [{"number": 1, "events": []}]}

        self.jobs = JobStore(Path(self.directory.name) / "jobs.sqlite", provider, workers=1, capacity=2)
        self.server = RecognitionServer(("127.0.0.1", 0), self.jobs, {"test-token": "owner-a", "second-token": "owner-b"})
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = "http://127.0.0.1:" + str(self.server.server_port)

    def tearDown(self):
        self.release.set()
        self.server.shutdown()
        self.server.server_close()
        self.jobs.close()
        self.directory.cleanup()

    def request(self, method, path, body=None, token="test-token", key="source-1"):
        payload = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self.base + path, data=payload, method=method,
                                         headers={"Authorization": "Bearer " + token, "Idempotency-Key": key,
                                                  "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=3) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            with error:
                return error.code, json.load(error)

    def test_authorization_and_owner_isolation(self):
        self.assertEqual(self.request("POST", "/v1/recognitions", {"pages": [page()]}, token="wrong")[0], 401)
        status, job = self.request("POST", "/v1/recognitions", {"pages": [page()]})
        self.assertEqual(status, 202)
        path = "/v1/recognitions/" + job["id"]
        self.assertEqual(self.request("GET", path, token="second-token")[0], 404)
        self.assertEqual(self.request("DELETE", path, token="second-token")[0], 404)

    def test_idempotent_retry_returns_same_task_and_real_result(self):
        body = {"pages": [page()]}
        _, first = self.request("POST", "/v1/recognitions", body)
        _, second = self.request("POST", "/v1/recognitions", body)
        self.assertEqual(first["id"], second["id"])
        self.release.set()
        path = "/v1/recognitions/" + first["id"]
        for _ in range(100):
            _, result = self.request("GET", path)
            if result["status"] == "succeeded":
                break
            time.sleep(0.01)
        self.assertEqual(result["draft"]["title"], "测试谱")
        self.assertEqual(self.calls, 1)

    def test_restart_recovers_checkpoint_and_same_key_retries_only_unfinished_page(self):
        second_started = threading.Event()
        images = [page(), page("black")]
        pages = validate_pages(images)
        draft = {"title": "checkpoint", "bars": [{"number": 1, "events": []}]}

        def interrupted_provider(batch):
            if batch == [pages[1]]:
                second_started.set()
                self.release.wait(3)
            return draft

        self.jobs.provider = interrupted_provider
        _, job = self.request("POST", "/v1/recognitions", {"pages": images})
        self.assertTrue(second_started.wait(2))
        # Snapshot durable state at the instant the worker loses its process.
        checkpoint = Path(self.directory.name) / "checkpoint.sqlite"
        snapshot = sqlite3.connect(checkpoint)
        try:
            with self.jobs.lock:
                self.jobs.db.backup(snapshot)
        finally:
            snapshot.close()
            self.release.set()

        retried_pages = []

        def resumed_provider(batch):
            retried_pages.extend(batch)
            return draft

        restored = JobStore(checkpoint, resumed_provider, workers=1)
        try:
            self.assertEqual(restored.get("owner-a", job["id"])["status"], "failed")
            retry = restored.submit("owner-a", "source-1", pages)
            self.assertEqual(retry["id"], job["id"])
            for _ in range(100):
                result = restored.get("owner-a", job["id"])
                if result["status"] == "succeeded":
                    break
                time.sleep(0.01)
            self.assertEqual(result["status"], "succeeded")
            self.assertEqual(restored.submit("owner-a", "source-1", pages), result)
            self.assertEqual(retried_pages, pages[1:])
            self.assertEqual([bar["source"]["page"] for bar in result["draft"]["bars"]], [1, 2])
        finally:
            restored.close()

    def test_cancelled_job_cannot_be_resurrected_by_late_provider(self):
        body = {"pages": [page()]}
        _, job = self.request("POST", "/v1/recognitions", body)
        path = "/v1/recognitions/" + job["id"]
        self.assertEqual(self.request("DELETE", path)[1]["status"], "cancelled")
        self.release.set()
        time.sleep(0.04)
        self.assertEqual(self.request("GET", path)[1]["status"], "cancelled")
        _, retry = self.request("POST", "/v1/recognitions", body)
        self.assertEqual(retry["id"], job["id"])

    def test_audio_and_invalid_image_are_rejected(self):
        self.assertEqual(self.request("POST", "/v1/recognitions", {"pages": [page()], "audio": "data"})[0], 400)
        self.assertEqual(self.request("POST", "/v1/recognitions", {"pages": ["YXVkaW8="]})[0], 400)
        with self.assertRaises(ValueError):
            validate_pages([page()] * 21)

    def test_capacity_is_bounded_and_different_content_conflicts(self):
        body = {"pages": [page()]}
        self.assertEqual(self.request("POST", "/v1/recognitions", body, key="a")[0], 202)
        self.assertEqual(self.request("POST", "/v1/recognitions", body, key="b")[0], 202)
        self.assertEqual(self.request("POST", "/v1/recognitions", body, key="c")[0], 429)
        different = io.BytesIO()
        Image.new("RGB", (40, 40), "black").save(different, "JPEG")
        self.assertEqual(self.request("POST", "/v1/recognitions", {"pages": [base64.b64encode(different.getvalue()).decode()]}, key="a")[0], 409)

    def test_cancelling_queued_task_immediately_releases_its_slot(self):
        body = {"pages": [page()]}
        self.request("POST", "/v1/recognitions", body, key="active")
        _, queued = self.request("POST", "/v1/recognitions", body, key="pending")
        self.request("DELETE", "/v1/recognitions/" + queued["id"])
        self.assertEqual(self.request("POST", "/v1/recognitions", body, key="replacement")[0], 202)

    def test_page_failure_retry_reuses_successful_pages_and_preserves_source_page(self):
        attempts = {"white":0,"black":0}
        def provider(pages):
            color = "white" if Image.open(io.BytesIO(pages[0])).getpixel((0,0))[0] > 128 else "black"
            attempts[color] += 1
            if color == "black" and attempts[color] == 1: raise ValueError("page unreadable")
            return {"title":"test","bars":[{"number":1,"events":[]}]}
        self.jobs.provider = provider
        body = {"pages":[page(),page("black")]}
        _, job = self.request("POST","/v1/recognitions",body)
        path = "/v1/recognitions/" + job["id"]
        for _ in range(100):
            _, result = self.request("GET",path)
            if result["status"] == "failed": break
            time.sleep(0.01)
        self.assertEqual([p["status"] for p in result["pages"]],["succeeded","failed"])
        self.request("POST","/v1/recognitions",body)
        for _ in range(100):
            _, result = self.request("GET",path)
            if result["status"] == "succeeded": break
            time.sleep(0.01)
        self.assertEqual(attempts,{"white":1,"black":2})
        self.assertEqual([b["source"]["page"] for b in result["draft"]["bars"]],[1,2])


if __name__ == "__main__":
    unittest.main()
