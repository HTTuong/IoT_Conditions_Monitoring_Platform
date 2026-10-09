*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Resource    ../../resources/mqtt_keywords.resource
Resource    ../../resources/service_keywords.resource
Library    ../../libraries/DeviceSimulator.py
Suite Setup    Start Environment
Suite Teardown    Stop Environment

*** Test Cases ***
Readings Published During Backend Outage Are Delivered In Order After Recovery
    [Documentation]
    ...    Risk: telemetry published while the backend is down is silently lost, or arrives
    ...    out of order after recovery, leaving gaps and a wrong history for the operator.
    ...    Expected: the gateway buffers the readings; once the backend is back, all 5 are
    ...    stored exactly once, in the order they were sent.
    [Tags]    resilience    gateway
    ${device_id}=    Register Fresh Device
    Stop Backend
    FOR    ${i}    IN RANGE    5
        ${temp}=    Evaluate    40.0 + ${i}
        ${reading}=    Generate Normal Reading    temperature=${temp}
        Publish Reading    ${device_id}    ${reading}
    END
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    Buffered. Queue size: 5
    Start Backend
    Wait Until Keyword Succeeds    60s    2s    Telemetry Count Should Be    ${device_id}    5
    ${response}=    Get Telemetry    ${device_id}
    ${in_order}=    Evaluate    [r['temperature'] for r in sorted($response.json(), key=lambda r: r['id'])]
    ${expected}=    Evaluate    [40.0 + i for i in range(5)]
    Should Be Equal    ${in_order}    ${expected}

*** Keywords ***
Start Environment
    Create API Session
    Start Backend
    Start Gateway

Stop Environment
    Terminate All Processes    kill=${True}
    Disconnect From Broker