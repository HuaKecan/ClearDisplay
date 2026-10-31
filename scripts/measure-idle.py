#!/usr/bin/env python3
"""Read-only resource sample. Does not drive UI or change displays."""
import datetime
import json
from pathlib import Path
import subprocess
import sys
import time

pid = int(sys.argv[1])
duration = float(sys.argv[2]) if len(sys.argv) > 2 else 10.0
destination = Path(sys.argv[3]) if len(sys.argv) > 3 else None

def sample():
    fields = subprocess.check_output(["ps", "-p", str(pid), "-o", "time=,rss=,%cpu="], text=True).split()
    minutes, seconds = fields[0].split(":")
    return {"cpuSeconds": int(minutes) * 60 + float(seconds), "rssKiB": int(fields[1]),
            "psCpuPercent": float(fields[2])}

initial = sample()
started = time.monotonic()
time.sleep(duration)
final = sample()
elapsed = time.monotonic() - started
processes = subprocess.check_output(["ps", "-axo", "pid=,ppid=,comm="], text=True).splitlines()
helpers = []
for line in processes:
    fields = line.split(None, 2)
    if len(fields) == 3 and (fields[2].endswith("/DisplayRescue") or fields[2].endswith("/DisplayVirtualHost")):
        helpers.append({"pid": int(fields[0]), "parentPID": int(fields[1]), "executable": fields[2]})
report = {"sampledAt": datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
          "pid": pid, "durationSeconds": round(elapsed, 3), "initial": initial, "final": final,
          "measuredCpuPercent": round(100 * (final["cpuSeconds"] - initial["cpuSeconds"]) / elapsed, 3),
          "rssMiB": round(final["rssKiB"] / 1024, 2), "liveDisplayHelpers": helpers,
          "limits": "Short local sample; RSS is resident memory, not physical footprint. No long-run claim."}
encoded = json.dumps(report, indent=2, ensure_ascii=False)
if destination:
    destination.write_text(encoded + "\n")
print(encoded)
