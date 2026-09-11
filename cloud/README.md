# Cloud — AWS backend

Serverless ingestion and access backend for the ParkinSense tremor
monitor. Built and operated in `us-east-1`. Account identifiers and
endpoint IDs are replaced with placeholders throughout.

## Contents

| Path | Purpose |
|---|---|
| `lambda/baymax-process-tremor.py` | Ingestion — validates payloads, writes to DynamoDB, archives to S3, raises alerts |
| `lambda/baymax-api-handler.py` | API — Cognito-authenticated, RBAC-enforced read access |
| `iot/baymax-device-policy.json` | Least-privilege IoT policy scoped to a single client ID and topic |
| `iot/baymax_tremor_rule.md` | Message routing rule |

Full architecture, schemas, and design rationale: [`../docs/architecture.md`](../docs/architecture.md).

## Data path

```
Pi → MQTT/mTLS → IoT Core → Rule → Lambda → DynamoDB + S3 (+ SNS on alert)
App → Cognito → API Gateway (JWT authorizer) → Lambda → DynamoDB
```

## Security design

**Device authentication** is mutual TLS with a per-device certificate.
The IoT policy permits `Connect` only with client ID `baymax-device-01`,
`Publish` only to `baymax/tremor-data`, and `Subscribe` only to
`baymax/commands/*` — a compromised device cannot publish as another
device or read other devices' data.

**Access control is enforced server-side.** The API Lambda reads the
Cognito group and custom attributes from the validated JWT, never from
request parameters. Three roles: patients see their own data, clinicians
see an explicit assigned-patient list, caretakers see one monitored
patient. A client that tampers with a `patient_id` parameter gets denied,
because the authorization decision never consults it.

**Archived data is immutable.** The S3 archive bucket uses Object Lock in
Governance mode with three-year retention and server-side encryption.
Access logging goes to a separate bucket so log deletion is not in reach
of anyone who compromises the primary.

**Transport** is TLS 1.3 on API Gateway with a Cognito authorizer; the
mobile app pins these domains via Android network security config and iOS
ATS rules.

## Deployment note

This infrastructure was built through the AWS console rather than
Terraform or CloudFormation. The documentation in `docs/architecture.md`
records every resource and setting, which is what made it reproducible —
but IaC would be the right choice for anything beyond a course project.
