# Device certificates

Not included in this repository.

The device authenticates to AWS IoT Core with mutual TLS. Provision a
Thing in IoT Core and place three files here:

- `AmazonRootCA1.pem` — Amazon root CA
- `device-certificate.pem.crt` — device certificate
- `device-private.pem.key` — device private key

Filenames are configured at the top of `../mqtt_client.py`.
