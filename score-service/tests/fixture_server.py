"""Serve the real recognition HTTP API with a deterministic, offline provider for iOS UI tests."""
import json
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

from service import JobStore, RecognitionHandler, RecognitionServer


def audit(event, **fields):
    print(json.dumps({"time": datetime.now(timezone.utc).isoformat(), "event": event, **fields}), flush=True)


def fixed_draft():
    bars = []
    for number, fret in enumerate((0, 3), 1):
        bars.append({
            "number": number, "numerator": 4, "denominator": 4,
            "events": [{"tick": 0, "duration": 3840, "voice": 1,
                        "tones": [{"midi": 64 + fret, "string": 1, "fret": fret}]}],
        })
    return {"title": "Fixture Score", "composer": "Fixture", "ticksPerQuarter": 960,
            "tempo": {"bpm": 68, "beatUnit": 4}, "tuning": [40, 45, 50, 55, 59, 64],
            "capo": 0, "warnings": [], "bars": bars}


class AuditedHandler(RecognitionHandler):
    def _send(self, status, body):
        audit("http", method=self.command, http_status=status, job_id=body.get("id"),
              job_status=body.get("status"), pages=body.get("pages"))
        super()._send(status, body)


def main():
    job_context = threading.local()

    class FixtureJobStore(JobStore):
        def _work(self, job_id, generation, pages):
            job_context.id = job_id
            super()._work(job_id, generation, pages)

    calls = 0

    def provider(pages):
        nonlocal calls
        calls += 1  # The fixture has exactly one worker.
        audit("provider", invocation=calls, job_id=job_context.id, page_count=len(pages))
        time.sleep(12)
        return fixed_draft()

    with tempfile.TemporaryDirectory() as directory:
        jobs = FixtureJobStore(Path(directory) / "jobs.sqlite", provider, workers=1)
        try:
            with RecognitionServer(("127.0.0.1", 18788), jobs, {"fixture-session": "fixture-user"}) as server:
                server.RequestHandlerClass = AuditedHandler
                audit("ready", port=server.server_port)
                server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            jobs.close()


if __name__ == "__main__":
    main()
