import paho.mqtt.client as mqtt
import json
import time
import requests
from collections import deque

BROKER_HOST = "localhost"
BROKER_PORT = 1883
SUBSCRIBE_TOPIC = "factory/#"
BACKEND_URL = "http://localhost:8000"

# Outcome of one forwarding attempt.
OK = "ok"        # backend stored the reading (201)
RETRY = "retry"  # transient failure: keep the reading and try again later
DROP = "drop"    # permanent failure (4xx): retrying can never succeed

# Each item: (reading, mqtt_message_id, mqtt_qos). The MQTT ack is sent only after the
# reading is resolved, so a crash before that makes the broker redeliver it.
buffer = deque()


def forward_to_backend(reading: dict) -> str:
    try:
        response = requests.post(f"{BACKEND_URL}/telemetry", json=reading, timeout=3)
    except requests.exceptions.RequestException as exc:
        # Covers ConnectionError AND timeouts (a hung backend). All are transient.
        print(f"Backend unreachable or not answering ({type(exc).__name__}), will buffer")
        return RETRY

    if response.status_code == 201:
        print(f"Forwarded: {reading['device_id']}")
        return OK

    print(f"Backend rejected ({response.status_code}): {response.text}")
    # 4xx means the reading itself is invalid, so retrying forever would block the queue.
    # 408 (timeout) and 429 (rate limit) are the exceptions: they are transient.
    if 400 <= response.status_code < 500 and response.status_code not in (408, 429):
        print("Permanent error, dropping reading")
        return DROP
    return RETRY


def on_connect(client, userdata, flags, reason_code, properties):
    print(f"Connected to broker, reason code: {reason_code}")
    client.subscribe(SUBSCRIBE_TOPIC, qos=1)


def on_message(client, userdata, msg):
    # Nothing may escape this callback: an uncaught exception ends paho's network thread
    # and the gateway silently stops consuming.
    try:
        try:
            reading = json.loads(msg.payload.decode())
        except json.JSONDecodeError:
            print(f"Malformed JSON on {msg.topic}, dropping message")
            client.ack(msg.mid, msg.qos)
            return

        if not isinstance(reading, dict):
            print(f"Payload on {msg.topic} is not a JSON object, dropping message")
            client.ack(msg.mid, msg.qos)
            return

        if buffer:
            # Keep FIFO: a new reading must never overtake readings that are still queued.
            result = RETRY
        else:
            result = forward_to_backend(reading)

        if result == RETRY:
            buffer.append((reading, msg.mid, msg.qos))
            print(
                f"Buffered. Queue size: {len(buffer)} "
                f"(device={reading.get('device_id')} temperature={reading.get('temperature')})"
            )
        else:
            client.ack(msg.mid, msg.qos)
    except Exception as exc:
        print(f"Unexpected error handling {msg.topic}: {exc!r}, dropping message")
        client.ack(msg.mid, msg.qos)


def retry_buffered_messages():
    while buffer:
        reading, mid, qos = buffer[0]
        
        if buffer:
            # Keep FIFO: a new reading must never overtake readings that are still queued.
            result = RETRY
        else:
            result = forward_to_backend(reading)
        
        if result == RETRY:
            break
        buffer.popleft()
        client.ack(mid, qos)
        if result == OK:
            print(f"Retry succeeded. Queue size: {len(buffer)}")
        else:
            print(f"Retry dropped a rejected reading. Queue size: {len(buffer)}")


client = mqtt.Client(
    mqtt.CallbackAPIVersion.VERSION2,
    client_id="gateway-1",
    clean_session=False,
    manual_ack=True,
)
client.on_connect = on_connect
client.on_message = on_message
client.connect(BROKER_HOST, BROKER_PORT, keepalive=60)
client.loop_start()

try:
    while True:
        try:
            retry_buffered_messages()
        except Exception as exc:
            print(f"Retry loop error: {exc!r}")
        time.sleep(5)
except KeyboardInterrupt:
    print("\nStopping gateway...")
    client.loop_stop()
    client.disconnect()