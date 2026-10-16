import http from 'k6/http';

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
export const DEVICE_COUNT = Number(__ENV.DEVICES || 100);

const JSON_HEADERS = { 'Content-Type': 'application/json' };

export function deviceId(index) {
  return `k6-load-${String(index % DEVICE_COUNT).padStart(3, '0')}`;
}

export function jsonParams(endpoint) {
  return { headers: JSON_HEADERS, tags: { endpoint } };
}

// Idempotent: 201 on the first run, 409 afterwards. Both are expected, so neither counts as a failure.
export function registerDevices() {
  const params = {
    headers: JSON_HEADERS,
    responseCallback: http.expectedStatuses(201, 409),
    tags: { endpoint: 'setup' },
  };
  for (let i = 0; i < DEVICE_COUNT; i++) {
    const body = JSON.stringify({ device_id: deviceId(i), name: `K6 load device ${i}` });
    http.post(`${BASE_URL}/devices`, body, params);
  }
}

function randomBetween(min, max) {
  return min + Math.random() * (max - min);
}

// 5% of readings exceed the alert thresholds (assumed 80 for temperature, 8 for vibration),
// so the alert-creation path is exercised under load too.
export function randomReading(id) {
  const anomalous = Math.random() < 0.05;
  return JSON.stringify({
    device_id: id,
    temperature: anomalous ? randomBetween(85, 95) : randomBetween(40, 70),
    vibration: randomBetween(0.5, 5),
    battery: randomBetween(20, 100),
    connectivity: 'good',
  });
}