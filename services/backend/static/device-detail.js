const API_BASE = "http://localhost:8000";

const params = new URLSearchParams(window.location.search);
const deviceId = params.get("device_id");

document.getElementById("device-title").textContent = `Device: ${deviceId}`;

function addCell(row, text) {
  const cell = document.createElement("td");
  cell.textContent = text;
  row.appendChild(cell);
}

async function loadTelemetryHistory() {
  const response = await fetch(`${API_BASE}/telemetry/${encodeURIComponent(deviceId)}`);
  const readings = await response.json();

  const tbody = document.querySelector("#telemetry-table tbody");
  tbody.innerHTML = "";

  for (const reading of readings) {
    const temperatureThreshold = 80.0;
    const vibrationThreshold = 8.0;
    const isAnomaly = reading.temperature > temperatureThreshold || reading.vibration > vibrationThreshold;

    const row = document.createElement("tr");
    if (isAnomaly) row.className = "anomaly";
    addCell(row, new Date(reading.timestamp).toLocaleTimeString());
    addCell(row, reading.temperature ?? "-");
    addCell(row, reading.vibration ?? "-");
    addCell(row, reading.battery ?? "-");
    addCell(row, reading.connectivity ?? "-");
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
    addCell(row, alert.alert_type);
    addCell(row, alert.message);
    addCell(row, alert.resolved ? "Yes" : "No");
    addCell(row, new Date(alert.created_at).toLocaleTimeString());
    tbody.appendChild(row);
  }
}

async function refresh() {
  await loadTelemetryHistory();
  await loadDeviceAlerts();
}

refresh();
setInterval(refresh, 3000);