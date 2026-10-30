# AI-Based HPCC Monitoring System

A two-virtual-machine prototype for monitoring a Linux compute node remotely using SSH. The system collects CPU, memory, and disk metrics, detects threshold violations, generates reports, and supports email alerts.

## Architecture

- VM1 - Compute Node: The target Linux machine whose system metrics are collected.
- VM2 - Monitoring Node: Runs the monitoring script, connects to VM1 over SSH, performs anomaly detection, generates reports, and handles alert notifications.

## Project Structure

```text
HPCC-Monitoring-System/
|-- ai/
|   |-- anomaly_detector.py
|   |-- isolation_forest.py
|-- config/
|   |-- targets.conf.example
|-- scripts/
|   |-- system_monitor.sh
|-- reports/
|-- logs/
|-- HPCC_Monitoring_Project_Report.docx
|-- README.md
|-- .gitignore
```

## Technologies

- Red Hat Enterprise Linux (RHEL) 7.9
- Bash scripting
- Python
- SSH
- VirtualBox
- Threshold-based anomaly detection
- Linux system monitoring utilities
- Email alerting

## Configuration

1. Place the project in `/opt/hpcc-monitor` on the monitoring VM.
2. Copy the example configuration:

   ```bash
   cp /opt/hpcc-monitor/config/targets.conf.example /opt/hpcc-monitor/config/targets.conf
   ```

3. Edit `targets.conf` with the target VM's IP address, SSH username, Python executable, and alert recipient.
4. Configure SSH access from VM2 to VM1.
5. Configure the required email delivery service.

## Run the Monitor

Make the script executable:

```bash
chmod +x /opt/hpcc-monitor/scripts/system_monitor.sh
```

Run it:

```bash
/opt/hpcc-monitor/scripts/system_monitor.sh
```

## Anomaly Detection

The threshold-based detector checks CPU, memory, and disk usage against configured limits. When a metric reaches its configured threshold, the detector reports an anomaly.

The repository also contains an Isolation Forest implementation. Its integration and runtime behavior should be verified separately before describing it as part of the active monitoring pipeline.

## Important Note

This repository reconstructs the project from its documentation. The implementation must be tested in a compatible Linux environment before it is described as fully operational on RHEL 7.9.