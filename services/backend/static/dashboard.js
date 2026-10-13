const API_BASE = "http://localhost:8000";

// Cells are filled with textContent, so data is never parsed as HTML.
function addCell(row, text, className) {
  const cell = document.createElement("td");
  cell.textContent = text;
  if (className) cell.className = className;
  row.appendChild(cell);
}

async function loadDevices() {
  const response = await fetch(`${API_BASE}/devices`);
  const devices = await response.json();

  const tbody = document.querySelector("#devices-table tbody");
  tbody.innerHTML = "";

  for (const device of devices) {
    const row = document.createElement("tr");

    const idCell = document.createElement("td");
    const link = document.createElement("a");
    link.href = `device-detail.html?device_id=${encodeURIComponent(device.device_id)}`;
    link.textContent = device.device_id;
    idCell.appendChild(link);
    row.appendChild(idCell);

    addCell(row, device.name);
    addCell(row, device.status, `status-${device.status}`);
    tbody.appendChild(row);
  }
}

async function loadAlerts() {
  const response = await fetch(`${API_BASE}/alerts?resolved=false`);
  const alerts = await response.json();

  const tbody = document.querySelector("#alerts-table tbody");
  tbody.innerHTML = "";

  for (const alert of alerts) {
    const row = document.createElement("tr");
    row.className = "alert-row";
    addCell(row, alert.device_id);
    addCell(row, alert.alert_type);
    addCell(row, alert.message);
    addCell(row, new Date(alert.created_at).toLocaleTimeString());
    tbody.appendChild(row);
  }
}

async function refreshDashboard() {
  await loadDevices();
  await loadAlerts();
}

refreshDashboard();
setInterval(refreshDashboard, 3000); // refresh every 3 seconds