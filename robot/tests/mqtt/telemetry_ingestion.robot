*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Library    Collections
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

Partial Reading Without Temperature Is Accepted And Stored As Null
    [Documentation]
    ...    Risk: a sensor that reports only some measurements (e.g. vibration only) has its
    ...    data rejected or corrupted somewhere along the pipeline.
    ...    Expected: the gateway forwards it and the backend stores it, with temperature null
    ...    and the reported vibration preserved.
    [Tags]    mqtt    gateway
    ${device_id}=    Register Fresh Device
    ${payload}=    Create Dictionary    device_id=${device_id}    vibration=${2.0}
    Publish Message    factory/line1/${device_id}/telemetry    ${payload}
    Wait Until Keyword Succeeds    10s    1s    Telemetry Count Should Be    ${device_id}    1
    ${records}=    Get Telemetry    ${device_id}
    Should Be Equal As Numbers    ${records.json()}[0][vibration]    2.0
    Should Be Equal    ${records.json()}[0][temperature]    ${None}

Payload With Non Numeric Temperature Is Not Stored
    [Documentation]
    ...    Risk: a reading with a wrong data type (temperature="hot") is stored or crashes
    ...    anomaly detection when it compares against the threshold.
    ...    Expected: the message is discarded; only the valid sentinel is stored.
    [Tags]    mqtt    gateway
    ${payload}=    Create Dictionary    device_id=PLACEHOLDER    temperature=hot    vibration=${2.0}
    Invalid Payload Should Not Be Stored    ${payload}

*** Keywords ***
Register Fresh Device
    ${device_id}=    Generate Device Id
    ${response}=    Register Device    device_id=${device_id}
    Should Be Equal As Integers    ${response.status_code}    201
    RETURN    ${device_id}

Publish Valid Telemetry
    [Arguments]    ${device_id}
    ${reading}=    Generate Normal Reading
    Set To Dictionary    ${reading}    device_id=${device_id}
    Publish Message    factory/line1/${device_id}/telemetry    ${reading}

Telemetry Count Should Be
    [Arguments]    ${device_id}    ${expected}
    ${response}=    Get Telemetry    ${device_id}
    Length Should Be    ${response.json()}    ${expected}

Publish Sentinel Telemetry
    [Arguments]    ${device_id}
    ${reading}=    Generate Normal Reading    temperature=${55.5}
    Set To Dictionary    ${reading}    device_id=${device_id}
    Publish Message    factory/line1/${device_id}/telemetry    ${reading}

Sentinel Should Be Stored
    [Arguments]    ${device_id}
    ${response}=    Get Telemetry    ${device_id}
    ${temps}=    Evaluate    [r['temperature'] for r in $response.json()]
    Should Contain    ${temps}    ${55.5}

Invalid Payload Should Not Be Stored
    [Arguments]    ${bad_payload}
    ${device_id}=    Register Fresh Device
    ${is_dict}=    Evaluate    isinstance($bad_payload, dict)
    IF    ${is_dict}
        Set To Dictionary    ${bad_payload}    device_id=${device_id}
    END
    Publish Message    factory/line1/${device_id}/telemetry    ${bad_payload}
    Publish Sentinel Telemetry    ${device_id}
    Wait Until Keyword Succeeds    10s    1s    Sentinel Should Be Stored    ${device_id}
    Telemetry Count Should Be    ${device_id}    1

Out Of Range Temperature Is Not Stored
    [Documentation]
    ...    Risk: a faulty sensor reporting an impossible temperature (500 C) is stored and
    ...    triggers false alerts or distorts charts.
    ...    Expected: the reading is rejected by the backend validation and not stored.
    [Tags]    mqtt    gateway
    ${payload}=    Create Dictionary    device_id=PLACEHOLDER    temperature=${500.0}    vibration=${2.0}
    Invalid Payload Should Not Be Stored    ${payload}

Negative Vibration Is Not Stored
    [Documentation]
    ...    Risk: a physically impossible negative vibration value is stored as valid data.
    ...    Expected: the reading is rejected and not stored.
    [Tags]    mqtt    gateway
    ${payload}=    Create Dictionary    device_id=PLACEHOLDER    temperature=${50.0}    vibration=${-1.0}
    Invalid Payload Should Not Be Stored    ${payload}

Unknown Connectivity Value Is Not Stored
    [Documentation]
    ...    Risk: a value outside the allowed set (good/weak/poor) is stored, breaking any
    ...    dashboard logic that groups or colors devices by connectivity.
    ...    Expected: the reading is rejected and not stored.
    [Tags]    mqtt    gateway
    ${payload}=    Create Dictionary    device_id=PLACEHOLDER    temperature=${50.0}    connectivity=excellent
    Invalid Payload Should Not Be Stored    ${payload}