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

Malformed JSON Payload Is Not Stored And Gateway Keeps Working
    [Documentation]
    ...    Risk: a corrupt message (not valid JSON) is stored as garbage or crashes the gateway,
    ...    blocking every message that follows it.
    ...    Expected: the corrupt message is discarded; a valid message sent right after is still
    ...    delivered, so exactly one record exists.
    [Tags]    mqtt    gateway
    Invalid Payload Should Not Be Stored    not-json

Payload Missing Temperature Is Not Stored
    [Documentation]
    ...    Risk: a reading without a required measurement is stored, leaving incomplete data that
    ...    breaks anomaly detection and charts.
    ...    Expected: the incomplete message is discarded; only the valid sentinel is stored.
    [Tags]    mqtt    gateway
    ${payload}=    Create Dictionary    device_id=PLACEHOLDER    vibration=${2.0}
    Invalid Payload Should Not Be Stored    ${payload}

Payload With Non Numeric Temperature Is Not Stored
    [Documentation]
    ...    Risk: a reading with a wrong data type (temperature="hot") is stored or crashes
    ...    anomaly detection when it compares against the threshold.
    ...    Expected: the message is discarded; only the valid sentinel is stored.
    [Tags]    mqtt    gateway
    ${payload}=    Create Dictionary    device_id=PLACEHOLDER    temperature=hot    vibration=${2.0}
    Invalid Payload Should Not Be Stored    ${payload}