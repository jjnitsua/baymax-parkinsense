# archive all files
tar czf release.tar.gz acquisition_no_int_w_log.py mqtt_client.py device_logger.py fft_analysis.py

# sign the archive — one signature for everything
openssl dgst -sha256 -sign private_key.pem -out release.tar.gz.sig release.tar.gz

# copy archive + signature to Pi
scp release.tar.gz release.tar.gz.sig <user>@<device-host>:/path/to/hardware/