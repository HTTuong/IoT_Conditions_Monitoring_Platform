import json
import queue
import time
import paho.mqtt.client as mqtt


class MqttLibrary:
    """Robot Framework library to publish and listen on MQTT topics
    against the Mosquitto broker.

    One instance is shared for the whole test suite (see
    ROBOT_LIBRARY_SCOPE below), so the connection is opened once and
    reused across every test case in the suite.
    """

    ROBOT_LIBRARY_SCOPE = "SUITE"

    def __init__(self, broker_host="localhost", broker_port=1883):
        self._messages = queue.Queue()
        self._client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION2,
            client_id=f"robot-test-{int(time.time() * 1000)}",
        )
        self._client.on_message = self._on_message
        self._client.connect(broker_host, int(broker_port), keepalive=30)
        self._client.loop_start()

    def _on_message(self, client, userdata, msg):
        try:
            payload = json.loads(msg.payload.decode())
        except json.JSONDecodeError:
            payload = msg.payload.decode()
        self._messages.put((msg.topic, payload))

    def subscribe_to_topic(self, topic, qos=1):
        """Subscribes to ``topic``. Supports MQTT wildcards (+ and #)."""
        self._client.subscribe(topic, qos=int(qos))
        time.sleep(0.2)  # let the SUBACK complete before the test publishes

    def publish_message(self, topic, payload, qos=1):
        """Publishes ``payload`` (a Robot dict or a plain string) as JSON."""
        body = json.dumps(payload) if not isinstance(payload, str) else payload
        result = self._client.publish(topic, body, qos=int(qos))
        result.wait_for_publish(timeout=5)

    def wait_for_message(self, topic_filter=None, timeout=5):
        """Blocks until a message arrives, optionally matching
        ``topic_filter`` (wildcards supported). Returns the decoded payload.
        Raises a clear AssertionError on timeout instead of a bare Empty.
        """
        deadline = time.time() + float(timeout)
        while True:
            remaining = deadline - time.time()
            if remaining <= 0:
                raise AssertionError(
                    "No MQTT message received on %s within %ss"
                    % (topic_filter or "any topic", timeout)
                )
            try:
                topic, payload = self._messages.get(timeout=remaining)
            except queue.Empty:
                continue
            if topic_filter is None or mqtt.topic_matches_sub(topic_filter, topic):
                return payload
            self._messages.put((topic, payload))  # not it — leave for someone else

    def clear_received_messages(self):
        """Drops buffered messages. Call in Test Setup so leftovers from
        one test can't leak into the next."""
        while not self._messages.empty():
            self._messages.get_nowait()

    def disconnect_from_broker(self):
        self._client.loop_stop()
        self._client.disconnect()