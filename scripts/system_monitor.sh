#!/bin/bash
# Central monitoring script. Run this script on VM2.
set -u

PROJECT_DIR="/opt/hpcc-monitor"
CONFIG_FILE="$PROJECT_DIR/config/targets.conf"
REPORT="$PROJECT_DIR/reports/latest_report.txt"
LOG="$PROJECT_DIR/logs/system_monitor.log"
HISTORY="$PROJECT_DIR/reports/metrics_history.csv"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Missing $CONFIG_FILE"
    echo "Copy config/targets.conf.example to config/targets.conf and edit it."
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

PYTHON_BIN="${PYTHON_BIN:-python3}"
ALERT_EMAIL="${ALERT_EMAIL:-}"
CPU_THRESHOLD="${CPU_THRESHOLD:-80}"
MEM_THRESHOLD="${MEM_THRESHOLD:-85}"
DISK_THRESHOLD="${DISK_THRESHOLD:-90}"
DETECTOR_MODE="${DETECTOR_MODE:-threshold}"

mkdir -p "$PROJECT_DIR/reports" "$PROJECT_DIR/logs"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

if ! command -v ssh >/dev/null 2>&1; then
    echo "ERROR: ssh client is not installed." | tee -a "$LOG"
    exit 1
fi

# Collect metrics on VM1 over SSH. vmstat's final row gives CPU idle in column 15
# on standard procps vmstat output; CPU usage is calculated as 100 - idle.
REMOTE_CMD='
set -u
HOST=$(hostname 2>/dev/null || echo unknown)
UPTIME=$(uptime 2>/dev/null | sed "s/^[[:space:]]*//")
CPU=$(vmstat 1 2 2>/dev/null | tail -n 1 | awk "{if (\$15 ~ /^[0-9.]+$/) printf \"%.2f\", 100-\$15; else print \"0\"}")
MEM=$(free -m 2>/dev/null | awk "/^Mem:/ {if (\$2>0) printf \"%.2f\", (\$3/\$2)*100; else print \"0\"}")
DISK=$(df -P / 2>/dev/null | awk "NR==2 {gsub(/%/, \"\", \$5); print \$5}")
printf "HOSTNAME=%s\n" "$HOST"
printf "UPTIME=%s\n" "$UPTIME"
printf "CPU=%s\n" "${CPU:-0}"
printf "MEM=%s\n" "${MEM:-0}"
printf "DISK=%s\n" "${DISK:-0}"
'

echo "[$TIMESTAMP] Starting monitoring for ${SSH_USER}@${HPCC_NODE_IP}" >> "$LOG"

# ConnectTimeout avoids hanging indefinitely when VM1 is unavailable.
METRICS="$(ssh -o BatchMode=yes -o ConnectTimeout=10 \
    "${SSH_USER}@${HPCC_NODE_IP}" "$REMOTE_CMD" 2>&1)"
SSH_STATUS=$?

if [ "$SSH_STATUS" -ne 0 ]; then
    {
        echo "AI/ML HPCC Monitoring System — CONNECTION ERROR"
        echo "Timestamp: $TIMESTAMP"
        echo "Target: ${HPCC_NODE_IP}"
        echo
        echo "Could not collect metrics over SSH."
        echo "SSH output:"
        echo "$METRICS"
        echo
        echo "Recommended actions:"
        echo "- Check that VM1 is running and reachable."
        echo "- Verify SSH service, user, key permissions, and target IP."
        echo
        echo "Regards,"
        echo "HPCC Monitoring System"
    } > "$REPORT"
    echo "[$TIMESTAMP] SSH collection failed: $METRICS" >> "$LOG"
    if [ -n "$ALERT_EMAIL" ] && command -v mail >/dev/null 2>&1; then
        mail -s "HPCC MONITORING: SSH CONNECTION ERROR" "$ALERT_EMAIL" < "$REPORT"
    fi
    exit 2
fi

HOSTNAME_VALUE="$(printf '%s\n' "$METRICS" | sed -n 's/^HOSTNAME=//p' | head -n 1)"
UPTIME_VALUE="$(printf '%s\n' "$METRICS" | sed -n 's/^UPTIME=//p' | head -n 1)"
CPU_VALUE="$(printf '%s\n' "$METRICS" | sed -n 's/^CPU=//p' | head -n 1)"
MEM_VALUE="$(printf '%s\n' "$METRICS" | sed -n 's/^MEM=//p' | head -n 1)"
DISK_VALUE="$(printf '%s\n' "$METRICS" | sed -n 's/^DISK=//p' | head -n 1)"

# Validate that the remote command returned numeric metrics.
for value in "$CPU_VALUE" "$MEM_VALUE" "$DISK_VALUE"; do
    if ! [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        echo "ERROR: Invalid metric received from VM1: $value" | tee -a "$LOG"
        exit 3
    fi
done

# Create/update CSV history. Isolation Forest uses this historical data when
# enough observations have accumulated; early runs use threshold fallback.
if [ ! -f "$HISTORY" ]; then
    echo "timestamp,cpu,mem,disk" > "$HISTORY"
fi
printf '"%s",%s,%s,%s\n' "$TIMESTAMP" "$CPU_VALUE" "$MEM_VALUE" "$DISK_VALUE" >> "$HISTORY"

AI_STATUS="NORMAL"
AI_DETAILS=""

if [ "$DETECTOR_MODE" = "isolation_forest" ]; then
    AI_OUTPUT="$("$PYTHON_BIN" "$PROJECT_DIR/ai/isolation_forest.py" \
        "$CPU_VALUE" "$MEM_VALUE" "$DISK_VALUE" "$HISTORY" 2>&1)"
    AI_RC=$?
    if [ "$AI_RC" -eq 0 ]; then
        AI_STATUS="$(printf '%s\n' "$AI_OUTPUT" | sed -n 's/^STATUS=//p' | tail -n 1)"
        AI_DETAILS="$(printf '%s\n' "$AI_OUTPUT" | sed -n 's/^DETAILS=//p' | tail -n 1)"
    else
        AI_STATUS="$("$PYTHON_BIN" "$PROJECT_DIR/ai/anomaly_detector.py" \
            "$CPU_VALUE" "$MEM_VALUE" "$DISK_VALUE" \
            "$CPU_THRESHOLD" "$MEM_THRESHOLD" "$DISK_THRESHOLD" 2>&1)"
        AI_DETAILS="Isolation Forest unavailable/failed; threshold fallback used. $AI_OUTPUT"
    fi
else
    AI_STATUS="$("$PYTHON_BIN" "$PROJECT_DIR/ai/anomaly_detector.py" \
        "$CPU_VALUE" "$MEM_VALUE" "$DISK_VALUE" \
        "$CPU_THRESHOLD" "$MEM_THRESHOLD" "$DISK_THRESHOLD" 2>&1)"
    AI_DETAILS="Configured threshold-based detector."
fi

if [ "$AI_STATUS" != "ANOMALY" ]; then
    AI_STATUS="NORMAL"
fi

{
    echo "AI/ML HPCC Monitoring System Report"
    echo "Timestamp: $TIMESTAMP"
    echo "Target IP: $HPCC_NODE_IP"
    echo "Hostname: ${HOSTNAME_VALUE:-unknown}"
    echo "Uptime: ${UPTIME_VALUE:-unknown}"
    echo
    echo "Metrics:"
    echo "CPU usage (%): $CPU_VALUE"
    echo "Memory usage (%): $MEM_VALUE"
    echo "Root disk usage (%): $DISK_VALUE"
    echo
    echo "AI status: $AI_STATUS"
    echo "Analysis: $AI_DETAILS"
    echo
    if [ "$AI_STATUS" = "ANOMALY" ]; then
        echo "Action Recommended:"
        echo "- Check CPU, memory, and disk utilization."
        echo "- Inspect the target node and relevant system logs."
        echo "- Confirm whether the workload is expected before taking action."
    else
        echo "System status is within the configured monitoring criteria."
    fi
} > "$REPORT"

echo "[$TIMESTAMP] Host=${HOSTNAME_VALUE:-unknown} CPU=$CPU_VALUE MEM=$MEM_VALUE DISK=$DISK_VALUE STATUS=$AI_STATUS" >> "$LOG"

if [ "$AI_STATUS" = "ANOMALY" ]; then
    if [ -n "$ALERT_EMAIL" ] && command -v mail >/dev/null 2>&1; then
        {
            echo "AI/ML Monitoring System Alert"
            echo
            echo "An anomaly has been detected in the HPCC cluster."
            echo
            echo "Report Details:"
            cat "$REPORT"
            echo
            echo "Action Recommended:"
            echo "- Check CPU, memory, and disk usage."
            echo "- Inspect the affected node."
            echo
            echo "Regards,"
            echo "AI Monitoring System"
        } | mail -s "HPCC AI ANOMALY ALERT" "$ALERT_EMAIL"
        MAIL_STATUS=$?
        if [ "$MAIL_STATUS" -eq 0 ]; then
            echo "[$TIMESTAMP] Alert email submitted to local mail service for $ALERT_EMAIL" >> "$LOG"
        else
            echo "[$TIMESTAMP] ERROR: mail command failed with status $MAIL_STATUS" >> "$LOG"
        fi
    else
        echo "[$TIMESTAMP] ANOMALY detected, but ALERT_EMAIL or mail command is missing." >> "$LOG"
    fi
fi

cat "$REPORT"
