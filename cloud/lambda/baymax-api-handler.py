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
