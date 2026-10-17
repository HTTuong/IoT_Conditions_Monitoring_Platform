import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL, deviceId, registerDevices, randomReading, jsonParams } from './lib/config.js';

export const options = {
  vus: 1,
  iterations: 20,
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<1000'],
    checks: ['rate==1'],
  },
};

export function setup() {
  registerDevices();
}

export default function () {
  const id = deviceId(__ITER);

  const health = http.get(`${BASE_URL}/health`, { tags: { endpoint: 'health' } });
  const created = http.post(`${BASE_URL}/telemetry`, randomReading(id), jsonParams('telemetry_post'));
  const devices = http.get(`${BASE_URL}/devices`, { tags: { endpoint: 'devices_list' } });
  const history = http.get(`${BASE_URL}/telemetry/${id}`, {
    tags: { endpoint: 'telemetry_get', name: 'GET /telemetry/{id}' },
  });
  const alerts = http.get(`${BASE_URL}/alerts?resolved=false`, { tags: { endpoint: 'alerts_open' } });

  check(health, { 'GET /health is 200': (r) => r.status === 200 });
  check(created, { 'POST /telemetry is 201': (r) => r.status === 201 });
  check(devices, { 'GET /devices is 200': (r) => r.status === 200 });
  check(history, { 'GET /telemetry/{id} is 200': (r) => r.status === 200 });
  check(alerts, { 'GET /alerts is 200': (r) => r.status === 200 });

  sleep(0.2);
}