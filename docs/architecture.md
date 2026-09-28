# Architecture of Industrial Asset Condition Monitoring Platform

## Overview
This platform simulates industrial IoT asset monitoring: sensors publish telemetry over MQTT, a gateway service validates and forwards data to a backend API, which persists readings and triggers alerts when thresholds are exceeded.

## Components

| Component | Responsibility | Tech |
|---|---|---|
| Sensor Simulator | Publishes fake telemetry (temperature, vibration, battery) | Python + paho-mqtt |
| MQTT Broker | Message transport | Mosquitto (Docker) |
| IoT Gateway Simulator | Validates, buffers on backend outage, reconnects | Python |
| Backend API | Device/Telemetry/Alert services, persistence | FastAPI + PostgreSQL |
| Dashboard | Read-only device/alert view | Minimal HTML/React |

## Data Flow
Sensor → MQTT → Gateway → Backend API → PostgreSQL
                                      → Alert Engine → Dashboard

## Why a Gateway layer, not direct Sensor to Backend?
Mirrors real industrial IoT patterns: gateways buffer data during connectivity loss and validate payloads before they reach the backend — this is exactly what the resilience test suite (Week 2 of this project) verifies.

## Dashboard pages
- `index.html`: device list + global active alerts
- `device-detail.html?device_id=X`: per-device telemetry history + alerts, reached by clicking a device_id link. Alert filtering is done client-side (API lacks a device_id query param on /alerts), acceptable for this scale.