*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Library    RequestsLibrary
Library    ../../libraries/MqttLibrary.py    ${MQTT_BROKER_HOST}    ${MQTT_BROKER_PORT}
Library    ../../libraries/DeviceSimulator.py
Library    ../../libraries/TelemetryValidator.py
Suite Setup    Create API Session
Suite Teardown    Disconnect From Broker

*** Test Cases ***
Valid Telemetry Published To MQTT Is Persisted By Backend
    [Documentation]
    ...    Risk: a valid reading is published to the broker but never reaches the database
    ...    (gateway drops it, mis-parses it, or fails to forward it).
    ...    Expected: within 10 seconds the backend holds exactly one telemetry record for the
    ...    device, with a complete schema.
    [Tags]    mqtt    gateway
    ${device_id}=    Register Fresh Device
    Publish Valid Telemetry    ${device_id}
    Wait Until Keyword Succeeds    10s    1s    Telemetry Count Should Be    ${device_id}    1
    ${records}=    Get Telemetry    ${device_id}
    Validate Telemetry Schema    ${records.json()}[0]