# Baymax / ParkinSense — Cloud Infrastructure Documentation v2

**Project:** Parkinson's Tremor Monitoring Device  
**Course:** EN.601.444/644 Medical Device Cybersecurity, Spring 2026  
**Author:** Austin (Cloud Infrastructure)  
**AWS Region:** us-east-1 (N. Virginia)  
**AWS Account ID:** <ACCOUNT_ID>  
**Last Updated:** May 1, 2026

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Architecture — Full System](#2-architecture--full-system)
3. [Sub-Architecture A — Device to Cloud (Pi ↔ AWS)](#3-sub-architecture-a--device-to-cloud-pi--aws)
4. [Sub-Architecture B — Cloud Internal Data Processing](#4-sub-architecture-b--cloud-internal-data-processing)
5. [Sub-Architecture C — Cloud to App (AWS ↔ Mobile)](#5-sub-architecture-c--cloud-to-app-aws--mobile)
6. [AWS Services Inventory](#6-aws-services-inventory)
7. [IAM and Account Security](#7-iam-and-account-security)
8. [AWS IoT Core](#8-aws-iot-core)
9. [AWS Lambda — Ingestion Function](#9-aws-lambda--ingestion-function)
10. [AWS Lambda — API Function](#10-aws-lambda--api-function)
11. [Amazon DynamoDB](#11-amazon-dynamodb)
12. [Amazon S3](#12-amazon-s3)
13. [Amazon SNS](#13-amazon-sns)
14. [Amazon Cognito](#14-amazon-cognito)
15. [Amazon API Gateway](#15-amazon-api-gateway)
16. [Amazon CloudWatch](#16-amazon-cloudwatch)
17. [Data Flow and Payload Specification](#17-data-flow-and-payload-specification)
18. [Alert Logic](#18-alert-logic)
19. [RBAC Logic](#19-rbac-logic)
20. [Context for Pi-Side Developers](#20-context-for-pi-side-developers)
21. [Context for Mobile App Developers](#21-context-for-mobile-app-developers)
22. [Current Design Constraints and Assumptions](#22-current-design-constraints-and-assumptions)
23. [Future Work](#23-future-work)
24. [Cost Considerations](#24-cost-considerations)
25. [Version History](#25-version-history)

---

## 1. System Overview

The Baymax cloud infrastructure serves two distinct purposes:

1. **Data Ingestion:** Receives processed tremor data from a Raspberry Pi 5 equipped with an ADXL345 accelerometer. The Pi performs edge-side FFT analysis on raw accelerometer samples and publishes frequency-domain tremor metrics to AWS over MQTT with mutual TLS authentication. The cloud pipeline stores, archives, and evaluates the data for alert conditions.

2. **Data Access:** Provides a secure REST API for the mobile app (Flutter, iOS + Android) to query tremor readings and alerts. Authentication is handled by Amazon Cognito with three user roles (patient, clinician, caretaker). Role-based access control is enforced server-side in the API Lambda function.

**Two data paths, two Lambda functions, one shared data layer:**

| Path | Direction | Transport | Lambda | Purpose |
|---|---|---|---|---|
| Ingestion | Pi → Cloud | MQTT/TLS (port 8883) | `baymax-process-tremor` | Store, archive, evaluate alerts |
| Access | Cloud → App | HTTPS (REST API) | `baymax-api-handler` | Query data, enforce RBAC |

Both paths read from and write to the same DynamoDB tables (`baymax-tremor-data` and `baymax-alerts`), ensuring the app always sees the latest device data.

---

## 2. Architecture — Full System

This diagram shows every component and how they connect end-to-end.

```
┌─────────────────────┐                                                          ┌─────────────────────┐
│   Raspberry Pi 5    │                                                          │   Mobile App        │
│   + ADXL345 sensor  │                                                          │   (Flutter)         │
│   + FFT analysis    │                                                          │   iOS + Android     │
│                     │                                                          │                     │
│   Publishes:        │                                                          │   3 Roles:          │
│   baymax/tremor-data│                                                          │   - Patient         │
│                     │                                                          │   - Clinician       │
│   Auth: X.509 certs │                                                          │   - Caretaker       │
│   mutual TLS        │                                                          │                     │
└────────┬────────────┘                                                          └──────────┬──────────┘
         │                                                                                  │
         │ MQTT over TLS                                                                    │ HTTPS
         │ Port 8883                                                                        │ REST API
         │                                                                                  │
         ▼                                                                                  ▼
┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    AWS Cloud (us-east-1)                                              │
│                                                                                                      │
│  ╔══════════════════════════════════════╗    ╔══════════════════════════════════════════════════════╗  │
│  ║  INGESTION PATH                     ║    ║  ACCESS PATH                                        ║  │
│  ║                                     ║    ║                                                      ║  │
│  ║  ┌──────────────────┐               ║    ║  ┌──────────────────┐    ┌──────────────────────┐   ║  │
│  ║  │  IoT Core        │               ║    ║  │  Cognito         │    │  API Gateway         │   ║  │
│  ║  │                  │               ║    ║  │  baymax-user-    │    │  baymax-api           │   ║  │
│  ║  │  Thing:          │               ║    ║  │  pool            │    │                      │   ║  │
│  ║  │  baymax-device-01│               ║    ║  │                  │    │  TLS 1.3             │   ║  │
│  ║  │                  │               ║    ║  │  3 groups:       │◄───│  Strict SNI          │   ║  │
│  ║  │  Rule:           │               ║    ║  │  patient         │JWT │  Cognito authorizer  │   ║  │
│  ║  │  baymax_tremor_  │               ║    ║  │  clinician       │val │                      │   ║  │
│  ║  │  rule            │               ║    ║  │  caretaker       │    │  Stage: /prod        │   ║  │
│  ║  └────────┬─────────┘               ║    ║  └──────────────────┘    └──────────┬───────────┘   ║  │
│  ║           │                         ║    ║                                     │               ║  │
│  ║           ▼                         ║    ║                                     ▼               ║  │
│  ║  ┌──────────────────┐               ║    ║                          ┌──────────────────────┐   ║  │
│  ║  │  Lambda          │               ║    ║                          │  Lambda              │   ║  │
│  ║  │  baymax-process- │               ║    ║                          │  baymax-api-handler  │   ║  │
│  ║  │  tremor          │               ║    ║                          │                      │   ║  │
│  ║  │                  │               ║    ║                          │  RBAC enforcement    │   ║  │
│  ║  │  Writes data     │               ║    ║                          │  Reads data          │   ║  │
│  ║  └──┬───┬───┬───┬───┘               ║    ║                          └───┬──────────┬───────┘   ║  │
│  ║     │   │   │   │                   ║    ║                              │          │           ║  │
│  ╚═════╪═══╪═══╪═══╪═══════════════════╝    ╚══════════════════════════════╪══════════╪═══════════╝  │
│        │   │   │   │                                                       │          │              │
│        │   │   │   │              ┌──────────────────────┐                 │          │              │
│        │   │   │   │              │  DynamoDB            │                 │          │              │
│        │   │   │   ├─── write ───►│  baymax-tremor-data  │◄── read ───────┘          │              │
│        │   │   │   │              └──────────────────────┘                            │              │
│        │   │   │   │                                                                 │              │
│        │   │   │   │              ┌──────────────────────┐                            │              │
│        │   │   │   └─── write ───►│  DynamoDB            │◄── read/update ────────────┘              │
│        │   │   │                  │  baymax-alerts        │                                           │
│        │   │   │                  └──────────────────────┘                                           │
│        │   │   │                                                                                     │
│        │   │   │                  ┌──────────────────────┐                                           │
│        │   │   └──── archive ────►│  S3 (archive)        │                                           │
│        │   │                      │  baymax-tremor-      │                                           │
│        │   │                      │  archive-8011        │                                           │
│        │   │                      │  Object Lock (Gov)   │                                           │
│        │   │                      └──────────┬───────────┘                                           │
│        │   │                                 │ server access logs                                    │
│        │   │                      ┌──────────▼───────────┐                                           │
│        │   │                      │  S3 (logs)           │                                           │
│        │   │                      │  baymax-access-log   │                                           │
│        │   │                      └──────────────────────┘                                           │
│        │   │                                                                                         │
│        │   │                      ┌──────────────────────┐    ┌──────────────────────┐               │
│        │   └──── alert email ────►│  SNS                 │───►│  Email Subscriber    │               │
│        │                          │  baymax-tremor-alerts │    └──────────────────────┘               │
│        │                          └──────────────────────┘                                           │
│        │                                                                                             │
│        │                          ┌──────────────────────┐                                           │
│        └──── error logs ─────────►│  CloudWatch          │                                           │
│                                   │  /iot/baymax-errors   │                                           │
│                                   │  /aws/lambda/...      │                                           │
│                                   │  spending alarm       │                                           │
│                                   └──────────────────────┘                                           │
│                                                                                                      │
└──────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Sub-Architecture A — Device to Cloud (Pi ↔ AWS)

This diagram focuses on how the Raspberry Pi communicates with AWS and what happens at the point of entry.

```
┌──────────────────────────────────────────────────────┐
│                  Raspberry Pi 5                       │
│                                                      │
│  ┌──────────┐    ┌──────────┐    ┌────────────────┐  │
│  │ ADXL345  │───►│  FFT     │───►│  MQTT Client   │  │
│  │ Accel.   │    │  Analysis │    │  (awsiotsdk)   │  │
│  │          │    │          │    │                │  │
│  │ Raw XYZ  │    │ 4-7 Hz   │    │ Publishes to:  │  │
│  │ @ 100 Hz │    │ band     │    │ baymax/        │  │
│  │          │    │ summary  │    │ tremor-data    │  │
│  └──────────┘    └──────────┘    └───────┬────────┘  │
│                                          │           │
│  Cert files on device:                   │           │
│  • baymax-device-01.cert.pem             │           │
│  • baymax-device-01.private.key          │           │
│  • AmazonRootCA1.pem                    │           │
│                                          │           │
│  Security:                               │           │
│  • LUKS full-disk encryption             │           │
│  • dm-verity integrity checking          │           │
│  • Headless SSH access only              │           │
└──────────────────────────────────────────┼───────────┘
                                           │
                                           │ MQTT over TLS 1.2+
                                           │ Port 8883
                                           │ Mutual TLS (X.509)
                                           │ Client ID: baymax-device-01
                                           │ QoS 1 (at least once)
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                     AWS IoT Core (us-east-1)                    │
│                                                                 │
│  ┌─────────────────────────────┐                                │
│  │  Thing: baymax-device-01    │                                │
│  │                             │                                │
│  │  Policy: baymax-device-     │                                │
│  │  policy                     │                                │
│  │  • Connect: baymax-device-01│                                │
│  │  • Publish: baymax/         │                                │
│  │    tremor-data              │                                │
│  │  • Subscribe: baymax/       │                                │
│  │    commands/* (future)      │                                │
│  │                             │                                │
│  │  Shadow: classic (unused)   │                                │
│  └─────────────┬───────────────┘                                │
│                │                                                │
│                ▼                                                │
│  ┌─────────────────────────────┐    ┌────────────────────────┐  │
│  │  Rule: baymax_tremor_rule   │    │  Error Action:         │  │
│  │                             │───►│  CloudWatch            │  │
│  │  SQL: SELECT * FROM         │err │  /iot/baymax-errors    │  │
│  │  'baymax/tremor-data'       │    └────────────────────────┘  │
│  │                             │                                │
│  │  Action: Invoke Lambda      │                                │
│  └─────────────┬───────────────┘                                │
│                │                                                │
└────────────────┼────────────────────────────────────────────────┘
                 │
                 │ Full JSON payload passed to Lambda
                 ▼
        ┌────────────────────┐
        │  Lambda            │
        │  baymax-process-   │
        │  tremor            │
        │  (see Section 9)   │
        └────────────────────┘
```

**Payload transmitted (Pi → IoT Core):**
```json
{
  "patient_id": "patient-001",
  "timestamp": 1777511600579,
  "band_summary": {
    "band_hz": [4.0, 7.0],
    "x": { "peak_hz": 5.5, "peak_amp_g": 0.045, "mean_amp_g": 0.02 },
    "y": { "peak_hz": 4.8, "peak_amp_g": 0.012, "mean_amp_g": 0.008 },
    "z": { "peak_hz": 6.1, "peak_amp_g": 0.038, "mean_amp_g": 0.015 }
  }
}
```

**Security controls on this path:**
- Mutual TLS with X.509 certificates (device identity)
- IoT policy scoped to single client ID and single publish topic
- Private key never leaves the device
- LUKS encryption on the SD card protects certs at rest

---

## 4. Sub-Architecture B — Cloud Internal Data Processing

This diagram shows what happens inside the cloud once data arrives — how it's stored, archived, evaluated, and logged.

```
                    Incoming MQTT message (from IoT Core rule)
                                    │
                                    ▼
                    ┌──────────────────────────────┐
                    │  Lambda: baymax-process-tremor │
                    │  Python 3.12, 128 MB, 3s      │
                    │                                │
                    │  1. Parse patient_id,           │
                    │     timestamp, band_summary     │
                    │  2. Flatten per-axis metrics     │
                    │  3. Convert floats → Decimal     │
                    │  4. Store → DynamoDB             │
                    │  5. Archive → S3                 │
                    │  6. Evaluate → alert threshold   │
                    │  7. If alert → DynamoDB + SNS    │
                    └──┬─────┬──────┬──────┬──────────┘
                       │     │      │      │
          ┌────────────┘     │      │      └────────────────┐
          │                  │      │                       │
          ▼                  ▼      ▼                       ▼
┌──────────────────┐  ┌──────────────────┐  ┌─────────────────────────┐
│  DynamoDB        │  │  DynamoDB        │  │  S3                      │
│  baymax-tremor-  │  │  baymax-alerts   │  │  baymax-tremor-archive-  │
│  data            │  │                  │  │  8011                    │
│                  │  │  Written only    │  │                          │
│  Every message   │  │  when threshold  │  │  Every message archived  │
│  stored here     │  │  exceeded        │  │  as raw JSON             │
│                  │  │                  │  │                          │
│  PK: patient_id  │  │  PK: patient_id  │  │  Key: {patient_id}/     │
│  SK: timestamp   │  │  SK: timestamp   │  │    {timestamp}.json      │
│                  │  │  read: false     │  │                          │
│  On-demand       │  │  On-demand       │  │  Object Lock: Governance │
│  capacity        │  │  capacity        │  │  Retention: 3 years      │
│                  │  │                  │  │  Encryption: SSE-S3      │
│                  │  │                  │  │  Versioning: enabled     │
└──────────────────┘  └──────────────────┘  └────────────┬────────────┘
                               │                         │
                               │                         │ Server access
                               │                         │ logs (automatic)
                               ▼                         ▼
                      ┌──────────────────┐  ┌─────────────────────────┐
                      │  SNS             │  │  S3                      │
                      │  baymax-tremor-  │  │  baymax-access-log       │
                      │  alerts          │  │                          │
                      │                  │  │  Object Lock: Governance │
                      │  Alert email     │  │  Retention: 3 years      │
                      │  sent only when  │  │  Encryption: SSE-S3      │
                      │  threshold       │  │                          │
                      │  exceeded        │  │  Who accessed the        │
                      │                  │  │  archive and when        │
                      └────────┬─────────┘  └─────────────────────────┘
                               │
                               ▼
                      ┌──────────────────┐
                      │  Email           │
                      │  Subscriber      │
                      │  (team email)    │
                      └──────────────────┘


                    ┌──────────────────────────────────────┐
                    │  CloudWatch (monitoring & logging)    │
                    │                                      │
                    │  Log Groups:                         │
                    │  • /aws/lambda/baymax-process-tremor  │
                    │  • /aws/lambda/baymax-api-handler     │
                    │  • /iot/baymax-errors                 │
                    │                                      │
                    │  Alarms:                             │
                    │  • spending-over-5-dollars → SNS     │
                    │    → billing-alerts → email          │
                    └──────────────────────────────────────┘
```

**Data transformations:**

| Stage | Input Format | Output Format | Where |
|---|---|---|---|
| Pi FFT | Raw XYZ samples @ 100 Hz | `band_summary` dict with per-axis peak/mean in 4–7 Hz band | On-device |
| MQTT payload | Nested JSON (`band_summary.x.peak_hz`) | Same nested JSON | Over the wire |
| Lambda flattening | Nested JSON | Flat fields (`x_peak_hz`, `x_peak_amp_g`, etc.) + Decimal conversion | `baymax-process-tremor` |
| DynamoDB storage | Flat Decimal fields | Queryable records with `patient_id` + `timestamp` keys | `baymax-tremor-data` |
| S3 archival | Original nested JSON (no transformation) | Immutable raw record | `baymax-tremor-archive-8011` |
| Alert evaluation | Per-axis `peak_amp_g` vs threshold (0.03 G) | Alert record if any axis exceeds | `baymax-alerts` + SNS |

---

## 5. Sub-Architecture C — Cloud to App (AWS ↔ Mobile)

This diagram shows how the mobile app authenticates and accesses data through the API layer.

```
┌──────────────────────────────────────────────────────────────┐
│                     Mobile App (Flutter)                      │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │ Login Screen │  │ Data Screen  │  │ Alerts Screen    │   │
│  │              │  │              │  │                  │   │
│  │ Email +      │  │ GET readings │  │ GET alerts       │   │
│  │ Password     │  │              │  │ PUT mark read    │   │
│  └──────┬───────┘  └──────┬───────┘  └────────┬─────────┘   │
│         │                 │                    │             │
│         │                 └────────┬───────────┘             │
│         │                         │                         │
│         ▼                         ▼                         │
│  ┌──────────────┐  ┌──────────────────────────────────────┐ │
│  │ Cognito SDK  │  │ HTTP Client                          │ │
│  │              │  │ Authorization: <IdToken>              │ │
│  │ SRP Auth     │  │ GET /patients/{id}/readings           │ │
│  │ Returns:     │  │ GET /patients/{id}/alerts             │ │
│  │ • IdToken    │  │ GET /patients/{id}/alerts?unread=true  │ │
│  │ • AccessToken│  │ PUT /patients/{id}/alerts/{timestamp} │ │
│  │ • RefreshTkn │  │ GET /clinician/patients               │ │
│  └──────┬───────┘  └──────────────────┬───────────────────┘ │
│         │                             │                     │
└─────────┼─────────────────────────────┼─────────────────────┘
          │                             │
          │ SRP Auth                    │ HTTPS + JWT
          │ (password never             │ in Authorization
          │  sent over wire)            │ header
          │                             │
          ▼                             ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                         AWS Cloud (us-east-1)                           │
│                                                                         │
│  ┌──────────────────────┐         ┌──────────────────────────────────┐  │
│  │  Cognito User Pool   │         │  API Gateway: baymax-api         │  │
│  │  baymax-user-pool     │         │                                  │  │
│  │                       │         │  Regional REST API               │  │
│  │  App Client:          │◄────────│  TLS 1.3 / Strict SNI           │  │
│  │  baymax-mobile-app    │  JWT    │                                  │  │
│  │  (public, no secret)  │validate │  Authorizer:                     │  │
│  │                       │         │  baymax-cognito-auth             │  │
│  │  Custom attributes:   │         │  (validates IdToken,             │  │
│  │  • custom:role        │         │   passes claims to Lambda)       │  │
│  │  • custom:patient_id  │         │                                  │  │
│  │  • custom:assigned_   │         │  Resources:                      │  │
│  │    patients           │         │  /patients/{id}/readings    GET  │  │
│  │                       │         │  /patients/{id}/alerts      GET  │  │
│  │  Groups:              │         │  /patients/{id}/alerts/          │  │
│  │  • patient            │         │    {timestamp}              PUT  │  │
│  │  • clinician          │         │  /clinician/patients        GET  │  │
│  │  • caretaker          │         │                                  │  │
│  └──────────────────────┘         └───────────────┬──────────────────┘  │
│                                                   │                     │
│                                                   │ Lambda proxy        │
│                                                   │ integration         │
│                                                   ▼                     │
│                                   ┌──────────────────────────────────┐  │
│                                   │  Lambda: baymax-api-handler      │  │
│                                   │  Python 3.12, 128 MB, 10s        │  │
│                                   │                                  │  │
│                                   │  1. Extract claims from JWT:     │  │
│                                   │     custom:role                   │  │
│                                   │     custom:patient_id             │  │
│                                   │     custom:assigned_patients      │  │
│                                   │                                  │  │
│                                   │  2. RBAC check:                  │  │
│                                   │     patient/caretaker →          │  │
│                                   │       patient_id must match      │  │
│                                   │     clinician →                  │  │
│                                   │       requested ID must be in    │  │
│                                   │       assigned_patients list     │  │
│                                   │                                  │  │
│                                   │  3. If denied → 403             │  │
│                                   │     If allowed → query DynamoDB  │  │
│                                   │                                  │  │
│                                   │  4. Return clean JSON array      │  │
│                                   │     (Decimal → float/int)        │  │
│                                   └─────────┬──────────┬─────────────┘  │
│                                             │          │                │
│                               ┌─────────────┘          └──────────┐    │
│                               ▼                                   ▼    │
│                  ┌──────────────────────┐          ┌──────────────────┐ │
│                  │  DynamoDB            │          │  DynamoDB        │ │
│                  │  baymax-tremor-data  │          │  baymax-alerts   │ │
│                  │                      │          │                  │ │
│                  │  Read: query by      │          │  Read: query by  │ │
│                  │  patient_id +        │          │  patient_id,     │ │
│                  │  optional time range │          │  filter unread   │ │
│                  │                      │          │                  │ │
│                  │                      │          │  Update: set     │ │
│                  │                      │          │  read = true     │ │
│                  └──────────────────────┘          └──────────────────┘ │
│                                                                         │
│  For GET /clinician/patients:                                           │
│  Lambda also queries Cognito User Pool                                  │
│  to look up patient names by custom:patient_id                          │
│  (filters for custom:role = "patient" only)                             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Response flow (App ← API):**

| Endpoint | DynamoDB Table | Response Shape |
|---|---|---|
| `GET /patients/{id}/readings` | `baymax-tremor-data` | Array of flat tremor records (snake_case keys) |
| `GET /patients/{id}/alerts` | `baymax-alerts` | Array of alert records with `details` as list of objects |
| `PUT /patients/{id}/alerts/{ts}` | `baymax-alerts` | `{"message": "Alert marked as read"}` |
| `GET /clinician/patients` | Cognito User Pool | Array of `{patient_id, name}` objects |

---

## 6. AWS Services Inventory

### Ingestion Path Services

| Service | Resource Name | Purpose |
|---|---|---|
| IoT Core | `baymax-device-01` (Thing) | Registered IoT device for the Pi |
| IoT Core | `baymax-device-policy` (Policy) | Permissions for device MQTT operations |
| IoT Core | `baymax_tremor_rule` (Rule) | Routes MQTT messages to Lambda |
| IoT Core | `baymax-iot-error-role` (IAM Role) | Allows IoT Core to write error logs |
| Lambda | `baymax-process-tremor` (Function) | Processes tremor data, stores, alerts |
| S3 | `baymax-tremor-archive-8011` (Bucket) | Immutable raw data archive |
| S3 | `baymax-access-log` (Bucket) | Server access logs for the archive bucket |
| SNS | `baymax-tremor-alerts` (Topic) | Alert notification delivery (currently email) |

### Access Path Services

| Service | Resource Name | Purpose |
|---|---|---|
| Cognito | `baymax-user-pool` (User Pool) | Authentication + user attributes for RBAC |
| Cognito | `baymax-mobile-app` (App Client) | Public app client for mobile login |
| API Gateway | `baymax-api` (REST API) | HTTPS endpoint for mobile app |
| API Gateway | `baymax-cognito-auth` (Authorizer) | Validates Cognito JWT tokens |
| Lambda | `baymax-api-handler` (Function) | Routes API requests, enforces RBAC, queries data |

### Shared Services

| Service | Resource Name | Purpose |
|---|---|---|
| IAM | `austin-admin` (user) | Admin IAM user with MFA |
| DynamoDB | `baymax-tremor-data` (Table) | Stores processed tremor readings (written by ingestion, read by API) |
| DynamoDB | `baymax-alerts` (Table) | Stores alert records (written by ingestion, read/updated by API) |
| SNS | `billing-alerts` (Topic) | Billing alarm notifications |
| CloudWatch | `spending-over-5-dollars` (Alarm) | Alerts if AWS spending exceeds $5 |
| CloudWatch | `/iot/baymax-errors` (Log Group) | IoT rule error logs |
| CloudWatch | `/aws/lambda/baymax-process-tremor` (Log Group) | Ingestion Lambda execution logs |
| CloudWatch | `/aws/lambda/baymax-api-handler` (Log Group) | API Lambda execution logs |

---

## 7. IAM and Account Security

**Root account:** MFA enabled. Not used for day-to-day operations.

**IAM user:** `austin-admin` with `AdministratorAccess` managed policy and console access. Billing access enabled for this IAM user.

**Ingestion Lambda execution role:** Auto-created role with the following attached policies:
- `AWSLambdaBasicExecutionRole` (CloudWatch Logs)
- `AmazonDynamoDBFullAccess`
- `AmazonS3FullAccess`
- `AmazonSNSFullAccess`

**API Lambda execution role:** Auto-created role with the following attached policies:
- `AWSLambdaBasicExecutionRole` (CloudWatch Logs)
- `AmazonDynamoDBReadOnlyAccess` (query tremor data and alerts)
- `AmazonCognitoReadOnly` (look up patient names for clinician endpoint)
- `baymax-alerts-update-policy` (inline — `dynamodb:UpdateItem` on `arn:aws:dynamodb:us-east-1:<ACCOUNT_ID>:table/baymax-alerts`)

> **Production note:** These broad managed policies are acceptable for the class project. In production, both Lambda roles should be scoped down to the specific table ARNs, bucket ARN, and topic ARN using least-privilege inline policies.

---

## 8. AWS IoT Core

### Thing

- **Name:** `baymax-device-01`
- **Shadow:** Unnamed shadow (classic) — enabled but not currently used. Available for future config sync (e.g., pushing sampling rate or threshold changes to the device).

### Certificates

- **Type:** Auto-generated X.509 certificates (mutual TLS)
- **Status:** Active
- **Files:** Four files downloaded and stored securely:
  - Device certificate (`.pem.crt`)
  - Private key (`.pem.key`)
  - Public key (`.pem.key`)
  - Amazon Root CA

> **Critical:** The private key cannot be re-downloaded. These files must be transferred to the Raspberry Pi for MQTT connectivity.

### IoT Policy: `baymax-device-policy`

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:us-east-1:<ACCOUNT_ID>:client/baymax-device-01"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": "arn:aws:iot:us-east-1:<ACCOUNT_ID>:topic/baymax/tremor-data"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": "arn:aws:iot:us-east-1:<ACCOUNT_ID>:topicfilter/baymax/commands/*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Receive",
      "Resource": "arn:aws:iot:us-east-1:<ACCOUNT_ID>:topic/baymax/commands/*"
    }
  ]
}
```

**What this allows:**
- Connect with client ID `baymax-device-01` only
- Publish to `baymax/tremor-data` (one-way data upload)
- Subscribe to `baymax/commands/*` (for future device config updates via Device Shadow or direct commands)

### IoT Rule: `baymax_tremor_rule`

- **SQL:** `SELECT * FROM 'baymax/tremor-data'`
- **SQL Version:** 2016-03-23
- **Action:** Invoke Lambda `baymax-process-tremor`
- **Error action:** Write to CloudWatch Log Group `/iot/baymax-errors`

### IoT Core Endpoint

To find the endpoint URL (needed for Pi-side MQTT client):

```
AWS Console → IoT Core → Settings → Device data endpoint
```

It will look like: `xxxxxxxxxxxxxx-ats.iot.us-east-1.amazonaws.com`

---

## 9. AWS Lambda — Ingestion Function

### Function: `baymax-process-tremor`

- **Runtime:** Python 3.12
- **Architecture:** x86_64
- **Memory:** 128 MB (default)
- **Timeout:** 3 seconds (default — sufficient for current workload)
- **Trigger:** AWS IoT Core rule `baymax_tremor_rule`

### Environment Variables

| Variable | Value | Description |
|---|---|---|
| `TREMOR_TABLE` | `baymax-tremor-data` | DynamoDB table for tremor readings |
| `ALERTS_TABLE` | `baymax-alerts` | DynamoDB table for alert records |
| `S3_BUCKET` | `baymax-tremor-archive-8011` | S3 bucket for raw data archive |
| `SNS_TOPIC_ARN` | `arn:aws:sns:us-east-1:<ACCOUNT_ID>:baymax-tremor-alerts` | SNS topic for notifications |
| `TREMOR_THRESHOLD` | `0.03` | Peak amplitude threshold in G (optional, defaults to 0.03) |

### Function Logic Summary

1. Parse incoming event for `patient_id`, `timestamp`, and `band_summary`.
2. Extract per-axis metrics (peak_hz, peak_amp_g, mean_amp_g) and convert floats to `Decimal` for DynamoDB compatibility.
3. Write the flattened record to `baymax-tremor-data`.
4. Archive the full raw JSON payload to S3 at key `{patient_id}/{timestamp}.json`.
5. Compare each axis's `peak_amp_g` against `TREMOR_THRESHOLD`. If any axis exceeds the threshold:
   - Write an alert record to `baymax-alerts`.
   - Publish an alert message to SNS.
6. Return a summary response with storage confirmation and alert count.

### Full Source Code

```python
import json
import boto3
import time
import os
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
s3 = boto3.client("s3")
sns = boto3.client("sns")

TREMOR_TABLE = os.environ["TREMOR_TABLE"]
ALERTS_TABLE = os.environ["ALERTS_TABLE"]
S3_BUCKET = os.environ["S3_BUCKET"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
TREMOR_THRESHOLD = float(os.environ.get("TREMOR_THRESHOLD", "0.03"))

tremor_table = dynamodb.Table(TREMOR_TABLE)
alerts_table = dynamodb.Table(ALERTS_TABLE)


def lambda_handler(event, context):
    patient_id = event.get("patient_id", "unknown")
    timestamp = event.get("timestamp") or int(time.time() * 1000)
    band = event.get("band_summary", {})

    # 1. Write to DynamoDB tremor table
    item = {
        "patient_id": patient_id,
        "timestamp": timestamp,
        "band_hz": convert_decimal(band.get("band_hz", [4.0, 7.0])),
    }

    for axis in ["x", "y", "z"]:
        axis_data = band.get(axis, {})
        item[f"{axis}_peak_hz"] = convert_decimal(axis_data.get("peak_hz"))
        item[f"{axis}_peak_amp_g"] = convert_decimal(axis_data.get("peak_amp_g"))
        item[f"{axis}_mean_amp_g"] = convert_decimal(axis_data.get("mean_amp_g"))

    tremor_table.put_item(Item=item)

    # 2. Archive raw payload to S3
    s3_key = f"{patient_id}/{timestamp}.json"
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=s3_key,
        Body=json.dumps(event),
        ContentType="application/json",
    )

    # 3. Check for alert conditions
    alerts = []
    for axis in ["x", "y", "z"]:
        axis_data = band.get(axis, {})
        peak_amp = axis_data.get("peak_amp_g")
        if peak_amp is not None and peak_amp > TREMOR_THRESHOLD:
            alerts.append({
                "axis": axis,
                "peak_hz": axis_data.get("peak_hz"),
                "peak_amp_g": peak_amp,
            })

    if alerts:
        alert_record = {
            "patient_id": patient_id,
            "timestamp": timestamp,
            "alert_type": "high_tremor",
            "severity": "warning",
            "message": f"Tremor threshold exceeded on "
                       f"{', '.join(a['axis'].upper() for a in alerts)} axis",
            "details": convert_decimal(alerts),
            "read": False,
        }
        alerts_table.put_item(Item=alert_record)

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"Tremor Alert - {patient_id}",
            Message=json.dumps(alert_record, default=str, indent=2),
        )

    return {
        "statusCode": 200,
        "body": {
            "stored": True,
            "archived": s3_key,
            "alerts_triggered": len(alerts),
        },
    }


def convert_decimal(obj):
    if isinstance(obj, float):
        return Decimal(str(obj))
    elif isinstance(obj, list):
        return [convert_decimal(i) for i in obj]
    elif isinstance(obj, dict):
        return {k: convert_decimal(v) for k, v in obj.items()}
    return obj
```

---

## 10. AWS Lambda — API Function

### Function: `baymax-api-handler`

- **Runtime:** Python 3.12
- **Architecture:** x86_64
- **Memory:** 128 MB
- **Timeout:** 10 seconds
- **Trigger:** API Gateway `baymax-api` (Lambda proxy integration)

### Environment Variables

| Variable | Value | Description |
|---|---|---|
| `TREMOR_TABLE` | `baymax-tremor-data` | DynamoDB table for tremor readings |
| `ALERTS_TABLE` | `baymax-alerts` | DynamoDB table for alert records |
| `USER_POOL_ID` | `<COGNITO_USER_POOL_ID>` | Cognito User Pool for patient name lookups |

### Function Logic Summary

1. Route the request based on `httpMethod` + `resource` path.
2. Extract RBAC claims (`custom:role`, `custom:patient_id`, `custom:assigned_patients`) from the Cognito token via `event.requestContext.authorizer.claims`.
3. Call `authorize()` to check if the caller can access the requested patient ID.
4. If denied, return `403 {"error": "Access denied"}`.
5. If allowed:
   - **Readings:** Query `baymax-tremor-data` by `patient_id`, optional time range, newest first.
   - **Alerts:** Query `baymax-alerts` by `patient_id`, optional `unread=true` filter, newest first.
   - **Mark read:** Update the alert's `read` field to `true`.
   - **Clinician patients:** Iterate `custom:assigned_patients`, look up each patient's `name` from Cognito (filtering for `custom:role = "patient"` to avoid returning caretaker names).
6. Convert all `Decimal` types to JSON-safe `int`/`float` and return with CORS headers.

### Full Source Code

```python
import json
import boto3
import os
from decimal import Decimal
from boto3.dynamodb.conditions import Key, Attr

dynamodb = boto3.resource("dynamodb")
cognito = boto3.client("cognito-idp")

TREMOR_TABLE = os.environ["TREMOR_TABLE"]
ALERTS_TABLE = os.environ["ALERTS_TABLE"]
USER_POOL_ID = os.environ["USER_POOL_ID"]

tremor_table = dynamodb.Table(TREMOR_TABLE)
alerts_table = dynamodb.Table(ALERTS_TABLE)


def lambda_handler(event, context):
    """Main router — dispatches to the correct handler based on method + path."""
    try:
        http_method = event.get("httpMethod", "")
        resource = event.get("resource", "")
        path_params = event.get("pathParameters") or {}
        query_params = event.get("queryStringParameters") or {}
        claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})

        # Extract RBAC info from JWT claims
        role = claims.get("custom:role", "")
        caller_patient_id = claims.get("custom:patient_id", "")
        assigned_patients_raw = claims.get("custom:assigned_patients", "")
        assigned_patients = [p.strip() for p in assigned_patients_raw.split(",") if p.strip()]
        caller_name = claims.get("name", "")
        caller_email = claims.get("email", "")

        # Route to handler
        if resource == "/patients/{id}/readings" and http_method == "GET":
            patient_id = path_params.get("id", "")
            if not authorize(role, caller_patient_id, assigned_patients, patient_id):
                return response(403, {"error": "Access denied"})
            return get_readings(patient_id, query_params)

        elif resource == "/patients/{id}/alerts" and http_method == "GET":
            patient_id = path_params.get("id", "")
            if not authorize(role, caller_patient_id, assigned_patients, patient_id):
                return response(403, {"error": "Access denied"})
            return get_alerts(patient_id, query_params)

        elif resource == "/patients/{id}/alerts/{timestamp}" and http_method == "PUT":
            patient_id = path_params.get("id", "")
            timestamp = path_params.get("timestamp", "")
            if not authorize(role, caller_patient_id, assigned_patients, patient_id):
                return response(403, {"error": "Access denied"})
            return mark_alert_read(patient_id, timestamp)

        elif resource == "/clinician/patients" and http_method == "GET":
            if role != "clinician":
                return response(403, {"error": "Access denied — clinicians only"})
            return get_clinician_patients(assigned_patients)

        else:
            return response(404, {"error": f"Not found: {http_method} {resource}"})

    except Exception as e:
        print(f"Error: {str(e)}")
        return response(500, {"error": "Internal server error"})


def authorize(role, caller_patient_id, assigned_patients, requested_patient_id):
    """
    RBAC check — returns True if the caller is allowed to access the requested patient's data.

    - patient: can only access their own data (custom:patient_id must match)
    - caretaker: can only access their monitored patient (custom:patient_id must match)
    - clinician: can access any patient in their custom:assigned_patients list
    """
    if role in ("patient", "caretaker"):
        return caller_patient_id == requested_patient_id
    elif role == "clinician":
        return requested_patient_id in assigned_patients
    return False


def get_readings(patient_id, query_params):
    """GET /patients/{id}/readings — with optional ?from=<ms>&to=<ms> range."""
    from_ts = query_params.get("from")
    to_ts = query_params.get("to")

    if from_ts and to_ts:
        result = tremor_table.query(
            KeyConditionExpression=Key("patient_id").eq(patient_id)
            & Key("timestamp").between(int(from_ts), int(to_ts)),
            ScanIndexForward=False,
        )
    else:
        result = tremor_table.query(
            KeyConditionExpression=Key("patient_id").eq(patient_id),
            ScanIndexForward=False,
        )

    items = convert_decimals(result.get("Items", []))
    return response(200, items)


def get_alerts(patient_id, query_params):
    """GET /patients/{id}/alerts — with optional ?unread=true filter."""
    unread_only = query_params.get("unread", "").lower() == "true"

    if unread_only:
        result = alerts_table.query(
            KeyConditionExpression=Key("patient_id").eq(patient_id),
            FilterExpression=Attr("read").eq(False),
            ScanIndexForward=False,
        )
    else:
        result = alerts_table.query(
            KeyConditionExpression=Key("patient_id").eq(patient_id),
            ScanIndexForward=False,
        )

    items = convert_decimals(result.get("Items", []))
    return response(200, items)


def mark_alert_read(patient_id, timestamp_str):
    """PUT /patients/{id}/alerts/{timestamp} — mark an alert as read."""
    try:
        timestamp = int(timestamp_str)
    except ValueError:
        return response(400, {"error": "Invalid timestamp"})

    alerts_table.update_item(
        Key={"patient_id": patient_id, "timestamp": timestamp},
        UpdateExpression="SET #r = :val",
        ExpressionAttributeNames={"#r": "read"},
        ExpressionAttributeValues={":val": True},
    )

    return response(200, {"message": "Alert marked as read"})


def get_clinician_patients(assigned_patients):
    """
    GET /clinician/patients — returns patient IDs and names.
    Looks up each patient's name from Cognito by matching custom:patient_id.
    """
    patients = []

    for pid in assigned_patients:
        name = lookup_patient_name(pid)
        patients.append({"patient_id": pid, "name": name})

    return response(200, patients)


def lookup_patient_name(patient_id):
    """Look up a patient's display name from Cognito by matching custom:patient_id and role=patient."""
    try:
        paginator = cognito.get_paginator("list_users")
        for page in paginator.paginate(UserPoolId=USER_POOL_ID):
            for user in page.get("Users", []):
                attrs = {a["Name"]: a["Value"] for a in user.get("Attributes", [])}
                if attrs.get("custom:patient_id") == patient_id and attrs.get("custom:role") == "patient":
                    return attrs.get("name", attrs.get("email", patient_id))
        return patient_id
    except Exception as e:
        print(f"Error looking up patient {patient_id}: {e}")
        return patient_id


def convert_decimals(obj):
    """Recursively convert Decimal types to int or float for JSON serialization."""
    if isinstance(obj, Decimal):
        if obj % 1 == 0:
            return int(obj)
        return float(obj)
    elif isinstance(obj, list):
        return [convert_decimals(i) for i in obj]
    elif isinstance(obj, dict):
        return {k: convert_decimals(v) for k, v in obj.items()}
    return obj


def response(status_code, body):
    """Build an API Gateway proxy response with CORS headers."""
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization",
            "Access-Control-Allow-Methods": "GET,PUT,OPTIONS",
        },
        "body": json.dumps(body, default=str),
    }
```

---

## 11. Amazon DynamoDB

### Table: `baymax-tremor-data`

Stores processed tremor readings from each FFT batch. **Written by** the ingestion Lambda, **read by** the API Lambda.

- **Partition key:** `patient_id` (String)
- **Sort key:** `timestamp` (Number — Unix epoch in milliseconds)
- **Capacity mode:** On-demand

**Record schema:**

| Field | Type | Description |
|---|---|---|
| `patient_id` | String | Unique patient identifier |
| `timestamp` | Number | Unix epoch in milliseconds |
| `band_hz` | List | Frequency band analyzed, e.g. [4.0, 7.0] |
| `x_peak_hz` | Number | Peak frequency on X-axis within band (Hz) |
| `x_peak_amp_g` | Number | Peak amplitude on X-axis within band (G) |
| `x_mean_amp_g` | Number | Mean amplitude on X-axis within band (G) |
| `y_peak_hz` | Number | Peak frequency on Y-axis within band (Hz) |
| `y_peak_amp_g` | Number | Peak amplitude on Y-axis within band (G) |
| `y_mean_amp_g` | Number | Mean amplitude on Y-axis within band (G) |
| `z_peak_hz` | Number | Peak frequency on Z-axis within band (Hz) |
| `z_peak_amp_g` | Number | Peak amplitude on Z-axis within band (G) |
| `z_mean_amp_g` | Number | Mean amplitude on Z-axis within band (G) |

**Common query patterns:**
- All readings for a patient: Query on `patient_id`
- Readings in a time range: Query on `patient_id` with sort key between `start_ts` and `end_ts`
- Latest N readings: Query on `patient_id` with `ScanIndexForward=False` and `Limit=N`

### Table: `baymax-alerts`

Stores alert records triggered when tremor amplitude exceeds threshold. **Written by** the ingestion Lambda, **read and updated by** the API Lambda.

- **Partition key:** `patient_id` (String)
- **Sort key:** `timestamp` (Number — Unix epoch in milliseconds)
- **Capacity mode:** On-demand

**Record schema:**

| Field | Type | Description |
|---|---|---|
| `patient_id` | String | Patient who triggered the alert |
| `timestamp` | Number | Unix epoch in milliseconds |
| `alert_type` | String | Alert category, currently `"high_tremor"` |
| `severity` | String | Alert severity, currently `"warning"` |
| `message` | String | Human-readable description |
| `details` | List | Per-axis details of which axes exceeded threshold |
| `read` | Boolean | Whether the alert has been viewed in the app |

**Common query patterns:**
- Unread alerts for a patient: Query on `patient_id`, filter `read = false`
- Alert history: Query on `patient_id` with sort key range
- Mark alert as read: Update item, set `read = true`

---

## 12. Amazon S3

### Bucket: `baymax-tremor-archive-8011`

Immutable archive of raw tremor payloads for audit trail and regulatory compliance.

- **Region:** us-east-1
- **Public access:** Fully blocked (all four Block Public Access settings enabled)
- **Versioning:** Enabled (required for Object Lock)
- **Encryption:** SSE-S3 (AES-256 server-side encryption at rest)
- **Object Lock:** Enabled
  - **Mode:** Governance
  - **Default retention:** 3 years (1095 days)
- **Server Access Logging:** Enabled, logs delivered to `baymax-access-log` bucket

**Key structure:** `{patient_id}/{timestamp}.json`

**Example:** `patient-001/1713700000000.json`

**Governance mode notes:**
- Objects cannot be deleted or overwritten during the retention period under normal circumstances.
- An IAM user with `s3:BypassGovernanceRetention` permission (e.g., `austin-admin` via `AdministratorAccess`) can override if needed.
- Production deployment should upgrade to Compliance mode, where even root cannot delete objects during retention.

> **Regulatory context:** This bucket supports data integrity requirements (NHM6 in the CRM Evaluation spreadsheet) and provides an immutable audit trail for FDA postmarket cybersecurity documentation.

### Bucket: `baymax-access-log`

Stores S3 server access logs for the `baymax-tremor-archive-8011` bucket. Provides an audit trail of who accessed the tremor data archive and when.

- **Region:** us-east-1
- **Public access:** Fully blocked (all four Block Public Access settings enabled)
- **Versioning:** Enabled
- **Encryption:** SSE-S3 (AES-256 server-side encryption at rest)
- **Object Lock:** Enabled (retention settings match archive bucket)

**Bucket policy:** Allows only the S3 logging service (`logging.s3.amazonaws.com`) to write log objects, scoped to the project AWS account (`<ACCOUNT_ID>`).

```json
{
  "Version": "2012-10-17",
  "Id": "S3-Console-Auto-Gen-Policy-1777068341872",
  "Statement": [
    {
      "Sid": "S3PolicyStmt-DO-NOT-MODIFY-1777068341762",
      "Effect": "Allow",
      "Principal": {
        "Service": "logging.s3.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::baymax-access-log/*",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "<ACCOUNT_ID>"
        }
      }
    }
  ]
}
```

> **Regulatory context:** Access logging supports auditability and non-repudiation requirements. Knowing who accessed patient data and when is a key component of HIPAA and FDA cybersecurity expectations.

---

## 13. Amazon SNS

### Topic: `baymax-tremor-alerts`

- **ARN:** `arn:aws:sns:us-east-1:<ACCOUNT_ID>:baymax-tremor-alerts`
- **Type:** Standard
- **Current subscriptions:** Email (team email address)

**Alert message format (JSON):**

```json
{
  "patient_id": "patient-001",
  "timestamp": 1713700000000,
  "alert_type": "high_tremor",
  "severity": "warning",
  "message": "Tremor threshold exceeded on X, Z axis",
  "details": [
    {"axis": "x", "peak_hz": 5.5, "peak_amp_g": 0.045},
    {"axis": "z", "peak_hz": 6.1, "peak_amp_g": 0.038}
  ],
  "read": false
}
```

### Topic: `billing-alerts`

- **Type:** Standard
- **Subscription:** Email
- **Purpose:** Alerts when AWS spending exceeds $5 (CloudWatch billing alarm)

---

## 14. Amazon Cognito

### User Pool: `baymax-user-pool`

| Setting | Value |
|---|---|
| User Pool ID | `<COGNITO_USER_POOL_ID>` |
| App Client ID | `<COGNITO_APP_CLIENT_ID>` |
| App Client Type | Public (no client secret) |
| Sign-in Identifier | Email |
| Self-registration | Disabled (admin-provisioned accounts only) |
| MFA | Disabled (class project simplification) |
| Auth Flows | `ALLOW_USER_SRP_AUTH`, `ALLOW_USER_PASSWORD_AUTH` |
| Email Delivery | Cognito default (SES) |
| Account Recovery | Email only |

### Custom Attributes

| Attribute | Type | Length | Mutable | Purpose |
|---|---|---|---|---|
| `custom:role` | String | 1–20 | Yes | User role: `patient`, `clinician`, or `caretaker` |
| `custom:patient_id` | String | 0–50 | Yes | Patient's own ID (patient/caretaker), empty for clinician |
| `custom:assigned_patients` | String | 0–500 | Yes | Comma-separated patient IDs (clinician only) |

### Groups

| Group | Description |
|---|---|
| `patient` | Patient users — access own data only |
| `clinician` | Clinician users — access data for assigned patients |
| `caretaker` | Caretaker users — read-only access to one monitored patient |

### Test Users

All use password: `<REDACTED>`

| Role | Email | Name | custom:patient_id | custom:assigned_patients | Group |
|---|---|---|---|---|---|
| Patient | `patient@baymax-test.com` | John Doe | `patient-001` | — | `patient` |
| Patient | `patient2@baymax-test.com` | Maria Lopez | `patient-002` | — | `patient` |
| Clinician | `clinician@baymax-test.com` | Dr. Lebron James | — | `patient-001,patient-002` | `clinician` |
| Caretaker | `caretaker@baymax-test.com` | Jacob Doe | `patient-001` | — | `caretaker` |

### ID Token Claims

When a user authenticates via SRP or password auth, the returned ID token JWT contains:

| Claim | Type | Description |
|---|---|---|
| `sub` | String | Unique Cognito user ID (UUID) |
| `name` | String | Display name |
| `email` | String | Login email |
| `email_verified` | Boolean | Whether email is verified |
| `custom:role` | String | User role |
| `custom:patient_id` | String | Associated patient ID (patient/caretaker) |
| `custom:assigned_patients` | String | Comma-separated patient list (clinician) |
| `cognito:groups` | Array | Group memberships (e.g., `["patient"]`) |
| `cognito:username` | String | Cognito username (same as `sub` for email sign-in) |
| `aud` | String | App Client ID |
| `iss` | String | Cognito User Pool issuer URL |
| `token_use` | String | `"id"` |
| `auth_time` | Number | Unix timestamp of authentication |
| `exp` | Number | Token expiry (1 hour after auth_time) |

---

## 15. Amazon API Gateway

### API: `baymax-api`

| Setting | Value |
|---|---|
| API Name | `baymax-api` |
| API Type | REST API |
| Endpoint Type | Regional |
| Stage | `prod` |
| Base URL | `https://<API_ID>.execute-api.us-east-1.amazonaws.com/prod` |
| TLS Version | 1.3 |
| Endpoint Access Mode | Strict (SNI enforced) |

### Authorizer: `baymax-cognito-auth`

| Setting | Value |
|---|---|
| Type | Cognito |
| User Pool | `baymax-user-pool` (`<COGNITO_USER_POOL_ID>`) |
| Token Source | `Authorization` header |
| Token Validation | None (no regex on `aud`) |

### Resource Tree

```
/
├── /patients
│   └── /{id}
│       ├── /readings          GET
│       └── /alerts            GET
│           └── /{timestamp}   PUT
└── /clinician
    └── /patients              GET
```

### Methods

All methods use:
- **Integration type:** Lambda Function (proxy integration enabled)
- **Lambda function:** `baymax-api-handler`
- **Authorization:** `baymax-cognito-auth`
- **API key required:** No

| Method | Resource | Description |
|---|---|---|
| GET | `/patients/{id}/readings` | Tremor readings with optional `?from=<ms>&to=<ms>` |
| GET | `/patients/{id}/alerts` | Alert history with optional `?unread=true` |
| PUT | `/patients/{id}/alerts/{timestamp}` | Mark a specific alert as read |
| GET | `/clinician/patients` | List clinician's assigned patients with names |

### CORS

CORS is enabled on all four resource endpoints with:
- **Access-Control-Allow-Origin:** `*`
- **Access-Control-Allow-Headers:** `Content-Type,Authorization`
- **Access-Control-Allow-Methods:** `GET,PUT,OPTIONS`

OPTIONS methods are auto-created for preflight requests.

### API Response Formats

**GET `/patients/{id}/readings`:**
```json
[
  {
    "patient_id": "patient-001",
    "timestamp": 1777511600579,
    "band_hz": [4, 7],
    "x_peak_hz": 4,
    "x_peak_amp_g": 0.002228,
    "x_mean_amp_g": 0.001265,
    "y_peak_hz": 5,
    "y_peak_amp_g": 0.003088,
    "y_mean_amp_g": 0.001551,
    "z_peak_hz": 7,
    "z_peak_amp_g": 0.002418,
    "z_mean_amp_g": 0.001776
  }
]
```

**GET `/patients/{id}/alerts`:**
```json
[
  {
    "patient_id": "patient-001",
    "timestamp": 1777508053100,
    "alert_type": "high_tremor",
    "severity": "warning",
    "message": "Tremor threshold exceeded on Y, Z axis",
    "details": [
      {"axis": "y", "peak_hz": 5, "peak_amp_g": 0.040269},
      {"axis": "z", "peak_hz": 5, "peak_amp_g": 0.032005}
    ],
    "read": false
  }
]
```

**PUT `/patients/{id}/alerts/{timestamp}`:**
```json
{"message": "Alert marked as read"}
```

**GET `/clinician/patients`:**
```json
[
  {"patient_id": "patient-001", "name": "John Doe"},
  {"patient_id": "patient-002", "name": "Maria Lopez"}
]
```

---

## 16. Amazon CloudWatch

### Alarms

| Alarm Name | Metric | Threshold | SNS Topic |
|---|---|---|---|
| `spending-over-5-dollars` | EstimatedCharges (USD) | > $5 | `billing-alerts` |

### Log Groups

| Log Group | Source | Purpose |
|---|---|---|
| `/aws/lambda/baymax-process-tremor` | Ingestion Lambda | Function execution logs, errors, duration |
| `/aws/lambda/baymax-api-handler` | API Lambda | API request logs, RBAC decisions, errors |
| `/iot/baymax-errors` | IoT Core Rule error action | Logs when the IoT rule fails to invoke Lambda |

---

## 17. Data Flow and Payload Specification

### Ingestion Path: MQTT Payload (Pi → IoT Core → Lambda)

```json
{
  "patient_id": "patient-001",
  "timestamp": 1713700000000,
  "band_summary": {
    "band_hz": [4.0, 7.0],
    "x": {
      "peak_hz": 5.5,
      "peak_amp_g": 0.045,
      "mean_amp_g": 0.02
    },
    "y": {
      "peak_hz": 4.8,
      "peak_amp_g": 0.012,
      "mean_amp_g": 0.008
    },
    "z": {
      "peak_hz": 6.1,
      "peak_amp_g": 0.038,
      "mean_amp_g": 0.015
    }
  }
}
```

**Field definitions:**

| Field | Type | Unit | Description |
|---|---|---|---|
| `patient_id` | String | — | Unique patient identifier |
| `timestamp` | Number | ms (Unix epoch) | Time of the FFT batch |
| `band_summary.band_hz` | Array[2] | Hz | Frequency band analyzed [low, high] |
| `*.peak_hz` | Number | Hz | Frequency of the strongest component in the band |
| `*.peak_amp_g` | Number | G (acceleration) | Amplitude of the strongest component |
| `*.mean_amp_g` | Number | G (acceleration) | Mean amplitude across the band |

### Access Path: API Responses (Lambda → API Gateway → App)

All API responses use flat snake_case keys (no nesting), which matches the DynamoDB record format and the mobile app's `fromJson()` parsers. See Section 15 for full response examples.

### FFT Context

The FFT is performed on the Pi using `fft_analysis.py`:
- **Sample rate:** 100 Hz
- **Tremor band of interest:** 4.0–7.0 Hz (classic Parkinson's resting tremor range)
- **Input:** Raw ADXL345 accelerometer readings on X, Y, Z axes
- **Output:** The `band_summary` dict used in the MQTT payload

---

## 18. Alert Logic

The ingestion Lambda function evaluates alert conditions on every incoming message.

**Current rule:** If any axis's `peak_amp_g` exceeds the `TREMOR_THRESHOLD` (default: 0.03 G), an alert is triggered.

**What happens when an alert fires:**

1. An alert record is written to `baymax-alerts` with:
   - The patient ID and timestamp
   - Which axes exceeded the threshold and by how much
   - `read: false` for the mobile app to detect
2. An email is sent via SNS with the alert details.

**Threshold tuning:** The threshold can be adjusted via the Lambda environment variable `TREMOR_THRESHOLD` without redeploying code. The default of 0.03 G is a starting point — clinical literature suggests typical Parkinson's resting tremor amplitudes range from 0.01 to 0.1 G depending on severity, so this should be calibrated with real device data.

---

## 19. RBAC Logic

The API Lambda function enforces role-based access control on every API request.

### How it works

1. The mobile app authenticates with Cognito and receives a JWT ID token.
2. The app sends the ID token in the `Authorization` header with every API request.
3. API Gateway validates the token via the `baymax-cognito-auth` Cognito authorizer.
4. API Gateway passes the validated token claims to the Lambda via `event.requestContext.authorizer.claims`.
5. Lambda extracts three RBAC claims: `custom:role`, `custom:patient_id`, `custom:assigned_patients`.
6. The `authorize()` function checks access based on role:

### Authorization Rules

| Role | Rule | Example |
|---|---|---|
| `patient` | `custom:patient_id` must equal the requested `{id}` | John Doe (`patient-001`) can only access `/patients/patient-001/*` |
| `caretaker` | `custom:patient_id` must equal the requested `{id}` | Jacob Doe (`patient-001`) can only access `/patients/patient-001/*` |
| `clinician` | Requested `{id}` must be in the `custom:assigned_patients` list | Dr. Lebron James (`patient-001,patient-002`) can access both patients |

### Endpoint-Level Access Matrix

| Endpoint | Patient | Caretaker | Clinician |
|---|---|---|---|
| `GET /patients/{own-id}/readings` | ✅ | ✅ | ✅ (if assigned) |
| `GET /patients/{other-id}/readings` | ❌ 403 | ❌ 403 | ❌ 403 (if not assigned) |
| `GET /patients/{id}/alerts` | Same as readings | Same as readings | Same as readings |
| `PUT /patients/{id}/alerts/{ts}` | Same as readings | Same as readings | Same as readings |
| `GET /clinician/patients` | ❌ 403 | ❌ 403 | ✅ |

### Test Results (May 2026)

| # | Role | Test | Expected | Result |
|---|---|---|---|---|
| 1 | Patient | GET own readings | 200 + data | ✅ |
| 2 | Patient | GET other patient's readings | 403 | ✅ |
| 3 | Patient | GET own alerts | 200 + data | ✅ |
| 4 | Patient | GET clinician patients | 403 | ✅ |
| 5 | Clinician | GET assigned patient's readings | 200 + data | ✅ |
| 6 | Clinician | GET patient list | 200 + names | ✅ |
| 7 | Clinician | GET unassigned patient | 403 | ✅ |
| 8 | Caretaker | GET monitored patient's readings | 200 + data | ✅ |
| 9 | Caretaker | GET other patient's readings | 403 | ✅ |

---

## 20. Context for Pi-Side Developers

This section provides the information needed to write the MQTT publishing script for the Raspberry Pi.

### What you need on the Pi

1. **Certificate files** (obtained during IoT Thing creation):
   - `baymax-device-01.cert.pem` (device certificate)
   - `baymax-device-01.private.key` (private key)
   - `AmazonRootCA1.pem` (root CA — download from https://www.amazontrust.com/repository/AmazonRootCA1.pem)

2. **MQTT client library:** `awsiotsdk` (recommended) or `paho-mqtt`
   ```bash
   pip install awsiotsdk
   ```

3. **IoT Core endpoint:** Find this in AWS Console → IoT Core → Settings → Device data endpoint. It looks like `xxxxxxxxxxxxxx-ats.iot.us-east-1.amazonaws.com`.

### Connection parameters

| Parameter | Value |
|---|---|
| Endpoint | `xxxxxxxxxxxxxx-ats.iot.us-east-1.amazonaws.com` |
| Port | 8883 (MQTT over TLS) |
| Client ID | `baymax-device-01` (must match policy exactly) |
| Protocol | MQTT v3.1.1 or v5 |
| Authentication | Mutual TLS (X.509 certificates) |

### Publishing requirements

- **Topic:** `baymax/tremor-data`
- **QoS:** 1 (at least once delivery, recommended)
- **Payload format:** JSON (see Section 17 for exact schema)
- **Publish frequency:** After each FFT batch (depends on sample window size — at 100 Hz with e.g. 256 samples, that's roughly every 2.5 seconds)

### Subscribing (optional, for future use)

The device can subscribe to `baymax/commands/*` to receive configuration updates (e.g., changing the sampling rate or tremor threshold). This can be implemented via the Device Shadow or as direct MQTT messages.

### Sample MQTT publisher pseudocode

```python
from awsiotsdk import mqtt5, mqtt_connection_builder
import json
import time

# Build connection
connection = mqtt_connection_builder.mtls_from_path(
    endpoint="YOUR_ENDPOINT",
    port=8883,
    cert_filepath="baymax-device-01.cert.pem",
    pri_key_filepath="baymax-device-01.private.key",
    ca_filepath="AmazonRootCA1.pem",
    client_id="baymax-device-01",
)

connection.connect().result()

# After FFT processing, build payload and publish
payload = {
    "patient_id": "patient-001",
    "timestamp": int(time.time() * 1000),
    "band_summary": band_summary_from_fft  # output of band_summary()
}

connection.publish(
    topic="baymax/tremor-data",
    payload=json.dumps(payload),
    qos=mqtt.QoS.AT_LEAST_ONCE,
)
```

### Important notes for Pi developers

- The `patient_id` should be configurable (e.g., from a config file or environment variable), not hardcoded in production.
- The `timestamp` must be Unix epoch in **milliseconds** (multiply `time.time()` by 1000).
- The `band_summary` field should be the exact output of the `band_summary()` function from `fft_analysis.py`.
- The device is restricted to client ID `baymax-device-01` — using any other client ID will be rejected by the IoT policy.

---

## 21. Context for Mobile App Developers

### Current State — API is Live

The mobile app has a fully functional REST API. A separate integration guide has been delivered: `baymax-app-integration-guide.md`.

### Quick Reference

| Resource | Value |
|---|---|
| Cognito User Pool ID | `<COGNITO_USER_POOL_ID>` |
| Cognito App Client ID | `<COGNITO_APP_CLIENT_ID>` |
| API Base URL | `https://<API_ID>.execute-api.us-east-1.amazonaws.com/prod` |
| Region | `us-east-1` |
| Auth Header | `Authorization: <IdToken>` (no `Bearer` prefix) |

### Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/patients/{id}/readings` | Readings with optional `?from=<ms>&to=<ms>` |
| GET | `/patients/{id}/alerts` | Alerts with optional `?unread=true` |
| PUT | `/patients/{id}/alerts/{timestamp}` | Mark alert as read |
| GET | `/clinician/patients` | Clinician's assigned patient list with names |

### Data Models

Responses use flat snake_case JSON matching the DynamoDB record format. The mobile app's `TremorReading.fromJson()` and `Alert.fromJson()` parse these directly without transformation.

### User Roles

| Role | Access Pattern |
|---|---|
| Patient | Own `patient_id` data only |
| Caretaker | Monitored `patient_id` data only (read-only) |
| Clinician | Any patient in `custom:assigned_patients` + `/clinician/patients` |

### Test Accounts

All use password: `<REDACTED>`

| Role | Email | Name |
|---|---|---|
| Patient | `patient@baymax-test.com` | John Doe (patient-001) |
| Patient | `patient2@baymax-test.com` | Maria Lopez (patient-002) |
| Clinician | `clinician@baymax-test.com` | Dr. Lebron James |
| Caretaker | `caretaker@baymax-test.com` | Jacob Doe (monitors patient-001) |

### Alert Polling

Until push notifications are implemented, the app should poll `GET /patients/{id}/alerts?unread=true` every 10–30 seconds for new alerts.

---

## 22. Current Design Constraints and Assumptions

### Single device limitation

The IoT policy is scoped to a single client ID (`baymax-device-01`). To support multiple devices simultaneously, additional Things must be registered in IoT Core, each with their own certificate and policy (or a wildcard policy). The Lambda and DynamoDB design already supports multiple patients via `patient_id` — only the IoT layer needs expansion.

### Patient ID is Pi-configured, not system-assigned

The `patient_id` is set on the Pi side (in the publishing script) and sent as part of the payload. There is no server-side validation that the patient ID is legitimate. In production, IoT Core policy variables could tie a specific certificate to a specific patient ID.

### Alert threshold is global

The `TREMOR_THRESHOLD` is a single environment variable applied to all patients equally. Individual patient thresholds (e.g., based on baseline assessment) would require a lookup table or per-patient configuration — not yet implemented.

### No data retention lifecycle

All data in DynamoDB is retained indefinitely. There is no TTL configured. S3 data is retained for at least 3 years due to Object Lock. For long-running deployments, consider adding DynamoDB TTL to automatically expire old readings.

### Push notifications not implemented

Alert notifications are currently email-only via SNS. Mobile push notifications would require Firebase Cloud Messaging (FCM) integration with SNS Platform Application. Until then, the app polls for unread alerts.

### No duplicate detection

If the Pi publishes the same message twice (e.g., network retry), the Lambda will process it twice. Since DynamoDB uses `patient_id` + `timestamp` as the key, an exact duplicate will overwrite (harmless), but a retry with a slightly different timestamp would create a duplicate record.

### Governance mode, not Compliance mode

S3 Object Lock uses Governance mode for practical reasons during the class project. An admin user can override the retention if needed. Production should use Compliance mode for true immutability.

### USER_PASSWORD_AUTH enabled for testing

The Cognito App Client has `ALLOW_USER_PASSWORD_AUTH` enabled alongside `ALLOW_USER_SRP_AUTH` to support CLI-based testing. In production, `USER_PASSWORD_AUTH` should be disabled — only `USER_SRP_AUTH` should remain.

### Broad IAM policies on Lambda roles

Both Lambda execution roles use broad managed policies (`AmazonDynamoDBFullAccess`, `AmazonS3FullAccess`, etc.). In production, these should be scoped to specific resource ARNs following least-privilege principles.

### Cognito custom attributes not searchable by server-side filter

The `/clinician/patients` endpoint iterates all Cognito users client-side to find patients by `custom:patient_id` because Cognito's `Filter` parameter doesn't reliably work on custom attributes. This is acceptable for small user pools but would need a lookup table (DynamoDB) for production scale.

---

## 23. Future Work

| Item | Description | Priority |
|---|---|---|
| **Pi MQTT client script** | Integrate FFT output with MQTT publishing | High — needed for device |
| **FCM push notifications** | Real-time mobile alerts via SNS + Firebase | Medium |
| **Multi-device support** | Register additional IoT Things, wildcard or fleet policies | Medium |
| **Per-patient thresholds** | Configurable thresholds per patient | Low |
| **DynamoDB TTL** | Auto-expire old readings after a configurable period | Low |
| **Device Shadow usage** | Sync config (threshold, sample rate) between cloud and Pi | Low |
| **Disable USER_PASSWORD_AUTH** | Remove password auth flow after testing complete | Low |
| **Scope down IAM policies** | Replace broad managed policies with resource-specific inline policies | Low |
| **Patient lookup table** | DynamoDB table for patient names (replace Cognito iteration at scale) | Low |

**Completed (no longer in this list):**
- ~~Cognito User Pool~~ → Built: `baymax-user-pool`
- ~~API Gateway~~ → Built: `baymax-api`
- ~~Clinician-patient mapping~~ → Solved via Cognito custom attributes

---

## 24. Cost Considerations

The entire infrastructure operates within or near the AWS Free Tier for the scale of a class project.

| Service | Free Tier Allowance | Expected Usage |
|---|---|---|
| IoT Core | Not free-tier eligible | ~$0.01–0.10 total (pennies for low message volume) |
| Lambda (both functions) | 1M requests/month, 400K GB-seconds | Well within free tier |
| DynamoDB | 25 GB storage, 25 RCU/WCU (on-demand has free tier too) | Well within free tier |
| S3 | 5 GB storage (12 months) | Well within free tier |
| SNS | 1M publishes, 1K email notifications | Well within free tier |
| CloudWatch | 10 alarms, 5 GB log ingestion | Well within free tier |
| Cognito | 50,000 MAU (monthly active users) | Well within free tier |
| API Gateway | 1M API calls/month (12 months) | Well within free tier |

**Billing alarm:** A CloudWatch alarm (`spending-over-5-dollars`) is configured to send an email if total charges exceed $5.

> **Note:** Free tier benefits require the AWS account to be less than 12 months old for S3, DynamoDB, and API Gateway. IoT Core has no free tier but costs are negligible at project scale.

---

## 25. Version History

| Date | Version | Change |
|---|---|---|
| April 21, 2026 | v1 | Initial cloud infrastructure: IoT Core, Lambda, DynamoDB, S3, SNS |
| April 21, 2026 | v1 | Added `baymax-access-log` S3 bucket for archive access auditing |
| April 21, 2026 | v1 | Updated S3 retention period to 3 years on both buckets |
| May 1, 2026 | v2 | Added Cognito User Pool with 3 groups, 3 custom attributes, 4 test users |
| May 1, 2026 | v2 | Added API Lambda (`baymax-api-handler`) with full RBAC for 3 roles |
| May 1, 2026 | v2 | Added REST API Gateway (`baymax-api`) with TLS 1.3, Strict SNI, Cognito authorizer |
| May 1, 2026 | v2 | All 9 RBAC test cases verified across patient, clinician, and caretaker roles |
| May 1, 2026 | v2 | Added full system architecture diagram and 3 sub-architecture diagrams |
| May 1, 2026 | v2 | Added Section 14 (Cognito), Section 15 (API Gateway), Section 19 (RBAC Logic) |
| May 1, 2026 | v2 | Updated Sections 6, 7, 16, 22, 23 with new services and resolved items |
| May 1, 2026 | v2 | Delivered `baymax-app-integration-guide.md` to app developer |
