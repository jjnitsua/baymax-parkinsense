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
