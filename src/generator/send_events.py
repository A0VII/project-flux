#!/usr/bin/env python3
"""
Project Flux — Synthetic Telemetry Event Generator

Simulates wearable health device sending events to the
Project Flux ingestion pipeline via API Gateway.

Usage:
    # Send a single Green heartbeat event
    python3 send_events.py

    # Send a burst of N events
    python3 send_events.py --mode burst --count 10

    # Run the full demo scenario (Green → Yellow → Red → recovery)
    python3 send_events.py --mode scenario

    # Send a specific risk state
    python3 send_events.py --risk-state Red --device-id device-demo-001

Environment:
    API_ENDPOINT  — required: the API Gateway URL
                    e.g. https://xxxx.execute-api.ap-south-1.amazonaws.com/dev/events

    Export before running:
    export API_ENDPOINT=$(cd infra && terraform output -raw api_endpoint)
"""

import argparse
import json
import os
import random
import sys
import time
import uuid
from datetime import datetime, timezone

import urllib.request
import urllib.error

# ── Configuration ────────────────────────────────────────────

API_ENDPOINT = os.environ.get("API_ENDPOINT", "")

RISK_STATES = ["Green", "Yellow", "Red", "Red++"]

# Realistic vital sign ranges per risk state
VITALS_BY_RISK = {
    "Green":  {"bpm": (60, 90),   "spo2": (96, 100)},
    "Yellow": {"bpm": (91, 110),  "spo2": (93, 95)},
    "Red":    {"bpm": (111, 150), "spo2": (88, 92)},
    "Red++":  {"bpm": (151, 180), "spo2": (80, 87)},
}

EVENT_TYPES = [
    "heartbeat",
    "risk_state_change",
    "session_start",
    "session_end",
]


# ── Event construction ────────────────────────────────────────

def build_event(
    device_id: str,
    session_id: str,
    risk_state: str = "Green",
    event_type: str = "heartbeat",
) -> dict:
    """Build a single telemetry event payload."""
    vitals = VITALS_BY_RISK[risk_state]
    return {
        "device_id":      device_id,
        "session_id":     session_id,
        "timestamp":      datetime.now(timezone.utc).isoformat(),
        "event_type":     event_type,
        "risk_state":     risk_state,
        "values": {
            "bpm":  random.randint(*vitals["bpm"]),
            "spo2": random.randint(*vitals["spo2"]),
        },
        "source":         "simulator",
        "schema_version": "1.0",
    }


# ── HTTP send ─────────────────────────────────────────────────

def send_event(event: dict, endpoint: str) -> tuple[int, str]:
    """POST one event to API Gateway. Returns (status_code, body)."""
    data = json.dumps(event).encode("utf-8")
    req  = urllib.request.Request(
        url     = endpoint,
        data    = data,
        headers = {"Content-Type": "application/json"},
        method  = "POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as exc:
        return 0, str(exc)


# ── Output helpers ────────────────────────────────────────────

COLOURS = {
    "Green":  "\033[92m",   # bright green
    "Yellow": "\033[93m",   # bright yellow
    "Red":    "\033[91m",   # bright red
    "Red++":  "\033[91m",   # bright red
    "RESET":  "\033[0m",
    "DIM":    "\033[2m",
    "BOLD":   "\033[1m",
}

def coloured(text: str, colour: str) -> str:
    return f"{COLOURS.get(colour, '')}{text}{COLOURS['RESET']}"

def print_event(event: dict, status: int, body: str, index: int) -> None:
    state  = event["risk_state"]
    marker = "✅" if status == 202 else "❌"
    c      = COLOURS.get(state, "")
    reset  = COLOURS["RESET"]
    dim    = COLOURS["DIM"]

    print(
        f"{marker} [{index:>3}] "
        f"{c}{state:<7}{reset} | "
        f"device={event['device_id']} | "
        f"bpm={event['values']['bpm']:>3} spo2={event['values']['spo2']}% | "
        f"type={event['event_type']:<20} | "
        f"{dim}HTTP {status}{reset}"
    )


# ── Modes ─────────────────────────────────────────────────────

def mode_single(args) -> None:
    """Send one event and exit."""
    device_id  = args.device_id
    session_id = f"sess-{uuid.uuid4().hex[:8]}"
    event      = build_event(device_id, session_id, args.risk_state, "heartbeat")

    print(f"\n{COLOURS['BOLD']}Project Flux — Single Event{COLOURS['RESET']}")
    print(f"Endpoint: {COLOURS['DIM']}{API_ENDPOINT}{COLOURS['RESET']}\n")

    status, body = send_event(event, API_ENDPOINT)
    print_event(event, status, body, 1)
    print(f"\nPayload: {json.dumps(event, indent=2)}\n")


def mode_burst(args) -> None:
    """Send N events in quick succession."""
    device_id  = args.device_id
    session_id = f"sess-{uuid.uuid4().hex[:8]}"
    count      = args.count
    delay      = args.delay

    print(f"\n{COLOURS['BOLD']}Project Flux — Burst Mode{COLOURS['RESET']}")
    print(f"Sending {count} events | delay={delay}s | device={device_id}\n")

    success = 0
    for i in range(1, count + 1):
        risk  = random.choices(
            RISK_STATES,
            weights=[70, 20, 8, 2],   # realistic distribution
        )[0]
        etype = random.choice(EVENT_TYPES)
        event = build_event(device_id, session_id, risk, etype)
        status, body = send_event(event, API_ENDPOINT)
        print_event(event, status, body, i)
        if status == 202:
            success += 1
        if delay > 0 and i < count:
            time.sleep(delay)

    print(f"\n{COLOURS['BOLD']}Summary:{COLOURS['RESET']} "
          f"{success}/{count} accepted | "
          f"{'✅ All good' if success == count else '⚠️ Some failed'}\n")


def mode_scenario(args) -> None:
    """
    Full demo scenario:
      Phase 1 — Normal operation (Green heartbeats)
      Phase 2 — Degradation (Yellow warnings)
      Phase 3 — Critical event (Red alert → email fires)
      Phase 4 — Recovery (back to Green)
    """
    device_id  = args.device_id
    session_id = f"sess-demo-{uuid.uuid4().hex[:8]}"

    scenario = [
        # (risk_state, event_type, label, count, delay)
        ("Green",  "session_start",    "Starting session",       1, 0),
        ("Green",  "heartbeat",        "Normal operation",        4, 1.0),
        ("Yellow", "risk_state_change","Degradation detected",    2, 1.5),
        ("Red",    "risk_state_change","🚨 CRITICAL — alert fires!", 1, 0),
        ("Red",    "heartbeat",        "Critical sustained",      1, 2.0),
        ("Yellow", "risk_state_change","Recovering",              2, 1.5),
        ("Green",  "risk_state_change","Back to normal",          2, 1.0),
        ("Green",  "session_end",      "Session complete",        1, 0),
    ]

    print(f"\n{COLOURS['BOLD']}Project Flux — Demo Scenario{COLOURS['RESET']}")
    print(f"Device:   {device_id}")
    print(f"Session:  {session_id}")
    print(f"Endpoint: {COLOURS['DIM']}{API_ENDPOINT}{COLOURS['RESET']}\n")
    print("─" * 70)

    idx = 1
    for risk, etype, label, count, delay in scenario:
        c = COLOURS.get(risk, "")
        print(f"\n{c}▶ {label}{COLOURS['RESET']}")
        for _ in range(count):
            event = build_event(device_id, session_id, risk, etype)
            status, body = send_event(event, API_ENDPOINT)
            print_event(event, status, body, idx)
            idx += 1
            if delay > 0:
                time.sleep(delay)

    print("\n" + "─" * 70)
    print(f"\n{COLOURS['BOLD']}Scenario complete.{COLOURS['RESET']}")
    print("Check your inbox for the Red alert email.")
    print("Check CloudWatch dashboard for live metrics.\n")


# ── Entry point ───────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Project Flux — synthetic telemetry event generator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--mode",
        choices=["single", "burst", "scenario"],
        default="single",
        help="Execution mode (default: single)",
    )
    parser.add_argument(
        "--device-id",
        default="device-demo-001",
        help="Device identifier (default: device-demo-001)",
    )
    parser.add_argument(
        "--risk-state",
        choices=RISK_STATES,
        default="Green",
        help="Risk state for single/burst mode (default: Green)",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=10,
        help="Number of events for burst mode (default: 10)",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.5,
        help="Seconds between events in burst mode (default: 0.5)",
    )

    args = parser.parse_args()

    if not API_ENDPOINT:
        print(
            "\n❌ API_ENDPOINT environment variable not set.\n"
            "   Run: export API_ENDPOINT=$(cd infra && terraform output -raw api_endpoint)\n",
            file=sys.stderr,
        )
        sys.exit(1)

    print(f"{COLOURS['BOLD']}Project Flux Event Generator{COLOURS['RESET']}")
    print(f"Mode: {args.mode} | Endpoint: {COLOURS['DIM']}{API_ENDPOINT[:50]}...{COLOURS['RESET']}")

    if args.mode == "single":
        mode_single(args)
    elif args.mode == "burst":
        mode_burst(args)
    elif args.mode == "scenario":
        mode_scenario(args)


if __name__ == "__main__":
    main()
