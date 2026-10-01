import random
import uuid


class DeviceSimulator:
    """Generates deterministic, controllable test data — the opposite of
    services/simulator, which generates random continuous data for the
    live demo dashboard."""

    def generate_device_id(self, prefix="sensor"):
        return f"{prefix}-{uuid.uuid4().hex[:8]}"

    def generate_normal_reading(self, temperature=None, vibration=None,
                                  battery=None, connectivity=None):
        return {
            "temperature": temperature if temperature is not None else round(random.uniform(40.0, 70.0), 1),
            "vibration": vibration if vibration is not None else round(random.uniform(1.0, 5.0), 2),
            "battery": battery if battery is not None else round(random.uniform(60.0, 100.0), 1),
            "connectivity": connectivity or random.choice(["good", "weak"]),
        }

    def generate_anomaly_reading(self, temperature_threshold=80.0, vibration_threshold=8.0,
                                   anomaly_type="temperature"):
        """Crosses exactly ONE threshold, so a test for 'temperature
        anomaly' doesn't accidentally also trip the vibration threshold."""
        reading = self.generate_normal_reading()
        if anomaly_type == "temperature":
            reading["temperature"] = round(
                random.uniform(float(temperature_threshold) + 1, float(temperature_threshold) + 30), 1)
        elif anomaly_type == "vibration":
            reading["vibration"] = round(
                random.uniform(float(vibration_threshold) + 0.5, float(vibration_threshold) + 5), 2)
        else:
            raise ValueError(f"Unknown anomaly_type: {anomaly_type}")
        return reading

    def generate_reading_sequence(self, count, anomaly_at_index=None, **anomaly_kwargs):
        """Builds N readings with one intentional anomaly at a given
        index — e.g. for T32 'value returns to normal after a spike'."""
        sequence = []
        for i in range(int(count)):
            if anomaly_at_index is not None and i == int(anomaly_at_index):
                sequence.append(self.generate_anomaly_reading(**anomaly_kwargs))
            else:
                sequence.append(self.generate_normal_reading())
        return sequence