# generate keypair
openssl genrsa -out private_key.pem 2048
openssl rsa -in private_key.pem -pubout -out public_key.pem

# copy public key to Pi, keep private key off the device
# scp public_key.pem <user>@<device-host>:/path/to/hardware/