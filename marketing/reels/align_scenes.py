#!/usr/bin/env python3
"""
align_scenes.py — merge the tour's MEASURED scene timings (from the sim log markers) into the
per-app scene config, so frame_reel.py captions land exactly on the footage.

Usage: align_scenes.py <base_scenes.json> <sim_syslog> <out_runtime.json>
Exits non-zero (leaving the base config to be used as-is) if markers are missing.
"""
import json, re, sys

base = json.load(open(sys.argv[1]))
log = open(sys.argv[2]).read()


def last(pat):
    m = re.findall(pat + r"\s+([0-9.]+)", log)
    return float(m[-1]) if m else None


t0, tend = last("REEL_T0"), last("REEL_END")
marks = re.findall(r"REEL_SCENE (\w+)\s+([0-9.]+)", log)
if t0 is None or tend is None or not marks:
    sys.exit("align_scenes: markers missing")

# first epoch per scene key, in encounter order
order, epoch = [], {}
for k, e in marks:
    if k not in epoch:
        epoch[k] = float(e); order.append(k)

by_key = {s["key"]: s for s in base["scenes"]}
out = []
for i, k in enumerate(order):
    start = epoch[k] - t0
    end = (epoch[order[i + 1]] - t0) if i + 1 < len(order) else (tend - t0)
    out.append({**by_key.get(k, {"key": k, "title": k, "subtitle": ""}),
                "key": k, "start": round(start, 3), "end": round(end, 3)})

if out:
    out[0]["start"] = 0.0   # first caption must be on frame 0, not a beat late
base["scenes"] = out
base["content_len"] = round(tend - t0, 3)
json.dump(base, open(sys.argv[3], "w"), indent=2)
print(f"align_scenes: {len(out)} scenes, content {base['content_len']}s")
