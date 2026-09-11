# Device audit log

Full bench capture (Pi 5 + ADXL345 on a desk, no human subject).

Each entry carries a per-session monotonic `seq` and a truncated HMAC
`sig`, giving tamper-evident, append-only logging for regulatory
traceability. Note the CRITICAL `MQTT_INIT_FAILED` entries — the device
refuses to publish when certificates are absent and records the refusal.

Infrastructure identifiers (IoT endpoint, certificate ID, host paths)
have been replaced with placeholders before publication. The signing key
is not published, so the `sig` values here are illustrative of the
format rather than verifiable.
