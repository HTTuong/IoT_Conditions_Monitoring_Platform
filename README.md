# Industrial Asset Condition Monitoring Platform

A simulated Industrial IoT platform built to practice quality-engineering techniques for distributed, asynchronous systems: sensor telemetry over MQTT, a resilient gateway, and automated testing across multiple layers (API, MQTT, end-to-end) with Robot Framework.

> This project is under active development. See [`docs/architecture.md`](docs/architecture.md) for design details and [`docs/risk-analysis.md`](docs/risk-analysis.md) for quality risks discovered so far.

## Table of Contents

- [Overview](#overview)
- [Architecture & Data Flow](#architecture--data-flow)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Backend API](#backend-api)
- [Dashboard](#dashboard)
- [Testing](#testing)
- [Project Status](#project-status)

## Overview

The system simulates a realistic industrial asset monitoring pipeline:

1. **Sensor Simulator** publishes fake telemetry (temperature, vibration, battery level) to an MQTT broker.

2. **IoT Gateway** subscribes to the broker, validates the data, and forwards it to the Backend API — buffering and retrying automatically whenever the backend is temporarily unreachable.

3. **Backend API** (FastAPI + PostgreSQL) persists devices and telemetry, automatically detects anomalies, and raises alerts.

4. **Dashboard** (static HTML/JS) shows the current devices and active alerts, auto-refreshing on an interval.

The design intentionally mirrors real industrial IoT failure modes — temporary disconnects, delayed delivery, transient vs. permanent errors, and so on. These are exactly the risks the Robot Framework test suite is being built to cover.

## Architecture & Data Flow

```
Sensor Simulator → MQTT Broker (Mosquitto) → Gateway → Backend API → PostgreSQL
                                                                    → Alert Engine → Dashboard
```

| Component | Responsibility | Tech |
|---|---|---|
| Sensor Simulator | Publishes fake telemetry (temperature, vibration, battery) | Python + `paho-mqtt` |
| MQTT Broker | Message transport | Eclipse Mosquitto (Docker) |
| IoT Gateway | Validates data, buffers on backend outage, reconnects | Python + `requests` |
| Backend API | Device/Telemetry/Alert management, persistence, anomaly detection | FastAPI + PostgreSQL (SQLAlchemy) |
| Dashboard | Read-only view of devices/alerts | Plain HTML/CSS/JS |

**Why a separate Gateway layer instead of Sensor → Backend directly?** It mirrors real industrial IoT patterns: gateways buffer data during connectivity loss and validate payloads before they reach the backend. This is exactly the behavior the resilience test suite is designed to verify.

## Tech Stack

- **Backend:** Python, FastAPI, SQLAlchemy 2.0, Pydantic v2, PostgreSQL
- **Gateway & Simulator:** Python, `paho-mqtt`, `requests`
- **Message broker:** Eclipse Mosquitto 2 (via Docker)
- **Testing:** `pytest` (backend unit tests), Robot Framework (API/MQTT/E2E/resilience suites — in progress)
- **Infrastructure:** Docker Compose (Mosquitto + PostgreSQL)

## Project Structure

```
.
├── docker-compose.yml          # Mosquitto + PostgreSQL
├── mosquitto/config/           # MQTT broker configuration
├── docs/
│   ├── architecture.md         # Detailed architecture design
│   └── risk-analysis.md        # Log of quality risks found and how they were fixed
├── services/
│   ├── backend/
│   │   ├── app/
│   │   │   ├── main.py         # FastAPI app setup, router + dashboard mounting
│   │   │   ├── config.py       # Environment-based settings (Pydantic Settings)
│   │   │   ├── database.py     # SQLAlchemy engine + session
│   │   │   ├── models.py       # Device, Telemetry, Alert models
│   │   │   ├── schemas.py      # Pydantic request/response schemas
│   │   │   ├── anomaly.py      # Temperature/vibration anomaly detection logic
│   │   │   ├── alert_service.py# Create/resolve alerts, deduplicated
│   │   │   └── routers/        # devices.py, telemetry.py, alerts.py
│   │   ├── static/              # index.html + dashboard.js
│   │   └── tests/               # Unit tests (pytest)
│   ├── gateway/src/gateway.py   # Subscribes to MQTT, forwards to Backend, buffers/retries
│   └── simulator/src/simulator.py # Publishes fake telemetry to MQTT
└── robot/                        # Robot Framework test suite (in progress)
    └── tests/
        ├── device/  mqtt/  e2e/  resilience/  anomaly_alert/  security/  data_integrity/
```

## Getting Started

### Prerequisites

- Python 3.13+
- Docker & Docker Compose

### 1. Start the infrastructure (MQTT broker + PostgreSQL)

```bash
docker compose up -d
```

Mosquitto listens on port `1883`, PostgreSQL on port `5432` (user `iot_user` / password `iot_password` / database `iot_monitoring`).

### 2. Install and run the Backend API

```bash
cd services/backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

The backend runs at `http://localhost:8000`. Database tables are created automatically on startup (`Base.metadata.create_all`). Configuration can be overridden via environment variables: `DATABASE_URL`, `MQTT_BROKER_HOST`, `MQTT_BROKER_PORT`, `TEMPERATURE_THRESHOLD`, `VIBRATION_THRESHOLD` (see [`app/config.py`](services/backend/app/config.py)).

### 3. Run the Gateway

```bash
cd services/gateway
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
python src/gateway.py
```

The gateway subscribes to the `factory/#` topic, forwards every telemetry message it receives to the Backend API, and automatically buffers and retries messages while the backend is unreachable.

### 4. Run the Sensor Simulator

```bash
cd services/simulator
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
python src/simulator.py
```

The simulator publishes fake readings for `sensor-001` to the topic `factory/line1/sensor-001/telemetry` every 5 seconds (with a 10% chance of generating an anomalous reading, to exercise the alerting path).

> **Note:** before the simulator/gateway traffic means anything, register the device via `POST /devices` (see the API section below) — telemetry for an unregistered device is rejected by the backend with `404`.

## Backend API

Base URL: `http://localhost:8000`

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/health` | Liveness check |
| `GET` | `/devices` | List all devices |
| `GET` | `/devices/{device_id}` | Get a single device |
| `POST` | `/devices` | Register a new device (`device_id`, `name`) |
| `PATCH` | `/devices/{device_id}/deactivate` | Set a device's status to `inactive` |
| `POST` | `/telemetry` | Ingest a telemetry reading; triggers anomaly detection |
| `GET` | `/telemetry/{device_id}` | Telemetry history for a device (defaults to the 50 most recent) |
| `GET` | `/alerts` | List alerts, optionally filtered with `?resolved=true/false` |

**Anomaly detection:** on every telemetry ingest, the backend compares `temperature`/`vibration` against configured thresholds (default 80°C and vibration 8). Exceeding a threshold raises a `high_temperature`/`high_vibration` alert (deduplicated against any already-open alert of the same type); returning to normal automatically resolves the corresponding alert.

A device's `status` automatically flips from `offline` to `active` as soon as it sends its first telemetry reading.

## Dashboard

A static dashboard is served at `http://localhost:8000/dashboard/`, showing two tables — **Devices** (with status) and **Active Alerts** — refreshed every 3 seconds via calls to `/devices` and `/alerts?resolved=false`. Source: [`services/backend/static/`](services/backend/static/).

## Testing

### Unit tests (pytest)

```bash
cd services/backend
pytest
```

There is currently a test suite for the anomaly detection logic ([`tests/test_anomaly.py`](services/backend/tests/test_anomaly.py)), covering normal readings, threshold breaches, boundary values, missing data, and negative values.

### Robot Framework (in progress)

The folder structure has been laid out under [`robot/tests/`](robot/tests/) for seven test groups, mapped to the risks tracked in [`docs/risk-analysis.md`](docs/risk-analysis.md):

- `device/` — device management
- `mqtt/` — MQTT telemetry validation
- `e2e/` — end-to-end flow: Sensor → Gateway → Backend → Dashboard
- `resilience/` — MQTT/backend outages, buffering, reconnection (current focus)
- `anomaly_alert/` — anomaly detection and alert creation/resolution
- `security/` — security testing
- `data_integrity/` — data integrity (e.g., the buffer must never grow unbounded)

Actual test cases will be added incrementally as the project progresses; see `docs/risk-analysis.md` for gaps already found through manual testing that are pending automation.

## Project Status

- [x] Architecture defined
- [x] MQTT broker + Sensor Simulator
- [x] Gateway (forwarding, buffer/retry, reconnect, persistent session)
- [x] Backend API (FastAPI + PostgreSQL): Device/Telemetry/Alert, anomaly detection
- [x] Minimal dashboard
- [ ] Full Robot Framework test suite (folder structure in place, test cases being written)
- [ ] Dockerize Backend/Gateway/Simulator + CI/CD

See [`docs/architecture.md`](docs/architecture.md) and [`docs/risk-analysis.md`](docs/risk-analysis.md) for more detail on the design and the quality risks addressed so far.
