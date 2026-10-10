# Risk Analysis - Industrial Asset Condition Monitoring Platform

## Purpose

This document tracks quality risks identified in the system and how each one maps to expected behavior and (eventually) automated test coverage. The format for each entry is:

> **Risk** → what could go wrong and why it matters
> **Expected behavior** → what the system should do instead
> **Automation** → which test layer verifies this (or "pending" if not yet automated)

This is a living document. Entries below were identified through manual exploratory testing during development, before the Robot Framework test suite existed, automated coverage will be added and cross-referenced as each test group (Device, MQTT, E2E, Resilience, Anomaly/Alert, Security, Data Integrity) is implemented in later project weeks.

---

## Gaps identified during manual end-to-end validation

### 1. Gateway buffered permanent errors as if they were transient

**Risk.** The gateway's retry-queue logic (built to survive temporary backend outages) did not distinguish between a *transient* failure (backend unreachable — connection refused) and a *permanent* failure (backend reachable, but rejects the request.For example, `404` for an unregistered device). Both cases returned the same `False` from `forward_to_backend()`, so both were buffered for retry. A permanently-rejected message would sit in the queue forever, since retrying it can never succeed, silently filling
the buffer with unrecoverable data.

**Expected behavior.** Only genuinely transient errors (network/connection failures) should be buffered and retried. Permanent rejections (client errors like `404`) should be logged and dropped, retrying them wastes resources and masks the real problem (an unregistered or misconfigured device).

**Resolution.** `forward_to_backend()` now treats a `404` response as "handled, no retry needed" (returns `True` without buffering), while a `ConnectionError` (backend down) is treated as transient and buffered.

**Automation.** Pending will be covered by Resilience group tests (T25–T28) and a dedicated Data Integrity case verifying the buffer never grows unbounded from permanently-unrecoverable messages.

---

### 2. Initial belief that the gateway did not auto-reconnect to MQTT

**Risk (as initially assumed).** It was believed the gateway required a manual restart to recover after losing its connection to the Mosquitto broker, which would mean any broker outage causes a permanent, unrecoverable outage for the gateway.

**Finding on closer inspection.** This assumption was incorrect. `paho-mqtt`'s `loop_start()` performs automatic reconnection by default (`reconnect_on_failure=True`), using exponential backoff. The gateway was already recovering its MQTT connection automatically; the earlier observation of "it looks stuck" was due to a lack of `on_disconnect` logging, not a lack of reconnection logic.

**Expected behavior.** The gateway should reconnect to the broker automatically after a broker outage, without manual intervention, and should log connection state changes for observability.

**Resolution.** Added an `on_disconnect` callback for visibility and tuned `reconnect_delay_set(min_delay=1, max_delay=10)` for faster recovery during testing.
No change was needed to the reconnection mechanism itself, since it already worked.

**Automation.** Pending - Resilience group, "gateway disconnects → reconnects" (T23–T24).

---

### 3. Messages published while the gateway was disconnected were lost permanently

**Risk.** This was the real, previously-undetected gap. While the gateway's MQTT connection was down (e.g. during a Mosquitto restart), any telemetry the sensor simulator published during that window was lost entirely, the gateway was never subscribed at the time those messages were sent, so it never received them, and MQTT's default (non-persistent) session does not retain them. This is a distinct failure mode from the backend-outage buffering (Gap #1 above): here, data never reaches the gateway at all, versus reaching the gateway but failing to reach the backend.

**Expected behavior.** Telemetry published while the gateway is briefly offline should still be delivered once the gateway reconnects, up to the broker's queuing limits, matching how a real industrial gateway would be expected to behave, since sensors have no way of knowing the gateway is temporarily unreachable.

**Resolution.** Configured the gateway with a persistent MQTT session (`clean_session=False` with a fixed `client_id`) and subscribed at QoS 1 (matching the QoS 1 the sensor simulator already publishes at). This instructs the broker to queue QoS ≥ 1 messages for the gateway while it is offline and deliver them on reconnect.
Verified manually: stopping Mosquitto for ~20–30 seconds while the simulator continued publishing no longer resulted in missing rows in the `telemetry` table after reconnect.

**Automation.** Pending - this will become the centerpiece of the Resilience group: "MQTT broker unavailable → recovers" (T21–T22) and "verify buffered messages eventually arrive" (T27–T28).

### 4. StaticFiles html=True mode requires the file to be named exactly "index.html"

**Risk.** The dashboard file was created as `dashboard.html`, expecting FastAPI's `StaticFiles(html=True)` to auto-serve it at the mounted directory URL (`/dashboard/`). This does not work — Starlette's html mode only auto-serves a file literally named `index.html` for directory-style requests; any other filename returns 404 even if it's
the only file present.

**Resolution.** Renamed `dashboard.html` → `index.html`. `dashboard.js` filename unaffected since it's referenced explicitly by `<script src="dashboard.js">`, not relied upon for directory-index auto-discovery.

---

## Planned risk coverage by test group

The table below will be filled in with specific risk entries as each Robot Framework test group is implemented in later project weeks. Listed now as a placeholder so the document's structure is established early, rather than backfilled at the end.

| Test group | Status | Risk entries |
|---|---|---|
| Device management | Not yet automated | TBD |
| MQTT telemetry validation | Not yet automated | TBD |
| End-to-end | Not yet automated | TBD |
| **Resilience** | Not yet automated | Gaps #1-#3 above are the seed risks for this group |
| Anomaly / Alert | Not yet automated | TBD |
| Security | Not yet automated | TBD |
| Data integrity | Not yet automated | TBD |

### R-GW-01: Readings buffered in the gateway are lost if the gateway crashes

- **Severity:** High (silent data loss, no alert)
- **Found by:** `tests/resilience/gateway_outage.robot` — "Gateway Crash With Buffered Readings Must Not Lose Them" (tag: `known-bug`)
- **Scenario:** The backend is down, the gateway buffers 3 readings in its in-memory `deque`, then the gateway process dies and is restarted after the backend is back.
- **Observed:** 0 of 3 readings are stored.
- **Root cause:** `gateway.py` accepts the MQTT message (paho acknowledges QoS 1 as soon as `on_message` returns) before the backend has accepted the reading. The broker therefore considers it delivered, and the only remaining copy is in process memory.
- **Suggested fix:** acknowledge the MQTT message manually only after the backend returns 201
  (`manual_ack=True`, `client.ack(...)`), or persist the buffer to disk.
- **Status:** Open. The test stays red on purpose and is excluded from CI gating with `--exclude known-bug` until the fix lands.


### R-GW-02: A permanently rejected reading blocks every reading buffered behind it

- **Severity:** High (data loss after any transient outage, plus an endless retry loop)
- **Found by:** `tests/resilience/poison_message.robot` — "Rejected Reading Must Not Block Valid Readings Buffered Behind It" (tag: `known-bug`)
- **Scenario:** The backend rejects one reading with 422 (temperature 999). The gateway buffers it. The backend then goes down briefly; a valid reading is buffered behind the rejected one. The backend recovers.
- **Observed:** 0 of 1 valid readings stored. The gateway retries the rejected reading every 5 s forever.
- **Root cause:** `forward_to_backend` returns `False` for any non-201 status, so a 4xx (permanent client error) is treated like a connection error (transient). The retry loop only ever looks at the head of the queue, so one permanent failure stalls the whole queue.
- **Suggested fix:** buffer only transient failures (connection errors, 5xx, timeouts); drop or park 4xx readings in a dead-letter list and log them; cap retries per reading.
- **Status:** Open. Test stays red on purpose and is excluded from CI gating with `--exclude known-bug`.