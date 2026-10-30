#!/usr/bin/env python3
"""
Isolation Forest detector for HPCC metrics.

Usage:
  python3 isolation_forest.py CPU MEM DISK /path/to/metrics_history.csv

The script requires pandas and scikit-learn. It needs at least 20 historical
observations; before then it uses conservative thresholds. The history includes
the current sample, so the model fits the available rolling history. For formal
evaluation, keep a separate baseline dataset and evaluate on held-out samples.
"""
import csv
import sys
from pathlib import Path

CPU_LIMIT, MEM_LIMIT, DISK_LIMIT = 80.0, 85.0, 90.0
MIN_ROWS = 20

def threshold_status(cpu, mem, disk):
    return "ANOMALY" if (cpu >= CPU_LIMIT or mem >= MEM_LIMIT or disk >= DISK_LIMIT) else "NORMAL"

def load_rows(path):
    rows = []
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try:
                rows.append([float(row["cpu"]), float(row["mem"]), float(row["disk"])])
            except (KeyError, ValueError, TypeError):
                continue
    return rows

def main():
    if len(sys.argv) != 5:
        print("Usage: isolation_forest.py CPU MEM DISK HISTORY_CSV", file=sys.stderr)
        return 2
    try:
        cpu, mem, disk = map(float, sys.argv[1:4])
    except ValueError:
        print("ERROR: metrics must be numeric", file=sys.stderr)
        return 2

    history_path = Path(sys.argv[4])
    try:
        rows = load_rows(history_path)
    except OSError as exc:
        print("ERROR: cannot read history: {}".format(exc), file=sys.stderr)
        return 2

    if len(rows) < MIN_ROWS:
        status = threshold_status(cpu, mem, disk)
        print("STATUS={}".format(status))
        print("DETAILS=Only {} history rows; threshold fallback used (minimum {}).".format(len(rows), MIN_ROWS))
        return 0

    try:
        from sklearn.ensemble import IsolationForest
    except ImportError:
        print("ERROR: scikit-learn is not installed for this Python interpreter.", file=sys.stderr)
        return 3

    # Exclude the most recent sample from baseline training when possible.
    baseline = rows[:-1] if len(rows) > MIN_ROWS else rows
    if len(baseline) < MIN_ROWS:
        baseline = rows

    model = IsolationForest(
        n_estimators=100,
        contamination=0.05,
        random_state=42
    )
    model.fit(baseline)
    prediction = int(model.predict([[cpu, mem, disk]])[0])  # -1 anomaly, 1 normal
    score = float(model.decision_function([[cpu, mem, disk]])[0])
    status = "ANOMALY" if prediction == -1 else "NORMAL"
    print("STATUS={}".format(status))
    print("DETAILS=IsolationForest prediction={} decision_score={:.6f} baseline_rows={}".format(
        prediction, score, len(baseline)))
    return 0

if __name__ == "__main__":
    sys.exit(main())
