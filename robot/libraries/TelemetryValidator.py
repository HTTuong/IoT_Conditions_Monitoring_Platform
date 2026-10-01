class TelemetryValidator:
    """Validation logic that's too fiddly for clean Robot assertions.
    Keeps 'what counts as anomalous' in one place, so tests and the app
    can't silently drift apart on the definition."""

    REQUIRED_FIELDS = {"device_id", "temperature", "vibration", "battery", "connectivity", "timestamp"}

    def validate_telemetry_schema(self, payload):
        missing = self.REQUIRED_FIELDS - set(payload.keys())
        if missing:
            raise AssertionError(f"Telemetry payload missing fields: {sorted(missing)}")
        if not isinstance(payload["temperature"], (int, float)):
            raise AssertionError(f"temperature should be numeric, got {type(payload['temperature'])}")
        if not isinstance(payload["vibration"], (int, float)):
            raise AssertionError(f"vibration should be numeric, got {type(payload['vibration'])}")
        return True

    def is_anomalous(self, temperature, vibration, temperature_threshold=80.0, vibration_threshold=8.0):
        return float(temperature) > float(temperature_threshold) or float(vibration) > float(vibration_threshold)

    def alert_matches_telemetry(self, alert, telemetry, temperature_threshold=80.0, vibration_threshold=8.0):
        """Confirms the alert's type is actually consistent with what
        triggered it — catches e.g. a vibration spike wrongly raising a
        temperature alert."""
        alert_type = alert.get("alert_type")
        if alert_type == "high_temperature":
            return float(telemetry["temperature"]) > float(temperature_threshold)
        if alert_type == "high_vibration":
            return float(telemetry["vibration"]) > float(vibration_threshold)
        raise ValueError(f"Unknown alert_type: {alert_type}")