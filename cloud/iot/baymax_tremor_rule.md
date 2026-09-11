# IoT Rule: `baymax_tremor_rule`

Routes every message published by the device to the ingestion Lambda.

| Property | Value |
|---|---|
| SQL | `SELECT * FROM 'baymax/tremor-data'` |
| SQL version | `2016-03-23` |
| Action | Invoke Lambda `baymax-process-tremor` |
| Error action | CloudWatch Logs — `/iot/baymax-errors` |

The error action matters: without it, a Lambda that throws fails silently
and the message is lost with no record that it arrived.
