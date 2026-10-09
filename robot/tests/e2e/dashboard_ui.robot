*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Resource    ../../resources/mqtt_keywords.resource
Library    RequestsLibrary
Library    Browser    retry_assertions_for=10s
Library    ../../libraries/DeviceSimulator.py
Suite Setup    Start Suite
Suite Teardown    Stop Suite
Test Setup    New Context
Test Teardown    Close Context

*** Variables ***
${HEADLESS}    ${True}
${DEVICES_ROW}     css=\#devices-table tbody tr
${ALERTS_ROW}      css=\#alerts-table tbody tr

*** Test Cases ***
Dashboard Shows Offline Device Then Updates To Active Without Reload
    [Documentation]
    ...    Risk: the dashboard shows stale data, so an operator sees a working sensor as
    ...    offline (or never notices a new device) until they manually reload.
    ...    Expected: a freshly registered device appears as offline; after the sensor
    ...    publishes a reading, the same open page shows it as active via auto-refresh.
    [Tags]    e2e    ui
    ${device_id}=    Register Fresh Device
    Open Dashboard
    Get Text    ${DEVICES_ROW}:has-text("${device_id}") td:nth-child(3)    ==    offline
    ${reading}=    Generate Normal Reading
    Publish Reading    ${device_id}    ${reading}
    Get Text    ${DEVICES_ROW}:has-text("${device_id}") td:nth-child(3)    ==    active

Dashboard Shows Alert When Threshold Is Exceeded And Removes It After Recovery
    [Documentation]
    ...    Risk: an overheating sensor raises an alert in the backend but the operator never
    ...    sees it on screen, or the alert stays on screen after the equipment recovers.
    ...    Expected: a high_temperature row appears in Active Alerts for the device, and
    ...    disappears once a normal reading arrives.
    [Tags]    e2e    ui    anomaly_alert
    ${device_id}=    Register Fresh Device
    Open Dashboard
    ${anomaly}=    Generate Anomaly Reading
    ...    temperature_threshold=${TEMPERATURE_THRESHOLD}    vibration_threshold=${VIBRATION_THRESHOLD}
    ...    anomaly_type=temperature
    Publish Reading    ${device_id}    ${anomaly}
    Get Text    ${ALERTS_ROW}:has-text("${device_id}") td:nth-child(2)    ==    high_temperature
    ${normal}=    Generate Normal Reading
    Publish Reading    ${device_id}    ${normal}
    Get Element Count    ${ALERTS_ROW}:has-text("${device_id}")    ==    0

*** Keywords ***
Start Suite
    Create API Session
    New Browser    chromium    headless=${HEADLESS}

Stop Suite
    Close Browser
    Disconnect From Broker

Open Dashboard
    New Page    ${DASHBOARD_URL}

Get Devices Row
    RETURN    css=\#devices-table tbody tr