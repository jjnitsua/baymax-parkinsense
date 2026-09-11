import smbus2
import struct
import time
import json
import signal
import sys
from collections import deque

from fft_analysis import compute_fft, band_summary
from device_logger import audit, DEVICE_ID
from mqtt_client import MQTTClient

# --- Config ---
ADDR     = 0x53   # ADXL345 I2C address (SDO low)
SCALE    = 0.004  # G per LSB in +/-16G full-res mode

FFT_BUFFER_SIZE = 100
POLL_INTERVAL   = 0.25   # seconds - poll FIFO 4x/sec (watermark = 25 samples @ 100 Hz)

# Thresholds for anomaly / data-quality logging
FIFO_OVERFLOW_THRESHOLD = 32   # FIFO is 32 samples deep; >= this risks data loss
ACCEL_CLIP_G            = 15.5 # near ±16 G full-scale → sensor likely clipping

# --- ADXL345 init ---
def init_adxl345_fifo(bus):
    """Initialise sensor and log the configuration applied."""
    bus.write_byte_data(ADDR, 0x38, 0x00)        # FIFO_CTL: bypass (flushes FIFO)
    bus.write_byte_data(ADDR, 0x2D, 0x08)        # POWER_CTL: measure mode
    bus.write_byte_data(ADDR, 0x31, 0x0B)        # DATA_FORMAT: +/-16G full resolution
    bus.write_byte_data(ADDR, 0x2C, 0x0A)        # BW_RATE: 100 Hz ODR
    bus.write_byte_data(ADDR, 0x38, 0b01011001)  # FIFO_CTL: stream mode, 25-sample watermark

    audit.sensor("SENSOR_INIT", {
        "addr_hex":    hex(ADDR),
        "scale_g_lsb": SCALE,
        "odr_hz":      100,
        "range_g":     16,
        "fifo_mode":   "stream",
        "watermark":   25,
    })


def read_fifo(bus):
    """
    Drain the FIFO and return samples. Logs overflow warnings so
    the FDA audit trail captures any data-integrity risk.
    """
    fifo_status = bus.read_byte_data(ADDR, 0x39)
    count       = fifo_status & 0x3F

    # Log a warning if we're approaching FIFO saturation (data loss risk)
    if count >= FIFO_OVERFLOW_THRESHOLD:
        audit.sensor("FIFO_NEAR_OVERFLOW", {
            "samples_in_fifo": count,
            "threshold":       FIFO_OVERFLOW_THRESHOLD,
        }, level="WARNING")

    samples = []
    for _ in range(count):
        raw     = bus.read_i2c_block_data(ADDR, 0x32, 6)
        x, y, z = struct.unpack_from('<3h', bytes(raw))
        samples.append((x * SCALE, y * SCALE, z * SCALE))
    return samples


# --- FFT buffers ---
fft_buffer_x = deque(maxlen=FFT_BUFFER_SIZE)
fft_buffer_y = deque(maxlen=FFT_BUFFER_SIZE)
fft_buffer_z = deque(maxlen=FFT_BUFFER_SIZE)

# Track consecutive empty FIFO polls (can indicate sensor fault)
_empty_fifo_streak = 0
_EMPTY_FIFO_ALERT  = 8   # alert after 8 consecutive empty polls (2 seconds)

# --- Initialize MQTT client ---
try:
    mqtt = MQTTClient(device_id=DEVICE_ID)
except FileNotFoundError as exc:
    audit.network("MQTT_INIT_FAILED", {"error": str(exc), "reason": "cert file missing"}, level="CRITICAL")
    mqtt = None
except OSError as exc:
    audit.network("MQTT_INIT_FAILED", {"error": str(exc), "reason": "broker unreachable"}, level="CRITICAL")
    mqtt = None

# --- Poll function ---
def poll_fifo(bus):
    global _empty_fifo_streak

    try:
        samples = read_fifo(bus)
    except OSError as exc:
        # I2C bus error — log as a security/integrity event because unexpected
        # hardware failures are a cybersecurity signal under FDA guidance.
        audit.sensor("I2C_READ_ERROR", {"error": str(exc)}, level="ERROR")
        return

    # --- Track empty FIFO streaks ---
    if not samples:
        _empty_fifo_streak += 1
        if _empty_fifo_streak == _EMPTY_FIFO_ALERT:
            audit.sensor("SENSOR_NO_DATA", {
                "consecutive_empty_polls": _empty_fifo_streak,
                "poll_interval_s":         POLL_INTERVAL,
            }, level="WARNING")
        return
    else:
        if _empty_fifo_streak >= _EMPTY_FIFO_ALERT:
            audit.sensor("SENSOR_RESUMED", {
                "empty_polls_before_resume": _empty_fifo_streak,
            })
        _empty_fifo_streak = 0

    ts = time.time()

    # Log sample batch metadata (not every sample — that would flood the log)
    audit.sensor("FIFO_READ", {
        "sample_count": len(samples),
        "batch_ts":     round(ts, 4),
    })

    for i, (x, y, z) in enumerate(samples):
        sample_ts = ts - (len(samples) - i) / 100.0

        # print(f"raw | ts: {sample_ts:.4f} | x: {x:.4f}G  y: {y:.4f}G  z: {z:.4f}G")

        # --- Clipping / out-of-range detection ---
        if any(abs(v) >= ACCEL_CLIP_G for v in (x, y, z)):
            audit.data("SENSOR_CLIPPING", {
                "sample_ts": round(sample_ts, 4),
                "x_g":       round(x, 4),
                "y_g":       round(y, 4),
                "z_g":       round(z, 4),
            }, level="WARNING")

        # # --- Publish raw sample ---
        # raw_payload = json.dumps({"x": round(x, 4),
        #                           "y": round(y, 4),
        #                           "z": round(z, 4),
        #                           "ts": sample_ts})
        # if mqtt:
        #     mqtt.publish("sensors/adxl345/raw", raw_payload)
        # else:
        #     audit.network("MQTT_PUBLISH_SKIPPED", {
        #         "topic":   "sensors/adxl345/raw",
        #         "reason":  "MQTT client not initialized",
        #         "payload": json.loads(raw_payload),
        #     }, level="WARNING")

        fft_buffer_x.append(x)
        fft_buffer_y.append(y)
        fft_buffer_z.append(z)

    # run FFT once buffer is full (every 100 samples = 1 second at 100 Hz)
    if len(fft_buffer_x) == FFT_BUFFER_SIZE:
        freqs, x_amp, y_amp, z_amp = compute_fft(
            list(fft_buffer_x),
            list(fft_buffer_y),
            list(fft_buffer_z),
        )
        summary = band_summary(freqs, x_amp, y_amp, z_amp, low_hz=4.0, high_hz=7.0)

        # print(f"fft | X peak: {summary['x']['peak_hz']} Hz  amp: {summary['x']['peak_amp_g']} G")
        # print(f"fft | Y peak: {summary['y']['peak_hz']} Hz  amp: {summary['y']['peak_amp_g']} G")
        # print(f"fft | Z peak: {summary['z']['peak_hz']} Hz  amp: {summary['z']['peak_amp_g']} G")

        # # Log FFT result to audit trail
        # audit.data("FFT_RESULT", {
        #     "band_hz":   summary["band_hz"],
        #     "x_peak_hz": summary["x"]["peak_hz"],
        #     "x_peak_g":  summary["x"]["peak_amp_g"],
        #     "y_peak_hz": summary["y"]["peak_hz"],
        #     "y_peak_g":  summary["y"]["peak_amp_g"],
        #     "z_peak_hz": summary["z"]["peak_hz"],
        #     "z_peak_g":  summary["z"]["peak_amp_g"],
        #     "batch_ts":  round(ts, 4),
        # })

        # --- Publish FFT result ---
        fft_payload = json.dumps({
            "patient_id": "patient-001",
            "timestamp": int(ts * 1000),
            "band_summary": summary})
        print(f"Publishing FFT summary: {fft_payload}")

        topic = "baymax/tremor-data"
        if mqtt:
            mqtt.publish(topic, fft_payload)
        else:
            audit.network("MQTT_PUBLISH_SKIPPED", {
                "topic":   topic,
                "reason":  "MQTT client not initialized",
                "payload": json.loads(fft_payload),
            }, level="WARNING")


# --- Watchdog counter ---
_poll_count = 0
_WATCHDOG_INTERVAL = 60   # emit a heartbeat log every 60 polls (~15 seconds)

# --- Graceful shutdown ---
# systemd sends SIGTERM when the service is stopped or the device is shutting
# down. We catch it here so we can write a clean DEVICE_SHUTDOWN log entry
# before exiting, rather than being killed mid-poll with no audit record.
_running = True

def _handle_sigterm(signum, frame):
    global _running
    audit.system("SHUTDOWN_SIGNAL", {"signal": "SIGTERM"})
    _running = False

signal.signal(signal.SIGTERM, _handle_sigterm)

# --- Main ---
bus = smbus2.SMBus(1)

audit.system("DEVICE_BOOT", {
    "poll_interval_s": POLL_INTERVAL,
    "fft_buffer_size": FFT_BUFFER_SIZE,
})

init_adxl345_fifo(bus)

print(f"Acquisition running - polling FIFO every {POLL_INTERVAL*1000:.0f} ms (Ctrl+C to stop)")

try:
    next_tick = time.monotonic()
    while _running:
        next_tick += POLL_INTERVAL
        poll_fifo(bus)

        # Periodic heartbeat so the FDA audit trail proves continuous operation
        _poll_count += 1
        if _poll_count % _WATCHDOG_INTERVAL == 0:
            audit.watchdog({"poll_count": _poll_count})

        sleep_for = next_tick - time.monotonic()
        if sleep_for > 0:
            time.sleep(sleep_for)
        elif sleep_for < -0.05:
            # Timing slip — log if we're falling behind the poll schedule
            audit.sensor("POLL_TIMING_SLIP", {
                "slip_ms": round(-sleep_for * 1000, 1),
            }, level="WARNING")

    # Clean exit after SIGTERM — _running was set False by _handle_sigterm
    audit.system("DEVICE_SHUTDOWN", {
        "reason":      "SIGTERM",
        "total_polls": _poll_count,
    })

except KeyboardInterrupt:
    # Ctrl+C during development; systemd will use SIGTERM in production
    audit.system("DEVICE_SHUTDOWN", {
        "reason":      "KeyboardInterrupt",
        "total_polls": _poll_count,
    })

except Exception as exc:
    audit.system("DEVICE_CRASH", {"error": str(exc)}, level="CRITICAL")
    raise

finally:
    if mqtt:
        mqtt.shutdown()
    bus.close()
    print("Cleaned up.")