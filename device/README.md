# Device — Raspberry Pi 5 acquisition node

Reads tremor data from an ADXL345 accelerometer over I2C, runs an FFT to
extract peak frequency in the 4–7 Hz Parkinsonian tremor band, and
publishes results to AWS IoT Core over mutual TLS.

## Files

| Path | Purpose |
|---|---|
| `acquisition_no_int_w_log.py` | Main loop — FIFO reads, FFT, publish, audit logging |
| `fft_analysis.py` | Frequency-domain analysis of accelerometer batches |
| `mqtt_client.py` | AWS IoT Core client (mutual TLS, SDK v2) |
| `device_logger.py` | Tamper-evident audit logging with HMAC signatures |
| `systemd/tremor_detector.service` | Hardened service unit |
| `scripts/` | Key generation, release signing, integrity-checked launch |
| `known_good/` | Reference copies plus SHA-256 baseline manifest |
| `log/` | Sample audit log from a bench run |

## Integrity chain

Nothing runs unless it verifies. `run.sh` performs two checks before
handing control to the acquisition process:

1. **Release signature** — `sign.sh` signs the release tarball with an
   RSA-2048 private key (`key_gen.sh`). `run.sh` verifies the detached
   signature against the public key held on the device. A device that
   only holds the public key cannot forge a release.
2. **File hashes** — every Python source file is checked against
   `known_good/checksums.sha256`. Any post-deployment modification fails
   the check and the service refuses to start.

The audit log is signed independently: each entry carries a truncated
HMAC over its contents, keyed from a secret loaded at startup from a
root-owned `640` file. Log entries cannot be forged or silently edited
by a process running as the service user.

## Service hardening

`systemd/tremor_detector.service` runs as a dedicated `nologin` user with
I2C group access only. It applies `ProtectSystem=strict`,
`NoNewPrivileges`, `ProtectHome`, `PrivateTmp`, and blocks kernel module
loading and tunable writes. SIGTERM is caught so a `DEVICE_SHUTDOWN`
entry is written before exit, and restart limits prevent boot loops.
The unit waits on `time-sync.target` — accurate UTC timestamps are a
traceability requirement, not a convenience.

## Running it

Deployment root is `/opt/tremor_detector`, overridable via `BAYMAX_HOME`.

Provision your own AWS IoT Thing and place the certificate, private key,
and Amazon root CA in `certs/` — see `certs/README.md`. Set the IoT
endpoint in `mqtt_client.py`.

Note: the service unit's `ExecStart` references `acquisition_no_int.py`,
the pre-logging entry point. The current script is
`acquisition_no_int_w_log.py`; update `ExecStart` to match.
