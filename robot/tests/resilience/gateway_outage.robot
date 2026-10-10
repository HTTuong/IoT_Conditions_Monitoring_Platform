*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Resource    ../../resources/mqtt_keywords.resource
Resource    ../../resources/service_keywords.resource
Library    ../../libraries/DeviceSimulator.py
Suite Setup    Start Environment
Suite Teardown    Stop Environment

*** Test Cases ***
Readings Published While Gateway Is Offline Are Delivered After It Restarts
    [Documentation]
    ...    Risk: readings published while the gateway process is down are lost because the
    ...    broker discards messages nobody is listening for.
    ...    Expected: the broker keeps them for the gateway's persistent session (QoS 1);
    ...    after the gateway restarts all 3 are stored exactly once, in order.
    [Tags]    resilience    gateway
    ${device_id}=    Register Fresh Device
    Stop Gateway
    FOR    ${i}    IN RANGE    3
        ${temp}=    Evaluate    40.0 + ${i}
        ${reading}=    Generate Normal Reading    temperature=${temp}
        Publish Reading    ${device_id}    ${reading}
    END
    Start Gateway
    ${sentinel}=    Generate Normal Reading    temperature=${55.5}
    Publish Reading    ${device_id}    ${sentinel}
    Wait Until Keyword Succeeds    30s    1s    Telemetry Count Should Be    ${device_id}    4
    ${response}=    Get Telemetry    ${device_id}
    ${in_order}=    Evaluate    [r['temperature'] for r in sorted($response.json(), key=lambda r: r['id'])]
    Should Be Equal    ${in_order}    ${{[40.0, 41.0, 42.0, 55.5]}}

Gateway Crash With Buffered Readings Must Not Lose Them
    [Documentation]
    ...    Risk: the gateway buffers readings in memory while the backend is down. If the
    ...    gateway then crashes, those readings are gone for good, because the broker already
    ...    received the MQTT acknowledgement when the gateway first accepted them.
    ...    Expected: after the backend and the gateway are both back, all 3 readings are stored.
    ...    Known to FAIL today: the buffer lives only in memory (see docs/risk-analysis.md).
    [Tags]    resilience    gateway    known-bug
    ${device_id}=    Register Fresh Device
    Stop Backend
    FOR    ${i}    IN RANGE    3
        ${temp}=    Evaluate    60.0 + ${i}
        ${reading}=    Generate Normal Reading    temperature=${temp}
        Publish Reading    ${device_id}    ${reading}
    END
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    Buffered. Queue size: 3
    Stop Gateway
    Start Backend
    Start Gateway
    Wait Until Keyword Succeeds    30s    2s    Telemetry Count Should Be    ${device_id}    3

*** Keywords ***
Start Environment
    Create API Session
    Start Backend
    Start Gateway

Stop Environment
    Terminate All Processes    kill=${True}
    Disconnect From Broker