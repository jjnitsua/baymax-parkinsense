# ParkinSense

A Parkinson's tremor monitoring system: a wrist-worn Raspberry Pi node,
a serverless AWS backend, and a Flutter mobile app for patients,
clinicians, and caretakers.

> **Academic coursework.** Built for JHU EN.601.644 Medical Device
> Cybersecurity (Spring 2026). Never used with patients, never in
> production. This is not a medical device and is not FDA cleared.
> The AWS backend has been decommissioned — device certificates are
> inactive, the IoT rule is disabled, and the API stage is throttled to
> zero. All identifiers in this repository are placeholders.

![System architecture](docs/diagrams/system-data-flow.png)

## How it works

An ADXL345 accelerometer feeds a Raspberry Pi 5 over I2C at 100 Hz. The
Pi runs an FFT over each batch and extracts peak frequency in the 4–7 Hz
Parkinsonian tremor band, then publishes results to AWS IoT Core over
MQTT with mutual TLS. An IoT rule invokes a Lambda that writes processed
records to DynamoDB, archives raw data to S3 under Object Lock, and
raises SNS alerts past a severity threshold. The Flutter app
authenticates through Cognito and reads data via API Gateway, with
role-based access enforced server-side.

## Repository

| Path | Contents |
|---|---|
| [`device/`](device/) | Pi acquisition firmware, FFT analysis, MQTT client, audit logging, hardened systemd unit, release signing and integrity chain |
| [`cloud/`](cloud/) | Lambda functions, IoT policy and rule |
| [`app/`](app/) | Flutter application (iOS, Android, web, desktop) |
| [`docs/`](docs/) | Architecture, threat model, design controls, attack trees |

## Security design

Security was a design input, not a review step. Highlights:

- **Device identity** — per-device X.509 certificate with mutual TLS. The
  IoT policy permits connection only under one client ID and publication
  only to one topic, so a compromised device cannot impersonate another.
- **Server-side authorization** — the API Lambda derives identity from
  the validated Cognito JWT, never from request parameters. Patients see
  their own data, clinicians an assigned list, caretakers one patient.
- **Tamper-evident logging** — every audit entry carries a monotonic
  sequence number and an HMAC keyed from a root-owned secret file.
- **Verified execution** — releases are signed; the device verifies the
  signature and checks every source file against a SHA-256 baseline
  before starting.
- **Immutable archive** — S3 Object Lock in Governance mode, three-year
  retention, separate access-log bucket.
- **Service hardening** — dedicated nologin user, `ProtectSystem=strict`,
  `NoNewPrivileges`, no kernel module loading.

A ScoutSuite audit was run against the deployed account; all critical and
high findings were remediated.

## Regulatory documentation

The course followed FDA premarket cybersecurity guidance, ISO 14971, and
21 CFR 820.30 design controls.

- [Threat model](docs/threat-model.md) — 11 assets, 9 data flows, 8
  threat actors, 3 attack trees, STRIDE hazard analysis with pre- and
  post-mitigation risk scoring, 17 cybersecurity requirements
- [Design controls](docs/design-controls.md) — 18 user needs, 30 design
  inputs, 15 verification activities, fully traced
- [Cloud architecture](docs/architecture.md) — every AWS resource,
  schema, and design decision

## Team

| | |
|---|---|
| **Austin** | Cloud infrastructure and security — AWS backend, threat model, risk management |
| **Saanvi and Rex** | Device hardware and firmware — Pi, sensor, acquisition, signing |
| **Yadhveer** | Mobile application — Flutter app across iOS and Android |

## License

MIT — see [LICENSE](LICENSE).
