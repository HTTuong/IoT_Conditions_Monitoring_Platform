import http from 'k6/http';
import exec from 'k6/execution';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';
import { BASE_URL, DEVICE_COUNT, deviceId, registerDevices, randomReading, jsonParams } from './lib/config.js';

const RATE = Number(__ENV.RATE || 20);
const DURATION = __ENV.DURATION || '2m';
const VIEWERS = Number(__ENV.VIEWERS || 10);

// Exact number of 201 responses, to reconcile against the database afterwards.
const telemetryCreated = new Counter('telemetry_created');

export const options = {
  scenarios: {
    ingest: {
      executor: 'constant-arrival-rate',
      exec: 'ingest',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 20,
      maxVUs: 200,
    },
    dashboards: {
      executor: 'constant-vus',
      exec: 'dashboard',
      vus: VIEWERS,
      duration: DURATION,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    checks: ['rate>0.99'],
    dropped_iterations: ['count==0'],
    'http_req_duration{endpoint:telemetry_post}': ['p(95)<500'],
    'http_req_duration{endpoint:devices_list}': ['p(95)<800'],
    'http_req_duration{endpoint:alerts_open}': ['p(95)<800'],
    'http_req_duration{endpoint:alerts_all}': ['p(95)<800'],
    'http_req_duration{endpoint:telemetry_get}': ['p(95)<800'],
  },
};

export function setup() {
  registerDevices();
}

export function ingest() {
  const id = deviceId(exec.scenario.iterationInTest);
  const res = http.post(`${BASE_URL}/telemetry`, randomReading(id), jsonParams('telemetry_post'));
  const ok = check(res, { 'POST /telemetry is 201': (r) => r.status === 201 });
  if (ok) {
    telemetryCreated.add(1);
  }
}

function get(path, endpoint, extraTags = {}) {
  const res = http.get(`${BASE_URL}${path}`, { tags: { endpoint, ...extraTags } });
  check(res, { [`${endpoint} is 200`]: (r) => r.status === 200 });
  return res;
}

// One dashboard refresh: what the browser does every 3 seconds.
export function dashboard() {
  const id = deviceId(Math.floor(Math.random() * DEVICE_COUNT));
  get('/devices', 'devices_list');
  get('/alerts?resolved=false', 'alerts_open');
  get(`/telemetry/${id}`, 'telemetry_get', { name: 'GET /telemetry/{id}' });
  get('/alerts', 'alerts_all');
  sleep(3);
}