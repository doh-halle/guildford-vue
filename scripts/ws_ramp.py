"""FP C3 WebSocket connection-ramp harness.

Parallel to the OO project's `c3_ramp.py`. Opens N raw WebSocket
connections against Phoenix's `/live/websocket?vsn=2.0.0` endpoint,
holds each until the whole batch has completed handshake, reports
per-step successful-open count + handshake latency percentiles.

Runs with the OO project's Python venv (matching client instrument
across both artefacts):

    /home/gladstone/Documents/guildford-vue-oo/.venv/bin/python \\
        /home/gladstone/Documents/guildford-vue/scripts/ws_ramp.py \\
        --steps 50 200 500 1000 --host 127.0.0.1:4000

CSV columns: step,target_concurrency,successful_opens,failed_opens,
handshake_p50_ms,handshake_p95_ms,handshake_p99_ms — schema
identical to the OO harness so the paradigm-comparison table lines
up 1:1.
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import time
from pathlib import Path

import websockets

RAW_CSV = Path("docs/measurements/fp/raw/c3_ws_ramp.csv")


async def _open(host: str, timeout: float) -> tuple[bool, int]:
    uri = f"ws://{host}/live/websocket?vsn=2.0.0"
    t0 = time.monotonic_ns()
    try:
        ws = await asyncio.wait_for(
            websockets.connect(uri, additional_headers={"Origin": f"http://{host}"}),
            timeout=timeout,
        )
        latency_ns = time.monotonic_ns() - t0
    except Exception:
        return False, 0
    # Hold briefly then close cleanly.
    try:
        await asyncio.sleep(0.5)
    finally:
        await ws.close()
    return True, latency_ns


async def _run_step(step: int, count: int, host: str, timeout: float) -> dict:
    tasks = [asyncio.create_task(_open(host, timeout)) for _ in range(count)]
    results = await asyncio.gather(*tasks)
    successes = [ln for ok, ln in results if ok]
    fails = sum(1 for ok, _ in results if not ok)
    lat_ms = sorted(x / 1_000_000 for x in successes)
    p = lambda q: lat_ms[int(len(lat_ms) * q) - 1] if lat_ms else 0.0
    return {
        "step": step,
        "target_concurrency": count,
        "successful_opens": len(successes),
        "failed_opens": fails,
        "handshake_p50_ms": round(p(0.50), 2),
        "handshake_p95_ms": round(p(0.95), 2),
        "handshake_p99_ms": round(p(0.99), 2),
    }


async def _amain(steps: list[int], host: str, timeout: float) -> None:
    RAW_CSV.parent.mkdir(parents=True, exist_ok=True)
    with RAW_CSV.open("w", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=(
                "step",
                "target_concurrency",
                "successful_opens",
                "failed_opens",
                "handshake_p50_ms",
                "handshake_p95_ms",
                "handshake_p99_ms",
            ),
        )
        writer.writeheader()
        for i, count in enumerate(steps):
            row = await _run_step(i, count, host, timeout)
            writer.writerow(row)
            print(
                f"step={i:>2} target={row['target_concurrency']:>5} "
                f"ok={row['successful_opens']:>5} fail={row['failed_opens']:>3}  "
                f"p50={row['handshake_p50_ms']}ms p95={row['handshake_p95_ms']}ms "
                f"p99={row['handshake_p99_ms']}ms"
            )
            await asyncio.sleep(2.0)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--steps", type=int, nargs="+", default=[50, 200, 500, 1000])
    ap.add_argument("--host", default="127.0.0.1:4000")
    ap.add_argument("--timeout", type=float, default=10.0)
    args = ap.parse_args()
    asyncio.run(_amain(args.steps, args.host, args.timeout))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
