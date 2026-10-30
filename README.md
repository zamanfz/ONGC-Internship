# AI-Based HPCC Monitoring System

A two-VM educational prototype for monitoring a Linux compute node over SSH, collecting CPU/memory/disk metrics, generating a report, and sending an email alert when the configured detector flags an anomaly.

## Architecture

- **VM1 — compute/target node:** provides system metrics via standard Linux utilities and SSH.
- **VM2 — monitoring node:** contains this project under `/opt/hpcc-monitor`, connects to VM1 over SSH, runs detection, writes reports/logs, and submits alert emails using the local `mail` command.

## Project layout

```text
/opt/hpcc-monitor/
├── ai/
│   ├── anomaly_detector.py
│   └── isolation_forest.py
├── config/
│   ├── targets.conf
│   └── targets.conf.example
├── scripts/
│   └── system_monitor.sh
├── reports/
│   ├── latest_report.txt
│   └── metrics_history.csv
└── logs/
    └── system_monitor.log
```

## Setup on VM2

1. Put the project at `/opt/hpcc-monitor`.
2. Create the live configuration file:

   ```bash
   cp /opt/hpcc-monitor/config/targets.conf.example /opt/hpcc-monitor/config/targets.conf
   vi /opt/hpcc-monitor/config/targets.conf
   ```

3. Set the target VM1 IP, SSH username, Python path, and alert recipient.
4. Make the script executable:

   ```bash
   chmod +x /opt/hpcc-monitor/scripts/system_monitor.sh
   chmod +x /opt/hpcc-monitor/ai/anomaly_detector.py
   chmod +x /opt/hpcc-monitor/ai/isolation_forest.py
   ```

5. Verify SSH from VM2 to VM1:

   ```bash
   ssh -o ConnectTimeout=10 root@192.168.56.101 'hostname; uptime; free -m; df -h /'
   ```

   Replace the user and IP with your configured values. Prefer a dedicated least-privilege account over root for a real deployment. Do not disable SSH host-key checking in production.

6. Confirm the configured Python works:

   ```bash
   /opt/python3.9/bin/python3.9 --version
   /opt/python3.9/bin/python3.9 /opt/hpcc-monitor/ai/anomaly_detector.py 30 45 25
   ```

7. Run the monitor:

   ```bash
   cd /opt/hpcc-monitor
   ./scripts/system_monitor.sh
   ```

## Detection modes

### Threshold mode (default)

`DETECTOR_MODE="threshold"` checks whether CPU, memory, or root-disk usage reaches configured thresholds. This is a deterministic threshold-based detector, not a trained ML model.

### Isolation Forest mode

Set `DETECTOR_MODE="isolation_forest"` in `config/targets.conf`. The model uses historical rows from `reports/metrics_history.csv` and needs scikit-learn installed in the selected Python environment. Before 20 usable historical observations, it falls back to threshold checks. Isolation Forest is unsupervised and should be evaluated against known normal/anomalous scenarios before claiming measured accuracy.

Install scikit-learn only if compatible with your Python/RHEL environment; in restricted enterprise systems, follow local software policies.

## Email alerts

The script uses the local `mail` command. Postfix/Gmail SMTP must already be configured on VM2. Test mail separately before relying on alert delivery. Store credentials in protected configuration outside version control; never commit SMTP passwords or Gmail app passwords.

## Files produced

- `reports/latest_report.txt`: most recent run report.
- `reports/metrics_history.csv`: time-series metrics used by the Isolation Forest option.
- `logs/system_monitor.log`: execution history and errors.

## Security notes

- Do not commit private SSH keys, Gmail credentials, passwords, API keys, or confidential ONGC/internal data.
- The sample target IP and root username are examples from a lab setup; review before publishing.
- Prefer a dedicated SSH account with only the permissions required to read metrics.
- A public GitHub repository should contain example configuration only, not live secrets or sensitive operational details.

## Troubleshooting

- **Connection refused:** ensure VM1 is running, `sshd` is active, and the IP/network is correct.
- **Permission denied (publickey/password):** verify SSH user, authorized key, file permissions, and SSH configuration.
- **No email:** test the `mail` command and inspect the Postfix mail log on VM2; verify SMTP relay settings.
- **Python module error:** run `python --version` and test imports with the exact interpreter configured in `PYTHON_BIN`.
- **No alert:** inspect `latest_report.txt`; with threshold mode, a metric must reach its configured limit.

## Important scope note

This package reconstructs the project structure and functionality from the available conversation context. It is not guaranteed to be byte-for-byte identical to the files previously on your VM. Validate the scripts in your lab before relying on them.
