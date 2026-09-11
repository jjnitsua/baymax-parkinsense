"""
device_logger.py

FDA Cybersecurity Guidance (2023) compliant audit logger for the ADXL345
tremor detector. Implements structured, tamper-evident logging with log
rotation and integrity hashing.

Log categories align with FDA guidance sections:
  - Section 3.3 (Cybersecurity Signal Management)
  - Section 4   (Premarket Submissions - auditability)
  - NIST SP 800-92 (log management best practices)
"""

import logging
import logging.handlers
import json
import hashlib
import hmac
import os
import time
import uuid
import platform
from datetime import datetime, timezone
from pathlib import Path

# --- Configuration ---
LOG_DIR          = Path(__file__).parent / "log"
LOG_FILE         = LOG_DIR / "device_audit.log"
LOG_MAX_BYTES    = 5 * 1024 * 1024   # 5 MB per file before rotation
LOG_BACKUP_COUNT = 40                 # keep 40 rotated files (~200 MB total)

# HMAC key for log integrity — in production, load this from a hardware
# security module (HSM) or encrypted key store, NOT hardcoded here.
# Example: read from an encrypted file or AWS Secrets Manager at boot.
_INTEGRITY_KEY = os.environ.get("LOG_HMAC_KEY", "CHANGE_ME_IN_PRODUCTION").encode()


def _get_device_id() -> str:
    """
    Read the Raspberry Pi's unique hardware serial number.
    Falls back to a stable UUID derived from the machine's hostname
    if not running on a Pi (e.g. during development/testing).
    """
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("Serial"):
                    serial = line.split(":")[1].strip()
                    if serial and serial != "0000000000000000":
                        return f"rpi-{serial}"
    except OSError:
        pass
    # Fallback: stable UUID from hostname (not hardware-unique, acceptable for dev)
    return f"dev-{uuid.uuid5(uuid.NAMESPACE_DNS, platform.node())}"

# Device identity — ideally burned into hardware (e.g. RPi serial, UUID)
DEVICE_ID = _get_device_id()

def _hmac_sign(message: str) -> str:
    """
    Return a truncated HMAC-SHA256 hex digest for a log line.
    This lets you detect if log lines have been tampered with post-write.
    Full verification requires the same key used at write time.
    """
    return hmac.new(_INTEGRITY_KEY, message.encode(), hashlib.sha256).hexdigest()[:16]


# --- Log event categories (maps to FDA audit trail requirements) ---
class EventCategory:
    SYSTEM      = "SYSTEM"       # boot, shutdown, config changes
    SENSOR      = "SENSOR"       # sensor reads, FIFO overflows, hardware errors
    DATA        = "DATA"         # FFT results, anomaly detection, data quality
    NETWORK     = "NETWORK"      # MQTT connect/disconnect, AWS transfer status
    SECURITY    = "SECURITY"     # access events, integrity failures, key usage
    WATCHDOG    = "WATCHDOG"     # heartbeat / liveness signals


class AuditLogger:
    """
    Structured JSON audit logger with HMAC integrity signatures.

    Each log entry is a single JSON object on one line (JSON Lines format),
    making it easy to ingest into AWS CloudWatch, Splunk, or any SIEM.

    Usage:
        log = AuditLogger()
        log.system("DEVICE_BOOT", {"firmware": "1.0.0"})
        log.sensor("FIFO_OVERFLOW", {"samples_lost": 3})
    """

    def __init__(self):
        LOG_DIR.mkdir(parents=True, exist_ok=True)

        # Rotating file handler — auto-rotates at LOG_MAX_BYTES
        handler = logging.handlers.RotatingFileHandler(
            LOG_FILE,
            maxBytes=LOG_MAX_BYTES,
            backupCount=LOG_BACKUP_COUNT,
            encoding="utf-8",
        )
        # Plain formatter — the JSON structure carries all context
        handler.setFormatter(logging.Formatter("%(message)s"))

        self._logger = logging.getLogger("fda_audit")
        self._logger.setLevel(logging.DEBUG)
        self._logger.addHandler(handler)

        # Also echo WARN+ events to stderr so systemd/journald captures them
        stderr_handler = logging.StreamHandler()
        stderr_handler.setLevel(logging.CRITICAL)
        stderr_handler.setFormatter(logging.Formatter("%(message)s"))
        self._logger.addHandler(stderr_handler)

        # Sequence counter — monotonically increasing within a session.
        # A gap in sequence numbers indicates a missing/deleted log line.
        self._seq = 0

    def _write(self, level: str, category: str, event: str, details: dict):
        self._seq += 1
        ts = datetime.now(timezone.utc).isoformat()

        entry = {
            "ts":       ts,
            "seq":      self._seq,
            "device":   DEVICE_ID,
            "level":    level,
            "category": category,
            "event":    event,
            "details":  details,
        }

        # Serialise without the signature first, then sign the canonical string
        body = json.dumps(entry, separators=(",", ":"), sort_keys=True)
        entry["sig"] = _hmac_sign(body)

        line = json.dumps(entry, separators=(",", ":"), sort_keys=True)

        log_fn = {
            "DEBUG":    self._logger.debug,
            "INFO":     self._logger.info,
            "WARNING":  self._logger.warning,
            "ERROR":    self._logger.error,
            "CRITICAL": self._logger.critical,
        }.get(level, self._logger.info)

        log_fn(line)

    # --- Convenience methods per category ---

    def system(self, event: str, details: dict = None, level="INFO"):
        """System lifecycle events: boot, shutdown, config changes."""
        self._write(level, EventCategory.SYSTEM, event, details or {})

    def sensor(self, event: str, details: dict = None, level="INFO"):
        """Sensor hardware events: reads, FIFO state, hardware errors."""
        self._write(level, EventCategory.SENSOR, event, details or {})

    def data(self, event: str, details: dict = None, level="INFO"):
        """Data quality / analysis events: FFT results, anomalies."""
        self._write(level, EventCategory.DATA, event, details or {})

    def network(self, event: str, details: dict = None, level="INFO"):
        """Network/comms events: MQTT state, AWS upload success/failure."""
        self._write(level, EventCategory.NETWORK, event, details or {})

    def security(self, event: str, details: dict = None, level="WARNING"):
        """Security events: access attempts, integrity failures."""
        self._write(level, EventCategory.SECURITY, event, details or {})

    def watchdog(self, details: dict = None):
        """Periodic heartbeat — proves device is alive and logging."""
        self._write("DEBUG", EventCategory.WATCHDOG, "HEARTBEAT", details or {})


# --- Module-level singleton ---
audit = AuditLogger()
