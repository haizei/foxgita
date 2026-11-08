"""Gita page-only recognition service. Run behind a TLS reverse proxy.

Provider credentials remain on the server. No performance-audio endpoint exists.
SQLite stores job metadata/results; uploaded page bytes are never written to disk.
"""
from __future__ import annotations

import base64
import binascii
import hashlib
import hmac
import io
import json
import multiprocessing
import os
import sqlite3
import threading
import time
import uuid
import warnings
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

from PIL import Image

MAX_BODY = 40_100_000
MAX_RESULT = 4_000_000
TERMINAL = {"succeeded", "failed", "cancelled"}


def validate_pages(values):
    if not isinstance(values, list) or not 1 <= len(values) <= 20:
        raise ValueError("Invalid pages")
    pages, total = [], 0
    for value in values:
        if not isinstance(value, str) or len(value) > 40_000_000:
            raise ValueError("Invalid page")
        try:
            data = base64.b64decode(value, validate=True)
            total += len(data)
            if total > 30_000_000:
                raise ValueError("Too many bytes")
            with warnings.catch_warnings():
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(io.BytesIO(data)) as image:
                    if image.format not in {"JPEG", "PNG"} or image.width * image.height > 40_000_000:
                        raise ValueError("Unsupported page")
                    if max(image.size) > 20_000:
                        raise ValueError("Unsupported dimensions")
                    image.verify()
        except (OSError, binascii.Error, Image.DecompressionBombError, Image.DecompressionBombWarning) as error:
            raise ValueError("Invalid image") from error
        pages.append(data)
    return pages


def validate_draft(draft):
    """Reject unsafe shapes; musical inconsistencies remain reviewable drafts."""
    if not isinstance(draft, dict):
        raise ValueError("Invalid draft")
    score = draft.get("score", draft)
    if not isinstance(score, dict) or not isinstance(score.get("title"), str):
        raise ValueError("Missing score")
    bars = score.get("bars")
    if not isinstance(bars, list) or not 1 <= len(bars) <= 2000:
        raise ValueError("Missing bars")
    for bar in bars:
        if not isinstance(bar, dict) or not isinstance(bar.get("events"), list) or len(bar["events"]) > 256:
            raise ValueError("Invalid bar")
        for event in bar["events"]:
            if not isinstance(event, dict) or not isinstance(event.get("tones"), list) or len(event["tones"]) > 6:
                raise ValueError("Invalid event")
            if type(event.get("tick")) is not int or not 0 <= event["tick"] <= 8_000_000:
                raise ValueError("Invalid tick")
            if type(event.get("duration")) is not int or not 1 <= event["duration"] <= 8_000_000:
                raise ValueError("Invalid duration")
            for tone in event["tones"]:
                if not isinstance(tone, dict) or type(tone.get("midi")) is not int or not 0 <= tone["midi"] <= 127:
                    raise ValueError("Invalid tone")
                for key, low, high in [("string",1,6),("fret",0,24),("finger",0,4)]:
                    if tone.get(key) is not None and (type(tone[key]) is not int or not low <= tone[key] <= high):
                        raise ValueError("Invalid fingering")
    if len(json.dumps(draft, allow_nan=False).encode()) > MAX_RESULT:
        raise ValueError("Result too large")
    return draft


def combine_pages(drafts):
    merged = None
    warnings = []
    for page, draft in enumerate(drafts, 1):
        score = json.loads(json.dumps(draft.get("score", draft)))
        if merged is None:
            merged = {key:value for key,value in score.items() if key not in {"bars","warnings"}}
            merged["bars"] = []
        if score.get("ticksPerQuarter",960) != merged.get("ticksPerQuarter",960):
            raise ValueError("Inconsistent score resolution")
        for bar in score["bars"]:
            bar["source"] = {**(bar.get("source") or {}),"page":page}
            for event in bar["events"]:
                event["source"] = {**(event.get("source") or {}),"page":page}
            merged["bars"].append(bar)
        if page > 1 and score.get("tempo") != merged.get("tempo") and score.get("tempo"):
            score["bars"][0]["tempo"] = score["tempo"]
        for warning in draft.get("warnings",[]):
            warning = {"message":warning} if isinstance(warning,str) else warning
            if isinstance(warning,dict): warnings.append({**warning,"page":page})
    merged["warnings"] = warnings
    return validate_draft(merged)


class ServiceError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


class JobStore:
    def __init__(self, path, provider, workers=2, capacity=8, ttl=86400):
        self.lock = threading.RLock()
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, owner TEXT, nonce TEXT, digest TEXT, status TEXT, generation INTEGER, updated REAL, draft TEXT, UNIQUE(owner,nonce))")
        columns = {row[1] for row in self.db.execute("PRAGMA table_info(jobs)")}
        if "page_state" not in columns:
            self.db.execute("ALTER TABLE jobs ADD COLUMN page_state TEXT")
        self.db.execute("UPDATE jobs SET status='failed', updated=? WHERE status IN ('running','queued')", (time.time(),))
        self.db.commit()
        self.provider, self.capacity, self.ttl = provider, capacity, ttl
        self.pool = ThreadPoolExecutor(max_workers=workers, thread_name_prefix="gita-omr")
        self.inflight = 0
        self.futures = {}

    def _prune(self):
        self.db.execute("DELETE FROM jobs WHERE updated < ? AND status IN ('succeeded','failed','cancelled')", (time.time() - self.ttl,))

    def submit(self, owner, nonce, pages):
        digest = hashlib.sha256()
        for page in pages:
            digest.update(len(page).to_bytes(8, "big"))
            digest.update(page)
        digest = digest.hexdigest()
        with self.lock:
            self._prune()
            old = self.db.execute("SELECT id,digest,status,generation,page_state FROM jobs WHERE owner=? AND nonce=?", (owner, nonce)).fetchone()
            if old:
                if old[1] != digest:
                    raise ServiceError(409, "Idempotency key content conflict")
                if old[2] not in {"failed", "cancelled"}:
                    return self.get(owner, old[0])
            if self.inflight >= self.capacity:
                raise ServiceError(429, "Recognition capacity reached")
            job_id, generation = (old[0], old[3] + 1) if old else (str(uuid.uuid4()), 1)
            states = json.loads(old[4]) if old and old[4] else [{"page":i+1,"status":"queued"} for i in range(len(pages))]
            for state in states:
                if state["status"] != "succeeded": state["status"] = "queued"
            self.db.execute("INSERT OR REPLACE INTO jobs (id,owner,nonce,digest,status,generation,updated,draft,page_state) VALUES (?,?,?,?,?,?,?,?,?)",
                            (job_id, owner, nonce, digest, "queued", generation, time.time(), None,json.dumps(states)))
            self.db.commit()
            self.inflight += 1
            try:
                future = self.pool.submit(self._work, job_id, generation, pages)
                self.futures[(job_id, generation)] = future
                future.add_done_callback(lambda done: self._release(job_id, generation))
            except RuntimeError:
                self.inflight -= 1
                self.db.execute("UPDATE jobs SET status='failed' WHERE id=?", (job_id,))
                self.db.commit()
                raise ServiceError(503, "Service stopping") from None
            return {"id": job_id, "status": "queued"}

    def _work(self, job_id, generation, pages):
        try:
            with self.lock:
                changed = self.db.execute("UPDATE jobs SET status='running',updated=? WHERE id=? AND generation=? AND status='queued'",
                                          (time.time(), job_id, generation)).rowcount
                self.db.commit()
            if not changed:
                return
            with self.lock:
                states = json.loads(self.db.execute("SELECT page_state FROM jobs WHERE id=?",(job_id,)).fetchone()[0])
            for index, page in enumerate(pages):
                if states[index]["status"] == "succeeded": continue
                if not self._page_update(job_id,generation,states,index,"running"): return
                try:
                    states[index]["draft"] = validate_draft(self.provider([page]))
                    status = "succeeded"
                except Exception:
                    status = "failed"
                if not self._page_update(job_id,generation,states,index,status): return
            if any(state["status"] != "succeeded" for state in states): raise ValueError("Page failed")
            result = combine_pages([state["draft"] for state in states])
            encoded = json.dumps(result, ensure_ascii=False, allow_nan=False)
            with self.lock:
                self.db.execute("UPDATE jobs SET status='succeeded',draft=?,updated=? WHERE id=? AND generation=? AND status='running'",
                                (encoded, time.time(), job_id, generation))
                self.db.commit()
        except Exception:
            # Provider errors may contain credentials/page content; never expose them.
            with self.lock:
                self.db.execute("UPDATE jobs SET status='failed',draft=NULL,updated=? WHERE id=? AND generation=? AND status='running'",
                                (time.time(), job_id, generation))
                self.db.commit()

    def _page_update(self,job_id,generation,states,index,status):
        states[index]["status"] = status
        with self.lock:
            changed = self.db.execute("UPDATE jobs SET page_state=?,updated=? WHERE id=? AND generation=? AND status='running'",
                                     (json.dumps(states,ensure_ascii=False),time.time(),job_id,generation)).rowcount
            self.db.commit()
            return bool(changed)

    def _release(self, job_id, generation):
        with self.lock:
            if self.futures.pop((job_id, generation), None) is not None:
                self.inflight -= 1

    def get(self, owner, job_id):
        with self.lock:
            self._prune()
            row = self.db.execute("SELECT status,draft,page_state FROM jobs WHERE id=? AND owner=?", (job_id, owner)).fetchone()
            self.db.commit()
            if not row:
                raise ServiceError(404, "Task not found")
            result = {"id": job_id, "status": row[0]}
            result["pages"] = [{"page":state["page"],"status":state["status"]} for state in json.loads(row[2] or "[]")]
            if row[0] == "succeeded":
                result["draft"] = json.loads(row[1])
            return result

    def cancel(self, owner, job_id):
        with self.lock:
            self.get(owner, job_id)
            self.db.execute("UPDATE jobs SET status='cancelled',draft=NULL,updated=? WHERE id=? AND owner=?", (time.time(), job_id, owner))
            self.db.commit()
            for (identity, _), future in list(self.futures.items()):
                if identity == job_id:
                    future.cancel()
            return self.get(owner, job_id)

    def close(self):
        self.pool.shutdown(wait=True, cancel_futures=False)
        with self.lock:
            self.db.close()


class QwenProvider:
    def __init__(self, base_url, model, key, prompt, total_timeout=240):
        parsed = urlsplit(base_url)
        local = parsed.hostname in {"127.0.0.1", "localhost", "::1"}
        if parsed.scheme != "https" and not (local and parsed.scheme == "http"):
            raise ValueError("Provider requires HTTPS")
        if not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or not model or not key:
            raise ValueError("Invalid operator provider settings")
        self.url = base_url.rstrip("/")
        if not self.url.endswith("/chat/completions"):
            self.url += "/chat/completions"
        self.model, self.key, self.prompt = model, key, prompt
        self.total_timeout = total_timeout

    def __call__(self, pages):
        # A socket inactivity timeout cannot bound a slow/trickling response.
        # A per-call process permits an actual deadline, including header reads,
        # response_format fallback and TLS/connect. Credentials never enter argv.
        context = multiprocessing.get_context("spawn")
        parent, child = context.Pipe(duplex=False)
        process = context.Process(target=_provider_process, args=(self,pages,child), daemon=True)
        process.start(); child.close()
        try:
            if not parent.poll(self.total_timeout):
                raise TimeoutError("Recognition deadline exceeded")
            payload = parent.recv_bytes(MAX_RESULT + 1024)
            envelope = json.loads(payload)
            if "error" in envelope:
                raise ValueError("Provider failed")
            return validate_draft(envelope["draft"])
        finally:
            parent.close()
            if process.is_alive(): process.terminate()
            process.join(timeout=1)
            if process.is_alive(): process.kill(); process.join(timeout=1)
            process.close()

    def _request(self, pages):
        content = [{"type": "text", "text": "Transcribe these pages in order. Return the complete JSON score and review warnings."}]
        for page in pages:
            mime = "image/png" if page.startswith(b"\x89PNG") else "image/jpeg"
            content.append({"type": "image_url", "image_url": {"url": "data:" + mime + ";base64," + base64.b64encode(page).decode()}})
        body = {"model": self.model, "messages": [{"role": "system", "content": self.prompt}, {"role": "user", "content": content}],
                "response_format": {"type": "json_object"}}
        for attempt in range(2):
            request = Request(self.url, data=json.dumps(body).encode(), headers={"Authorization": "Bearer " + self.key, "Content-Type": "application/json"})
            try:
                with build_opener(NoRedirect()).open(request, timeout=240) as response:
                    raw = response.read(MAX_RESULT + 1)
                break
            except HTTPError as error:
                if error.code == 400 and attempt == 0:
                    body.pop("response_format", None)
                    error.close()
                    continue
                error.close()
                raise ValueError("Provider failed") from None
        if len(raw) > MAX_RESULT:
            raise ValueError("Provider response too large")
        text = json.loads(raw)["choices"][0]["message"]["content"]
        if not isinstance(text, str):
            raise ValueError("Invalid provider content")
        text = text.strip()
        if text.startswith("```"):
            text = text.partition("\n")[2].rsplit("```", 1)[0].strip()
        return validate_draft(json.loads(text))


def _provider_process(provider, pages, connection):
    try:
        result = {"draft": provider._request(pages)}
        payload = json.dumps(result, ensure_ascii=False, allow_nan=False).encode()
        if len(payload) > MAX_RESULT: raise ValueError("Result too large")
        connection.send_bytes(payload)
    except Exception:
        connection.send_bytes(b'{"error":"provider_failed"}')
    finally:
        connection.close()


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward a server-held provider key to a redirected host.
        return None


class RecognitionServer(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = True

    def __init__(self, address, jobs, tokens):
        if not tokens or any(not key or not owner for key, owner in tokens.items()):
            raise ValueError("Provision service tokens first")
        self.jobs, self.tokens = jobs, tokens
        self.connections = threading.BoundedSemaphore(32)
        super().__init__(address, RecognitionHandler)

    def process_request(self, request, client_address):
        if not self.connections.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.connections.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.connections.release()


class RecognitionHandler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(20)

    def log_message(self, *args):
        pass  # No tokens, user paths, page bytes, or raw provider errors in logs.

    def _handle(self):
        try:
            auth = self.headers.get("Authorization", "")
            owner = next((owner for token, owner in self.server.tokens.items()
                          if hmac.compare_digest(auth.encode(), ("Bearer " + token).encode())), None)
            if owner is None:
                raise ServiceError(401, "Unauthorized")
            parts = self.path.split("/")
            if self.command == "POST" and self.path == "/v1/recognitions":
                nonce = self.headers.get("Idempotency-Key", "")
                if not nonce or len(nonce) > 128:
                    raise ServiceError(400, "Missing idempotency key")
                if self.headers.get("Transfer-Encoding") or len(self.headers.get_all("Content-Length", [])) != 1:
                    raise ServiceError(411, "Content-Length required")
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= MAX_BODY:
                    raise ServiceError(413, "Request too large")
                raw = self.rfile.read(length)
                if len(raw) != length:
                    raise ServiceError(400, "Incomplete body")
                body = json.loads(raw)
                if not isinstance(body, dict) or set(body) != {"pages"}:
                    raise ServiceError(400, "Only score pages are accepted")
                result = self.server.jobs.submit(owner, nonce, validate_pages(body["pages"]))
                self._send(202, result)
            elif len(parts) == 4 and parts[1:3] == ["v1", "recognitions"] and self.command in {"GET", "DELETE"}:
                job_id = str(uuid.UUID(parts[3]))
                operation = self.server.jobs.get if self.command == "GET" else self.server.jobs.cancel
                self._send(200, operation(owner, job_id))
            else:
                raise ServiceError(404, "Not found")
        except ServiceError as error:
            self._send(error.status, {"error": error.message})
        except (ValueError, TypeError, KeyError, UnicodeError):
            self._send(400, {"error": "Invalid request"})
        except (ConnectionError, TimeoutError):
            self.close_connection = True
        except Exception:
            self._send(500, {"error": "Service unavailable"})

    def _send(self, status, body):
        payload = json.dumps(body, ensure_ascii=False, allow_nan=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)
        self.close_connection = True

    do_GET = _handle
    do_POST = _handle
    do_DELETE = _handle


def main():
    os.umask(0o077)
    tokens = json.loads(os.environ["GITA_SERVICE_TOKENS_JSON"])
    prompt = Path(__file__).with_name("recognition-prompt.txt").read_text()
    provider = QwenProvider(os.environ["GITA_OMR_BASE_URL"], os.environ["GITA_OMR_MODEL"], os.environ["GITA_OMR_API_KEY"], prompt)
    db = Path(os.environ.get("GITA_OMR_DATABASE", "jobs.sqlite"))
    db.parent.mkdir(parents=True, exist_ok=True)
    jobs = JobStore(db, provider)
    server = RecognitionServer(("127.0.0.1", int(os.environ.get("PORT", "8788"))), jobs, tokens)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        jobs.close()


if __name__ == "__main__":
    main()
