const API_BASE = "http://localhost:8000";

const params = new URLSearchParams(window.location.search);
const deviceId = params.get("device_id");

document.getElementById("device-title").textContent = `Device: ${deviceId}`;

async function loadTelemetryHistory() {
  const response = await fetch(`${API_BASE}/telemetry/${deviceId}`);
  const readings = await response.json();

  const tbody = document.querySelector("#telemetry-table tbody");
  tbody.innerHTML = "";

  for (const reading of readings) {
    const temperatureThreshold = 80.0;
    const vibrationThreshold = 8.0;
    const isAnomaly = reading.temperature > temperatureThreshold || reading.vibration > vibrationThreshold;

    const row = document.createElement("tr");
    if (isAnomaly) row.className = "anomaly";
    row.innerHTML = `
      <td>${new Date(reading.timestamp).toLocaleTimeString()}</td>
      <td>${reading.temperature ?? "-"}</td>
      <td>${reading.vibration ?? "-"}</td>
      <td>${reading.battery ?? "-"}</td>
      <td>${reading.connectivity ?? "-"}</td>
    `;
    tbody.appendChild(row);
  }
}

async function loadDeviceAlerts() {
  const response = await fetch(`${API_BASE}/alerts`);
  const allAlerts = await response.json();
  const deviceAlerts = allAlerts.filter(a => a.device_id === deviceId);

  const tbody = document.querySelector("#alerts-table tbody");
  tbody.innerHTML = "";

  for (const alert of deviceAlerts) {
    const row = document.createElement("tr");
    row.innerHTML = `
      <td>${alert.alert_type}</td>
      <td>${alert.message}</td>
      <td>${alert.resolved ? "Yes" : "No"}</td>
      <td>${new Date(alert.created_at).toLocaleTimeString()}</td>
    `;
    tbody.appendChild(row);
  }
}

async function refresh() {
  await loadTelemetryHistory();
  await loadDeviceAlerts();
}

refresh();
setInterval(refresh, 3000);