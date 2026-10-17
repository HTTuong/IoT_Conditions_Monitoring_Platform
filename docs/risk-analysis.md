# Risk Analysis - Industrial Asset Condition Monitoring Platform

## Purpose

This document tracks quality risks identified in the system and how each one maps to expected behavior and automated test coverage. The format for each entry is:

> **Risk** → what could go wrong and why it matters
> **Expected behavior** → what the system should do instead
> **Automation** → which test layer verifies this (or "pending" if not yet automated)

This is a living document. The first entries below were identified through manual exploratory testing during development, before the Robot Framework test suite existed. Every later entry was found by an automated test, which is named in its "Found by" line.

Last updated: 2026-10-17.

## How to read test status

- **Green** normally means the behavior is correct.
- **Red on purpose** (R-AL-01) means the test asserts the correct behavior and fails because the defect is still present.
- **Pinned defect** (R-DI-01 to R-DI-06) means the test asserts that the documented defect is still present. Green means the defect is still there. When the behavior changes, the test fails with a message starting "looks FIXED". Flip the assertion to the correct behavior and update the entry here.

---

## Gaps identified during manual end-to-end validation

### 1. Gateway buffered permanent errors as if they were transient

**Risk.** The gateway's retry-queue logic (built to survive temporary backend outages) did not distinguish between a *transient* failure (backend unreachable, connection refused) and a *permanent* failure (backend reachable, but rejects the request, for example `404` for an unregistered device). Both cases returned the same `False` from `forward_to_backend()`, so both were buffered for retry. A permanently-rejected message would sit in the queue forever, since retrying it can never succeed, silently filling the buffer with unrecoverable data.

**Expected behavior.** Only genuinely transient errors (network/connection failures) should be buffered and retried. Permanent rejections (client errors like `404`) should be logged and dropped, retrying them wastes resources and masks the real problem (an unregistered or misconfigured device).

**Resolution.** `forward_to_backend()` first treated a `404` response as "handled, no retry needed" (returns `True` without buffering), while a `ConnectionError` (backend down) was treated as transient and buffered. The fix was later generalized to all permanent client errors, see R-GW-02.

**Automation.** Covered by `tests/resilience/poison_message.robot` (R-GW-02) and `tests/resilience/backend_backlog.robot` (R-GW-04).

---

### 2. Initial belief that the gateway did not auto-reconnect to MQTT

**Risk (as initially assumed).** It was believed the gateway required a manual restart to recover after losing its connection to the Mosquitto broker, which would mean any broker outage causes a permanent, unrecoverable outage for the gateway.

**Finding on closer inspection.** This assumption was incorrect. `paho-mqtt`'s `loop_start()` performs automatic reconnection by default (`reconnect_on_failure=True`), using exponential backoff. The gateway was already recovering its MQTT connection automatically, the earlier observation of "it looks stuck" was due to a lack of `on_disconnect` logging, not a lack of reconnection logic.

**Expected behavior.** The gateway should reconnect to the broker automatically after a broker outage, without manual intervention, and should log connection state changes for observability.

**Resolution.** Added an `on_disconnect` callback for visibility and tuned `reconnect_delay_set(min_delay=1, max_delay=10)` for faster recovery during testing. No change was needed to the reconnection mechanism itself, since it already worked.

**Automation.** `tests/resilience/broker_restart.robot` (broker stopped and started while the gateway keeps running).

---

### 3. Messages published while the gateway was disconnected were lost permanently

**Risk.** This was the real, previously-undetected gap. While the gateway's MQTT connection was down (e.g. during a Mosquitto restart), any telemetry the sensor simulator published during that window was lost entirely, the gateway was never subscribed at the time those messages were sent, so it never received them, and MQTT's default (non-persistent) session does not retain them. This is a distinct failure mode from the backend-outage buffering (Gap #1 above): here, data never reaches the gateway at all, versus reaching the gateway but failing to reach the backend.

**Expected behavior.** Telemetry published while the gateway is briefly offline should still be delivered once the gateway reconnects, up to the broker's queuing limits, matching how a real industrial gateway would be expected to behave, since sensors have no way of knowing the gateway is temporarily unreachable.

**Resolution.** Configured the gateway with a persistent MQTT session (`clean_session=False` with a fixed `client_id`) and subscribed at QoS 1 (matching the QoS 1 the sensor simulator already publishes at). This instructs the broker to queue QoS ≥ 1 messages for the gateway while it is offline and deliver them on reconnect. Verified manually: stopping Mosquitto for 20 to 30 seconds while the simulator continued publishing no longer resulted in missing rows in the `telemetry` table after reconnect.

**Automation.** `tests/resilience/gateway_outage.robot` ("Readings Published While Gateway Is Offline Are Delivered After It Restarts") and `tests/resilience/broker_restart.robot`.

---

### 4. StaticFiles html=True mode requires the file to be named exactly "index.html"

**Risk.** The dashboard file was created as `dashboard.html`, expecting FastAPI's `StaticFiles(html=True)` to auto-serve it at the mounted directory URL (`/dashboard/`). This does not work. Starlette's html mode only auto-serves a file literally named `index.html` for directory-style requests, any other filename returns 404 even if it's the only file present.

**Resolution.** Renamed `dashboard.html` → `index.html`. `dashboard.js` filename unaffected since it's referenced explicitly by `<script src="dashboard.js">`, not relied upon for directory-index auto-discovery.

---

## Risk coverage by test group

| Test group | Status | Risk entries |
|---|---|---|
| Device management | Automated (`tests/device/`, 7 tests) | No open risks recorded |
| MQTT telemetry validation | Automated (`tests/mqtt/`, 11 tests, covering ingestion from the broker through the gateway into the backend) | No open risks recorded |
| End-to-end | Automated (`tests/e2e/dashboard_ui.robot`, 2 browser tests) | No open risks recorded |
| **Resilience** | Automated (`tests/resilience/`, 7 tests, all pass) | R-GW-01, R-GW-02, R-GW-03 (fixed); R-GW-04, R-GW-05 (open) |
| Anomaly / Alert | Automated (`tests/anomaly_alert/`, 14 tests: 13 pass, 1 red on purpose) | R-AL-01 (open) |
| Security | XSS tests automated (`tests/security/xss_dashboard.robot`, 5 tests). API hardening tests (CORS, CSP, device id format) are planned and not written yet | R-SEC-01 (fix delivered, pending verification); R-SEC-02 (accepted) |
| Data integrity | Automated (`tests/data_integrity/`, 13 tests, all pass; defects R-DI-01 to R-DI-06 are pinned) | R-DI-01 to R-DI-06 (open); R-DI-07 (fixed) |
| Performance (k6) | Scripts written (`k6/smoke.js`, `k6/load_mix.js`), no run recorded yet | Candidate: `GET /alerts` has no filter or pagination (see Design observations) |

---

## Resilience (gateway)

### R-GW-01: Readings buffered in the gateway are lost if the gateway crashes

- **Severity:** High (silent data loss, no alert)
- **Found by:** `tests/resilience/gateway_outage.robot`, test "Gateway Crash With Buffered Readings Must Not Lose Them"
- **Scenario:** The backend is down, the gateway buffers 3 readings in its in-memory `deque`, then the gateway process dies and is restarted after the backend is back.
- **Observed (before the fix):** 0 of 3 readings are stored.
- **Root cause:** `gateway.py` accepted the MQTT message (paho acknowledges QoS 1 as soon as `on_message` returns) before the backend had accepted the reading. The broker therefore considered it delivered, and the only remaining copy was in process memory.
- **Fix applied:** The MQTT client is created with `manual_ack=True`. A message is acknowledged only after the backend returned 201, or after the gateway deliberately dropped it as permanently unprocessable. A reading that only exists in the in-memory buffer stays unacknowledged at the broker, so a restarted gateway receives it again (persistent session, `client_id="gateway-1"`).
- **Residual risk:** At-least-once delivery means duplicates are possible, see R-GW-05.
- **Status:** Fixed. Verified by the Resilience suite (7 of 7 tests pass).

### R-GW-02: A permanently rejected reading blocks every reading buffered behind it

- **Severity:** High (data loss after any transient outage, plus an endless retry loop)
- **Found by:** `tests/resilience/poison_message.robot`, test "Rejected Reading Must Not Block Valid Readings Buffered Behind It"
- **Scenario:** The backend rejects one reading with 422 (temperature 999). The gateway buffers it. The backend then goes down briefly, a valid reading is buffered behind the rejected one. The backend recovers.
- **Observed (before the fix):** 0 of 1 valid readings stored. The gateway retries the rejected reading every 5 s forever.
- **Root cause:** `forward_to_backend` returned `False` for any non-201 status, so a 4xx (permanent client error) was treated like a connection error (transient). The retry loop only ever looks at the head of the queue, so one permanent failure stalls the whole queue.
- **Fix applied:** `forward_to_backend` returns one of three results: OK, RETRY or DROP. Transient failures (network errors, timeouts, 5xx, and 408/429) are retried. Other 4xx responses and malformed messages are logged and dropped (acknowledged). While anything is buffered, new messages are queued behind it so that FIFO order is preserved.
- **Residual risk:** Dropped readings are only visible in the gateway log. There is no dead-letter store, so a misconfigured device loses data without a durable trace.
- **Status:** Fixed. Verified by the Resilience suite (7 of 7 tests pass).

### R-GW-03: A hung backend kills the gateway's MQTT thread (silent zombie gateway)

- **Severity:** Critical (all ingestion stops, no error surfaced, process still looks healthy)
- **Found by:** `tests/resilience/backend_hang.robot`, test "Gateway Survives A Hung Backend And Delivers After It Recovers"
- **Scenario:** The backend accepts the TCP connection but does not answer (frozen process, overloaded, deadlocked). Simulated with SIGSTOP.
- **Observed (before the fix):** `requests.exceptions.ReadTimeout` is raised inside `on_message`, the paho network thread (`paho-mqtt-client-gateway-1`) terminates. The gateway process stays alive but no longer consumes MQTT messages and never reconnects.
- **Root cause:** `forward_to_backend` only caught `requests.exceptions.ConnectionError`. A read timeout is a different exception, and an uncaught exception in a paho callback ends its thread.
- **Fix applied:** `forward_to_backend` catches `requests.exceptions.RequestException` (timeouts included) and treats it as transient. `on_message` is wrapped in `try/except` so no exception can escape into paho, and the retry loop in the main thread is wrapped as well.
- **Residual risk:** There is still no liveness signal (health endpoint or heartbeat), so a stuck gateway would still look healthy from the outside.
- **Status:** Fixed. Verified by the Resilience suite (7 of 7 tests pass).

### R-GW-04: The gateway buffer has no explicit bound

- **Severity:** Low to Medium (memory growth during a very long backend outage)
- **Found by:** Code review of `gateway.py` (`buffer = deque()` has no `maxlen`), then observed in `tests/resilience/backend_backlog.robot`, which publishes 50 readings during an outage and checks that all are delivered afterwards.
- **Observed:** The gateway's queue size did not reach 50 during the outage (the test waits for `Queue size: 10`). With `manual_ack=True` the broker stops delivering once its in-flight window is full (Mosquitto `max_inflight_messages`, default 20), so the remaining readings wait in the broker's per-client queue instead of the gateway's memory.
- **Remaining risk:** The deque itself is still unbounded in code. The broker's per-client queue limit (`max_queued_messages`) has not been verified in this repository's Mosquitto configuration, so it is unknown at what backlog size the broker starts dropping messages.
- **Suggested fix:** Verify and set the broker limits explicitly, cap the gateway buffer, decide whether to drop the oldest or newest reading when full, log every drop, and expose the queue size as a metric.
- **Status:** Open. Partly mitigated by the broker's in-flight window. A policy decision is needed before a test can assert a limit.

### R-GW-05: A retried reading can be stored twice (at-least-once delivery)

- **Severity:** Medium (duplicate rows distort history and can repeat alerts)
- **Found by:** `tests/resilience/backend_hang.robot`, which asserts at least one stored copy of a sentinel reading (temperature 55.5) instead of exactly one.
- **Scenario:** The backend is slow or hung. The gateway's request times out, but the backend may still process it later. The gateway retries, so the same reading can be stored twice.
- **Root cause:** Delivery is at-least-once by design (the gateway acknowledges after the backend accepts) and the reading carries no unique message id, so the backend cannot recognize a repeat.
- **Suggested fix:** Include a unique message id in each reading and enforce uniqueness in the backend (unique constraint, with a repeat answered as already stored).
- **Status:** Open, accepted trade-off: at-least-once was chosen over silent data loss. An idempotency key would remove the duplicates.

## Anomaly / Alert

### R-AL-01: Concurrent anomalous readings create duplicate active alerts

- **Severity:** Medium (duplicate alerts for one condition, resolved together later only by accident)
- **Found by:** `tests/anomaly_alert/alert_concurrency.robot`, which sends simultaneous anomalous readings for the same device through a barrier (`LoadHelper.post_concurrently`).
- **Observed:** The recorded run showed 3 devices with 2 active alerts of the same type, where at most 1 is allowed.
- **Root cause:** `create_alert_if_not_duplicate` does a SELECT followed by an INSERT with no unique constraint, so two concurrent requests both see "no active alert" and both insert.
- **Suggested fix:** Clean up existing duplicates, add a partial unique index on `alerts (device_id, alert_type) WHERE resolved = false`, and catch `IntegrityError` in `alert_service.py` (rollback and return `None`).
- **Status:** Open. Fix deferred. The test stays red on purpose.

## Security

### R-SEC-01: Stored XSS in the dashboard

- **Severity:** High (any party that can register a device can run script in an operator's browser)
- **Found by:** `tests/security/xss_dashboard.robot`, tests "Markup In Device Name Is Displayed As Text, Not Parsed", "Markup In Device Id Is Displayed As Text, Not Parsed" and "Script In Device Name Does Not Execute". Two control tests (plain name, device id from the URL on the detail page) pass.
- **Observed:** A device name of `<b>…</b>` was rendered as bold HTML instead of text, and a script payload in a device name executed (the page title became `XSS-EXECUTED`).
- **Root cause:** `dashboard.js` built table rows with `innerHTML` and unescaped values (`device_id`, `name`, `status`, alert fields). `device-detail.js` did the same for telemetry and alert rows. The API accepts any characters in `device_id` and `name`.
- **Fix delivered:** Build cells with `createElement` and `textContent` in `dashboard.js` and `device-detail.js`, and use `encodeURIComponent` for the device link and the telemetry URL.
- **Remaining work:** Restrict the `device_id` format in the API and add a Content-Security-Policy header. Tests for both are planned in a new `tests/security/api_hardening.robot`, which does not exist yet.
- **Status:** Open until `xss_dashboard.robot` is re-run and passes 5 of 5, then mark as Fixed in the UI.

### R-SEC-02: No authentication or authorization on any endpoint

- **Severity:** High in production, accepted for this portfolio project
- **Details:** Every endpoint, including device registration and deactivation, is open, and CORS allows any origin (`allow_origins=["*"]`). Anyone who can reach the API can create devices, post telemetry or deactivate devices.
- **Planned coverage:** A test that pins the current CORS behavior (any origin allowed) is planned in `tests/security/api_hardening.robot`, which does not exist yet.
- **Status:** Accepted risk, out of scope. A production version would need API keys or JWT, role checks and a restricted CORS origin list.

## Data integrity

### R-DI-01: Battery level has no range check

- **Severity:** Medium (impossible values stored and displayed)
- **Found by:** `tests/data_integrity/telemetry_values.robot`, test "Defect R-DI-01: Out Of Range Battery Is Currently Accepted"
- **Observed:** `battery` 101 and -1 both return 201 and are stored unchanged.
- **Root cause:** `TelemetryCreate` validates `temperature` and `vibration` but not `battery`.
- **Suggested fix:** `battery: Optional[float] = Field(default=None, ge=0, le=100)`.
- **Status:** Open, pinned by test.

### R-DI-02: NaN and Infinity are accepted, and infinite temperature crashes the error response

- **Severity:** Medium (corrupt rows stored, and a 500 instead of a clean 422)
- **Found by:** `tests/data_integrity/telemetry_values.robot`, tests "Defect R-DI-02: Non-Finite Numbers Are Currently Accepted" and "Defect R-DI-02: Infinite Temperature Currently Crashes With 500"
- **Observed:** `temperature` NaN, `vibration` NaN and Infinity, and `battery` NaN and Infinity all return 201. `temperature` Infinity returns 500.
- **Root cause:** Every comparison with NaN is false, so the range validators let it through, and `vibration` and `battery` have no upper bound. For `temperature` Infinity the validator does reject the value, but FastAPI echoes the non-finite input in the 422 body and the JSON encoder cannot encode it.
- **Suggested fix:** `allow_inf_nan=False` on the three numeric fields, and a custom `RequestValidationError` handler that drops the echoed `input` from the error body.
- **Status:** Open, pinned by test.

### R-DI-03: A NaN temperature closes an open high-temperature alert

- **Severity:** High (a genuine overheating alert is silently closed)
- **Found by:** `tests/data_integrity/telemetry_integrity.robot`, test "Defect R-DI-03: NaN Reading Currently Closes An Open Alert"
- **Scenario:** A device has an open `high_temperature` alert (reading 120.0). A reading with `"temperature": NaN` arrives.
- **Observed:** The alert is resolved. The control test (a battery-only reading) leaves the alert open, because `detect_anomaly` only evaluates metrics that are present.
- **Root cause:** `NaN > threshold` is false, so `detect_anomaly` lists the temperature as normal and `resolve_alerts_for_type` closes the alert.
- **Suggested fix:** Reject non-finite values at the API (R-DI-02). Optionally treat a non-finite value as "no data" in `detect_anomaly`.
- **Status:** Open, pinned by test. Resolved by the R-DI-02 fix.

### R-DI-04: Timestamps carry no timezone offset

- **Severity:** Medium (times shown on the dashboard are wrong by the viewer's UTC offset, 3 hours in Finland)
- **Found by:** `tests/data_integrity/telemetry_integrity.robot`, test "Defect R-DI-04: Telemetry Timestamp Currently Has No Timezone Offset"
- **Observed:** The API returns `2026-10-14T19:23:27.536080`, which is UTC but carries no offset, so browsers read it as local time. By the same code path, device and alert `created_at` have the same problem (read from the code, not tested).
- **Root cause:** Columns use `datetime.utcnow` (naive) and the response schemas serialize the naive value as is.
- **Suggested fix:** Serialize with an explicit UTC offset in the response schemas (a `field_serializer`), or store timezone-aware datetimes.
- **Status:** Open, pinned by test.

### R-DI-05: Device identity fields are not normalized

- **Severity:** Low to Medium (look-alike duplicate devices, blank entries)
- **Found by:** `tests/data_integrity/device_identity.robot`, tests "Defect R-DI-05: Whitespace-Only Device Id Is Currently Not Rejected", "Whitespace-Only Device Name Is Currently Accepted" and "Padded Device Id Is Currently Stored Untrimmed"
- **Observed:** A whitespace-only name returns 201. An id with leading or trailing spaces is stored exactly as sent, so `" dev-1"` and `"dev-1"` are different devices. A whitespace-only id (3 spaces) returned 500; the cause has not been diagnosed, so that test only asserts the response is not 422.
- **Root cause:** `min_length` counts whitespace and nothing trims the input.
- **Suggested fix:** `model_config = ConfigDict(str_strip_whitespace=True)` on `DeviceCreate` and `TelemetryCreate`. Diagnose the 500 from the backend log.
- **Status:** Open, pinned by test.

### R-DI-06: Concurrent registration of one device id returns 500

- **Severity:** Low (no duplicate data, but a misleading error)
- **Found by:** `tests/data_integrity/device_identity.robot`, test "Defect R-DI-06: Concurrent Registrations Of One Id Currently Produce 500s"
- **Observed:** In one round of 10 simultaneous requests: one 201, six 409 and three 500. Every round creates exactly one device.
- **Root cause:** Registration is check-then-insert. The unique constraint on `devices.device_id` prevents duplicates, but the `IntegrityError` it raises is not handled.
- **Suggested fix:** Catch `IntegrityError` around the commit in `register_device`, roll back and answer 409.
- **Status:** Open, pinned by test.

### R-DI-07: A reading with no measurements was stored as a row of nulls

- **Severity:** Medium (history polluted, a silent device looks active)
- **Found by:** `tests/data_integrity/telemetry_validation.robot`, test "Telemetry Without Any Measurement Is Rejected"
- **Observed (before the fix):** 201 instead of 422, and a row with every measurement null.
- **Fix applied:** A `model_validator` on `TelemetryCreate` requires at least one measurement.
- **Status:** Fixed. The test passes.

### Verified behaviors (controls that pass)

- Boundary values (`temperature` -50 and 200, `vibration` 0, `battery` 0 and 100, and values such as 36.6 and 33.3) are accepted and stored unchanged.
- A reading without temperature does not close an open high-temperature alert.
- Telemetry from a deactivated device does not reactivate it (the status stays `inactive`).

## Design observations (no test yet)

- Alerts stay open forever if a device stops sending the metric that raised them. They are only closed by a later normal reading of the same metric.
- `GET /alerts` has no device filter and no pagination, so its cost grows with the whole alert history and every device page filters in the browser. This is a target for the k6 performance group.
- `GET /telemetry/{device_id}` returns at most 50 readings by default (`limit=50`), so tests that count more than 50 records must raise the limit.
- A deactivated device still accepts and stores telemetry. Only its status is protected. Whether such readings should be rejected is a product decision.
- There are no DELETE endpoints, so test data accumulates in the database.