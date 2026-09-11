"""
mqtt_client.py

MQTT client class for AWS IoT Core using the official AWS IoT Device SDK v2.
Instantiate in acquisition_no_int.py so init errors can be caught and logged.

Usage:
    from mqtt_client import MQTTClient
    mqtt = MQTTClient(device_id)
    mqtt.publish("sensors/adxl345/raw", payload)
    mqtt.shutdown()
"""

import os
from awscrt import mqtt
from awsiot import mqtt_connection_builder
from device_logger import audit
import json
from pathlib import Path


_CERT_DIR =  Path(os.environ.get("BAYMAX_HOME", "/opt/tremor_detector")) / "certs"
# _CERT_DIR = Path(__file__).parent / "certs" 

# --- Config ---
MQTT_BROKER      = "<YOUR-IOT-ENDPOINT>-ats.iot.<REGION>.amazonaws.com"
MQTT_PORT        = 8883
MQTT_CA          = str(_CERT_DIR / "AmazonRootCA1.pem")
MQTT_CERT        = str(_CERT_DIR / "device-certificate.pem.crt")
MQTT_KEY         = str(_CERT_DIR / "device-private.pem.key")
AUTHORIZED_BROKER = MQTT_BROKER


class MQTTClient:

    def __init__(self, device_id: str):
        if MQTT_BROKER != AUTHORIZED_BROKER:
            raise ValueError(f"Unauthorized broker: {MQTT_BROKER}")

        self._connection = mqtt_connection_builder.mtls_from_path(
            endpoint=MQTT_BROKER,
            port=MQTT_PORT,
            cert_filepath=MQTT_CERT,
            pri_key_filepath=MQTT_KEY,
            ca_filepath=MQTT_CA,
            client_id="baymax-device-01",
            clean_session=False,        # resume session after reconnect
            keep_alive_secs=60,
            on_connection_interrupted=self._on_interrupted,
            on_connection_resumed=self._on_resumed,
        )

        # connect() returns a Future — .result() blocks until connected or raises
        connect_future = self._connection.connect()
        connect_future.result()         # raises on failure — caller catches and logs
        audit.network("MQTT_CONNECTED", {"broker": MQTT_BROKER})

    def publish(self, topic: str, payload: str, qos: int = 1) -> None:
        qos_level = mqtt.QoS.AT_LEAST_ONCE if qos == 1 else mqtt.QoS.AT_MOST_ONCE
        publish_future, _ = self._connection.publish(
            topic=topic,
            payload=payload,
            qos=qos_level,
        )
        # bind topic and payload into the callback via default args
        publish_future.add_done_callback(
            lambda future: self._on_publish_complete(future, topic, payload)
        )

    def shutdown(self):
        disconnect_future = self._connection.disconnect()
        disconnect_future.result()
        audit.network("MQTT_DISCONNECTED", {"rc": 0}, level="INFO")

    def _on_interrupted(self, connection, error, **kwargs):
        audit.network("MQTT_INTERRUPTED", {"error": str(error)}, level="WARNING")

    def _on_resumed(self, connection, return_code, session_present, **kwargs):
        audit.network("MQTT_RESUMED", {
            "return_code":     str(return_code),
            "session_present": session_present,
        })

    def _on_publish_complete(self, future, topic: str, payload: str):
        from device_logger import audit
        try:
            future.result()
        except Exception as exc:
            audit.network("MQTT_PUBLISH_FAILED", {
                "topic":   topic,
                "error":   str(exc),
                "payload": json.loads(payload),  # parse back to dict so it's readable in the log
            }, level="ERROR")