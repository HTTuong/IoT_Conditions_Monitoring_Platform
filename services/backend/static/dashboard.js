const API_BASE = "http://localhost:8000";

async function loadDevices() {
  const response = await fetch(`${API_BASE}/devices`);
  const devices = await response.json();

  const tbody = document.querySelector("#devices-table tbody");
  tbody.innerHTML = "";

  for (const device of devices) {
    const row = document.createElement("tr");
    row.innerHTML = `
      <td><a href="device-detail.html?device_id=${device.device_id}">${device.device_id}</a></td>
      <td>${device.name}</td>
      <td class="status-${device.status}">${device.status}</td>
    `;
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
    row.innerHTML = `
      <td>${alert.device_id}</td>
      <td>${alert.alert_type}</td>
      <td>${alert.message}</td>
      <td>${new Date(alert.created_at).toLocaleTimeString()}</td>
    `;
    tbody.appendChild(row);
  }
}

async function refreshDashboard() {
  await loadDevices();
  await loadAlerts();
}

refreshDashboard();
setInterval(refreshDashboard, 3000); // refresh every 3 seconds