# Design controls — user needs, design inputs, and verification

ParkinSense design control documentation for JHU EN.601.644, structured per
FDA 21 CFR 820.30 and ISO 13485 design control requirements. Every design
input traces to a user need; every verification activity traces to a design
input.

## User needs (18)

| ID | Need | User | Rationale | Priority | Assets | Validation method |
|---|---|---|---|---|---|---|
| UN1 | Patients need the wearable device to accurately and reliably detect and quantify tremor episodes in real time to support continuous Parkinson's symptom monitoring. | Patient | Continuous tremor monitoring during daily activity | Critical | A1 | Clinical Validation |
| UN2 | Patients need the wearable device to be lightweight and unobtrusive so it can be worn comfortably during extended daily use. | Patient | Long-term wearability and patient compliance | Critical | A1 | Usability Validation |
| UN3 | Patients need the device to operate continuously to support uninterrupted monitoring. | Patient | Uninterrupted daily monitoring | High | A1 | System Validation |
| UN4 | Patients need to view their data to be aware of their own disease progression. | Patient | Patient self-awareness to disease progression | High | A3 | Usability Validation |
| UN5 | Patients need their personal health data to be protected from unauthorized access to preserve privacy and comply with applicable regulations. | Patient | Patient data privacy and regulatory compliance | Critical | A1, A4, A6, A7 | Security Validation |
| UN6 | Clinicians need access to real-time and historical tremor data to assess disease progression and conduct retrospective analysis. | Clinician | Disease progression monitoring and treatment optimization | Critical | A1, A3, A6, A7 | Clinical Validation |
| UN7 | Clinicians need tremor severity scores and movement metrics to be displayed clearly and accurately to support clinical interpretation. | Clinician | Clinical interpretation of tremor data | Critical | A3, A5 | Usability Validation |
| UN8 | Clinicians need to associate tremor data with the correct patient to support accurate patient identification and record management. | Clinician | Patient identification and record integrity | Critical | A1, A3, A4, A6, A7 | Usability Validation |
| UN9 | Clinicians need to generate patient tremor reports to support clinical documentation and care coordination. | Clinician | Clinical documentation and reporting | High | A3 | Usability Validation |
| UN10 | Clinicians need accelerometer data to be reliably transmitted from the wearable device to the cloud without data loss to support remote patient monitoring. | Clinician | Remote monitoring of ambulatory Parkinson's patients | Critical | A1, A4 | Data Integrity Validation |
| UN11 | Clinicians need the system to reliably classify tremor events using validated signal processing algorithms to minimize false positives and negatives. | Clinician | Accurate tremor classification for clinical decision-making | Critical | A5 | Clinical Validation |
| UN12 | Clinicians need to operate the tremor monitoring system without specialized technical training to support routine patient monitoring workflows. | Clinician | Routine patient monitoring workflows | Critical | A1, A3 | Usability Validation |
| UN13 | Caregivers need to receive timely notifications when a patient experiences a significant tremor episode so they can provide assistance. | Caregiver | Caregiver awareness and timely patient assistance | High | A3, A8 | System Validation |
| UN14 | Caregivers need to view a summary of the patient's recent tremor activity to monitor daily symptom burden. | Caregiver | Daily symptom burden monitoring by non-clinical users | High | A3, A5 | Usability Validation |
| UN15 | Caregivers need the mobile or web application to be simple and easy to navigate without medical or technical expertise. | Caregiver | Accessible interface for non-clinical users | High | A3 | Usability Validation |
| UN16 | IT administrators need the system to maintain comprehensive audit logs of all access and data modification events to support compliance monitoring. | IT Administrator | Regulatory compliance and audit traceability | Critical | A7 | Security Validation |
| UN17 | IT administrators need the ability to remotely update device firmware and software to address security vulnerabilities and maintain compliance. | IT Administrator | Secure remote software update management | High | A1, A3, A5 | Installation Validation |
| UN18 | IT administrators need the system to integrate with existing clinical or hospital infrastructure without requiring significant custom configuration. | IT Administrator | Seamless clinical environment integration | Medium | A1, A6, A7 | Interoperability Validation |

## Design inputs (30)

| ID | Requirement | Allocation | Category | Traces to | Verification method |
|---|---|---|---|---|---|
| DI1 | The system shall display real-time symptom metrics to clinicians with a refresh rate of no less than 1 frame per second. | Software | Functional | UN1, UN4, UN6, UN14 | Test |
| DI2 | The system shall acquire raw accelerometer signals with a sampling rate of at least 20 Hz | Hardware | Functional | UN1, UN6 | Test |
| DI3 | The system shall acquire raw accelerometer signals with an resolution of at least 2.87 cm/second2 per increment. | Hardware | Functional | UN1, UN6 | Test |
| DI4 | The longest dimension of the wearable component (excluding fastening) shall not exceed 20 cm | Hardware | Usability | UN2 | Test |
| DI5 | The weight of the wearable component shall be less than 60 g | Hardware | Usability | UN2 | Test |
| DI6 | The battery of the wearable component shall last more than 24 hours under normal operating conditions without recharging. | Hardware | Usability | UN3 | Test |
| DI7 | The system shall associate all acquired accelerometer data with a unique patient identifier prior to storage or transmission. | Software | Functional | UN8 | Inspection |
| DI8 | The system shall allow retrieval and display historical symptom recordings for a specified patient. | Software | Functional | UN6, UN7, UN14 | Demonstration |
| DI9 | The system shall enable clinicians to generate and export symptom reports in PDF format. | Software | Functional | UN9, UN11 | Demonstration |
| DI10 | The system shall support printing of symptom reports via a connected printer. | Software | Functional | UN9, UN11 | Demonstration |
| DI11 | End-to-end latency from signal acquisition to symptom metric display shall not exceed 500 ms under normal operating conditions. | System | Performance | UN1 | Test |
| DI12 | The system shall transmit patient data between assets with a packet loss rate of no greater than 3% under normal home wireless conditions. | System | Performance | UN10 | Test |
| DI13 | The system shall generate an audible and visual alert for the caregiver within 10 seconds of detecting a clinically significant "off" period or device fault. | System | Safety | UN11, UN13 | Test |
| DI14 | The system shall maintain continuous symptom monitoring and alerting functions during transient wireless disconnection of up to 30 seconds. | System | Safety | UN3 | Test |
| DI15 | The system shall provide a status indicator showing connectivity state, battery level, and active alarms visible from the main clinician view. | Software | Interface | UN3 | Inspection |
| DI16 | The system shall expose a FHIR R4-compliant API for exchange of symptom observations with connected EHR systems. | Software | Interface | UN18 | Test |
| DI17 | The system shall allow a trained clinician or caregiver to register a new patient and begin symptom monitoring in no more than 3 user interactions. | Software | Usability | UN12, UN15 | Inspection |
| DI18 | The system shall maintain an audit log of all access to patient records, including user ID, timestamp, and action performed, retained for a minimum of 3 years. | Software | Regulatory | UN16 | Inspection |
| DI19 | The system shall enforce role-based access control (RBAC) such that clinicians, IT administrators, and service accounts are granted only the minimum permissions required for their function. | Software | Cybersecurity | UN5 | Test |
| DI20 | The system shall enforce multi-factor authentication (MFA) for all IT administrator accounts at both the login endpoint of the application’s administrative web dashboard and for SSH remote maintenance access to the embedded devices prior to granting access to any system configuration or maintenance functions. | Software | Cybersecurity | UN5 | Test |
| DI21 | All patient data transmitted between the Raspberry Pi, mobile app, and AWS backend systems shall be encrypted using TLS 1.2 or higher with cipher suites that provide authenticated encryption and forward secrecy (e.g., AES-GCM or ChaCha20-Poly1305 with ECDHE). | Software | Cybersecurity | UN5 | Test |
| DI22 | All patient data stored on the system shall be encrypted at rest using AES-256 or an equivalent algorithm in a secure mode of operation (e.g., AES-GCM or AES-XTS). Insecure modes of operation such as ECB shall not be used. | Software | Cybersecurity | UN5 | Test |
| DI23 | The holter monitor shall restrict all network communications except for outbound MQTT over TLS on port 8883 for outbound data transmission and SSH on port 22 for remote maintenance. The cloud system shall restrict all network communications except for MQTT over TLS on port 8883 to receive telemetry data and HTTPS on port 443 for data transfer with authorized mobile applications. | System | Cybersecurity | UN1, UN5, UN17 | Test |
| DI24 | The holter monitor shall transmit MQTT telemetry data only to the authorized AWS IoT Core endpoints. | System | Cybersecurity | UN1, UN5 | Test |
| DI25 | The holter moniter shall allow SSH remote maintenance connections only through an authenticated TailScale VPN tunnel. | System | Cybersecurity | UN5, UN17 | Test |
| DI26 | The system shall provide a mechanism to roll back a failed software or firmware update to the last known good version. | Software | Cybersecurity | UN1, UN5, UN17 | Test |
| DI27 | The system shall log all authentication events, access control decisions, and security-relevant configuration changes to a tamper-evident audit log. | Software | Cybersecurity | UN16 | Test |
| DI28 | The mobile and desktop app shall implement session timeout, locking out inactive authenticated sessions after no more than 15 minutes with no user input. | Software | Cybersecurity | UN5 | Test |
| DI29 | The system shall reject all login attempts for 15 minuts after 3 failed login attempts to prevent brute forcing the credentials | Software | Cybersecurity | UN5 | Test |
| DI30 | The system shall require all passwords to be a combination of letters, numbers, and symbols that is 10-15 characters long. | Software | Cybersecurity | UN5 | Test |

## Verification activities (15)

| ID | Design inputs | Activity | Method | Pass criteria | Status |
|---|---|---|---|---|---|
| V1 | DI18 | Inspect audit log contents and retention policy configuration. | Inspection | Log captures user ID, timestamp, and action; retention ≥3 years confirmed | Pass |
| V2 | DI8 | Using the mobile app, retrieve and display historical symptom recordings for a pre-loaded test patient with known data across multiple sessions. | Demonstration | Historical recordings are retrieved and displayed for the specified patient; displayed values match the known stored records with no missing sessions. | Pass |
| V3 | DI9 | Using the mobile app, generate and export a symptom report in PDF format for a specified patient and date range. | Demonstration | A valid, readable PDF file is generated and exported containing the correct patient name, date range, and symptom data; PDF opens without error in a standard viewer. | Pass |
| V5 | DI15 | Inspect the main clinician view of the mobile app and confirm that connectivity state, battery level, and active alarm indicators are present and visible without scrolling or navigating to another screen. | Inspection | All three indicators (connectivity state, battery level, active alarms) are visible on the main clinician view without any additional navigation; each indicator updates to reflect a simulated state change within the display refresh period. | Pending |
| V6 | DI23 | Perform a network port scan and service enumeration on the holter monitor and cloud system to identify all open ports and running services; confirm that only the ports and services specified in the allowlist are accessible. | Test | Only documented ports allowed in DI23 are open; no unexpected services running | Pass |
| V7 | DI24 | Attempt to connect holter to a test MQTT broker. | Test | The holter monitor rejects or cannot establish connection to non-authorized endpoints in all test cases | Pass |
| V8 | DI25 | Attempt SSH connection from a device not connected to TailScale. | Test | The connection fails and no SSH access granted in all test cases | Pass |
| V9 | DI26 | Simulate failed update; verify rollback to last known good version without data loss. | Test | System restores to prior version after simulated update failure; patient data and configuration intact | Pass |
| V10 | DI27 | Review audit log contents after performing authentication, access control, and configuration change events. | Test | All specified event types present in log with correct fields; log file integrity mechanism verified | Pass |
| VER-17 | DI17 | Ask a trained clinician or caregiver to register a new patient and begin symptom monitoring from the mobile app home screen; an observer counts every discrete user interaction (tap or confirmation). | Inspection | Task is completed in ≤3 user interactions from the home screen to active monitoring for the new patient. | Pending |
| VER-21 | DI21 | Capture network traffic from the mobile app to the backend during a representative monitoring session using a packet analyser; inspect TLS version and negotiated cipher suite. | Test | All captured patient-data traffic from the mobile app uses TLS 1.2 or higher; negotiated cipher suites provide authenticated encryption and forward secrecy (e.g., ECDHE-AES-GCM or ECDHE-ChaCha20-Poly1305); no plaintext patient data is observed in any captured packet. | Pending |
| VER-22 | DI22 | Inspect local storage on the mobile device (e.g., app sandbox, SQLite database, cached files) and review the mobile app's encryption implementation in source code or configuration. | Test | All patient data stored locally by the mobile app is encrypted with AES-256 or equivalent in a secure mode (GCM or XTS); ECB mode is absent; encryption is confirmed via both source/config review and direct storage inspection. | Pending |
| VER-28 | DI28 | Authenticate on the mobile app, leave the session idle for 15 minutes, then attempt to perform an authenticated action without re-authenticating. | Test | The mobile app automatically locks the session after ≤15 minutes of inactivity; any subsequent authenticated action is blocked until the user re-authenticates successfully. | Pending |
| VER-29 | DI29 | Submit 3 consecutive failed login attempts with incorrect credentials on the mobile app login screen; immediately attempt a 4th login; wait for the lockout period to expire and attempt again with correct credentials. | Test | Login is blocked after 3 failed attempts; the 4th attempt is rejected within the 15-minute lockout window; a successful login with correct credentials is possible only after the full 15-minute lockout period has elapsed. | Pending |
| VER-30 | DI30 | On the mobile app, attempt to set passwords that violate the policy (< 10 chars, > 15 chars, letters only, numbers only, no symbols); then submit a compliant password (10–15 chars with letters, numbers, and at least one symbol). | Test | All non-compliant passwords are rejected with an informative error message; compliant passwords (10–15 characters containing letters, numbers, and at least one symbol) are accepted. | Pending |
