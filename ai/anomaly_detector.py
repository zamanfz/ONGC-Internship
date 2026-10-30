#!/usr/bin/env python3
"""
Lightweight threshold-based anomaly detector.
Usage:
  python3 anomaly_detector.py CPU_PERCENT MEM_PERCENT DISK_PERCENT [CPU_LIMIT MEM_LIMIT DISK_LIMIT]
Prints exactly NORMAL or ANOMALY for shell integration.
"""
import sys

def main():
    if len(sys.argv) not in (4, 7):
        print("Usage: anomaly_detector.py CPU MEM DISK [CPU_LIMIT MEM_LIMIT DISK_LIMIT]", file=sys.stderr)
        return 2

    try:
        cpu, mem, disk = map(float, sys.argv[1:4])
        limits = tuple(map(float, sys.argv[4:7])) if len(sys.argv) == 7 else (80.0, 85.0, 90.0)
    except ValueError:
        print("ERROR: all metric and threshold arguments must be numeric", file=sys.stderr)
        return 2

    if any(value < 0 for value in (cpu, mem, disk)):
        print("ERROR: metrics cannot be negative", file=sys.stderr)
        return 2

    triggered = (
        cpu >= limits[0] or
        mem >= limits[1] or
        disk >= limits[2]
    )
    print("ANOMALY" if triggered else "NORMAL")
    return 0

if __name__ == "__main__":
    sys.exit(main())
