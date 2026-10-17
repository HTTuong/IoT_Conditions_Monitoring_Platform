# Test Strategy - Industrial Asset Condition Monitoring Platform

## Purpose

This document explains what is tested, why, how, and where each test runs. It is the entry point for anyone who wants to understand the test suite without reading every file. The detail of each individual risk lives in `risk-analysis.md`, the system design lives in `architecture.md`.

## Guiding principles

1. **Risk first.** Every test starts from a risk and follows the same chain: Risk → Expected behavior → Automation. A test without a risk behind it is not written, and a risk without a test is listed as open in `risk-analysis.md`.
2. **Evidence over assumption.** A behavior is documented only after a real run showed it. Several predictions made while designing the tests were wrong (for example an infinite temperature returned 500, not 422), and the real output replaced the prediction in the test and in the risk document.
3. **Real infrastructure, no mocks, for the failure modes.** Resilience tests stop the broker, freeze the backend, kill and restart the gateway, and read the gateway log. The same tests run against local processes and against the Docker Compose stack.
4. **Defects are visible, not hidden.** A known defect is never skipped or excluded from a run. It is either asserted as fixed behavior and left red on purpose, or pinned (see "How to read test status").
5. **Tests are independent.** Each test creates its own devices with unique ids and does not rely on data from another test.

## Scope

In scope: device management API, MQTT ingestion through the gateway, the dashboard in a browser, gateway resilience, anomaly detection and the alert lifecycle, security of the dashboard, data integrity of telemetry and device identity, and performance of the API under load.

Out of scope: authentication and authorization (accepted risk R-SEC-02), multi-browser and mobile testing (Chromium only), long-duration soak testing, and testing of the Mosquitto and PostgreSQL products themselves.

## Test levels and tools

| Level | Tool | What it verifies |
|---|---|---|
| API | Robot Framework with RequestsLibrary | Request validation, status codes, stored data, alert rules |
| Messaging | Robot Framework with MQTT keywords | Publish to the broker and observe the effect on the backend |
| UI | Robot Framework with the Browser library (Playwright, Chromium) | The dashboard shows devices and alerts, and renders hostile input as text |
| Resilience | Robot Framework with the Process library and Docker Compose | Behavior under broker, backend and gateway failures |
| Concurrency | Python helper libraries with a thread barrier (`LoadHelper`, `DataIntegrityHelper`) | Race conditions that a sequential test can never show |
| Performance | k6 | Latency and error rate under steady and mixed load |

## Test groups

The robot suite contains 59 tests.

| Group | Location | Tests | Focus | Main risks | Runs in CI |
|---|---|---|---|---|---|
| A. Device management | `robot/tests/device/` | 7 | Register, lifecycle (read, list, deactivate), duplicates, health check | none open | Yes |
| B. MQTT ingestion | `robot/tests/mqtt/` | 11 | Valid and invalid telemetry through the broker and gateway into the backend | none open | Yes |
| C. End-to-end | `robot/tests/e2e/` | 2 | Dashboard in a browser: registered devices and raised alerts are visible | none open | Yes |
| D. Resilience | `robot/tests/resilience/` | 7 | Backend outage, backlog and hang, broker restart, gateway outage and crash, poison message | R-GW-01 to R-GW-05 | Yes, in container mode |
| E. Anomaly and alert | `robot/tests/anomaly_alert/` | 14 | High temperature, threshold boundaries, alert lifecycle, concurrency | R-AL-01 | 13 of 14 (not `alert_concurrency.robot`) |
| F. Security | `robot/tests/security/` | 5 | Stored XSS on the dashboard. API hardening tests (CORS, CSP, id format) are planned | R-SEC-01, R-SEC-02 | Not yet |
| G. Data integrity | `robot/tests/data_integrity/` | 13 | Value ranges, non-finite numbers, timestamps, identity normalization, concurrent registration | R-DI-01 to R-DI-07 | Yes |
| H. Performance | `k6/lib/` | 2 scripts | Smoke test, mixed load with ingest and dashboard readers | `GET /alerts` has no filter or pagination | Not yet |

## Techniques used

- **Boundary value analysis.** Threshold tests check the value just below, at and just above the limit, and data integrity tests check the documented range limits (for example temperature -50 and 200, battery 0 and 100).
- **Data-driven tests.** Robot `Test Template` runs one scenario over many inputs, for example the padded device id cases.
- **Failure injection.** Services are stopped, paused and restarted, then the test waits for recovery and checks that no data was lost.
- **Concurrency testing.** A barrier releases many requests at the same instant to expose check-then-insert races (R-AL-01, R-DI-06).
- **Characterization (pinned defect) tests.** See below.
- **Control tests.** A passing sibling test proves that the failing behavior is specific. For example a battery-only reading must not close a temperature alert, which isolates the NaN defect R-DI-03.
- **Security payloads.** Device names and ids containing markup and script are registered through the API and the dashboard is inspected to confirm they are shown as text and never executed.

## Tags

Tags describe the area of a test and let a subset run with `--include`. Examples in use: `device`, `mqtt`, `gateway`, `resilience`, `anomaly_alert`, `data_integrity`, `security`, `xss`, `e2e`, `ui`, `smoke` and `control`. Data integrity tests also carry the risk id they document (for example `R-DI-02`), which links a test to its entry in `risk-analysis.md`.

## How to read test status

- **Green** normally means the behavior is correct.
- **Red on purpose** means the test asserts the correct behavior and fails because the defect is still present. Currently this is the alert concurrency test (R-AL-01).
- **Pinned defect** means the test asserts that a documented defect is still present, so green means the defect is still there. When the behavior changes, the test fails with a message starting "looks FIXED". The next step is to flip the assertion to the correct behavior and update `risk-analysis.md`. Currently R-DI-01 to R-DI-06 are pinned.

This keeps the whole suite green and trustworthy without hiding anything: a green run means every documented behavior, correct or not, is exactly as recorded.

## Test data

- Every test registers its own devices with unique ids, so tests can run in any order.
- There are no DELETE endpoints, so test data accumulates in the database. A clean state comes from recreating the stack (`docker compose down -v`), which is what CI does at the end of every run.
- The k6 scripts use the prefix `k6-load-` and register their 100 devices idempotently, treating 201 and 409 as success.

## Environments and execution modes

| Mode | Selected by | Backend and gateway | Used for |
|---|---|---|---|
| Process | `SERVICE_MODE:process` (default) | Local processes started by `dev.sh` | Daily development and debugging |
| Container | `SERVICE_MODE:docker` | Docker Compose profile `app` | CI and production-like runs |

Only the resilience keywords differ between the modes (start, stop and freeze of backend and gateway, gateway log access). All test files are the same in both modes. The browser runs headless with `--variable HEADLESS:True`.

## Running the tests

From the `robot/` directory, with the stack running:

```bash
robot -d results/all --variable HEADLESS:True tests
robot -d results/smoke --include smoke tests
robot -d results/resilience --variable SERVICE_MODE:docker tests/resilience
```

The first command runs everything, so it includes the one test that is red on purpose. The second runs only the smoke subset. The third runs the resilience group against the container stack.

## Continuous integration

The GitHub Actions workflow `.github/workflows/ci.yml` runs on pushes to `main` and `master` and on every pull request. It executes 53 of the 59 robot tests.

1. Build the images and start the stack: `docker compose --profile app up -d --build --wait`.
2. Install Python 3.13, Node 20, the robot dependencies and Chromium for Playwright.
3. Run groups A, B, C, G and the three anomaly files that do not depend on the known race (46 tests).
4. Run the resilience group separately in container mode, even if step 3 failed, so one failure does not hide the other (7 tests).
5. Upload the robot reports as an artifact, print the compose logs on failure and tear the stack down with `down -v`.

Deliberately not in CI, with the reason:

| Not in CI | Tests | Reason | Plan |
|---|---|---|---|
| `alert_concurrency.robot` | 1 | Red on purpose until R-AL-01 is fixed | Add when the fix lands |
| Security group | 5 | The XSS fix has not been verified against the container stack | Add after the first clean run |
| k6 | 2 scripts | No recorded load baseline to set thresholds against | Add the smoke test first, then the load test |

## Entry and exit criteria

- **Entry:** the stack is healthy (`up --wait` returned) and the backend answers `/health`.
- **Exit for a change:** the CI run is green, and any new defect found is recorded in `risk-analysis.md` with severity, evidence, root cause, suggested fix and status.
- **Release readiness:** no open item of severity High or Critical without an explicit decision. Today the accepted High item is R-SEC-02 (no authentication), and the High item R-SEC-01 awaits verification.

## Performance targets (k6)

- `k6/lib/smoke.js`: a short run that proves the scenario works before any load is applied.
- `k6/lib/load_mix.js`: an open model that ingests telemetry at a constant arrival rate (default 20 per second for 2 minutes) while a closed model of dashboard viewers (default 10) reads devices and alerts.
- Thresholds: failed requests below 1 percent, checks above 99 percent, no dropped iterations, p95 below 500 ms for telemetry posts and below 800 ms for reads. A run that breaks a threshold exits with code 99.
- The open model matters: a closed model slows down when the system slows down and hides overload, while a constant arrival rate keeps pushing and shows `dropped_iterations`.

## Known gaps and next steps

- API hardening tests (CORS, Content-Security-Policy, device id format) are planned but not written, so R-SEC-02 and the remaining part of R-SEC-01 have no automated coverage.
- The gateway buffer bound (R-GW-04) has no test because the expected policy (drop oldest, drop newest or block) is a product decision.
- Duplicate delivery (R-GW-05) is documented but not asserted, because an idempotency key does not exist yet.
- The security group is not in CI, and k6 has no recorded load baseline.
- No cross-browser or accessibility testing.
- The 500 caused by a whitespace-only device id (R-DI-05) is not yet diagnosed.