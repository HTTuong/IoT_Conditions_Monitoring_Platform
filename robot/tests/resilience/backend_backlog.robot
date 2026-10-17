*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Resource    ../../resources/mqtt_keywords.resource
Resource    ../../resources/service_keywords.resource
Library    ../../libraries/DeviceSimulator.py
Suite Setup    Start Environment
Suite Teardown    Stop Environment

*** Variables ***
${BACKLOG_SIZE}    ${50}

*** Test Cases ***
Large Backlog Is Fully Drained In Order After Backend Recovery
    [Documentation]
    ...    Risk: when many readings pile up during a long backend outage, some are lost,
    ...    duplicated or reordered while the backlog drains, or the gateway dies under the load,
    ...    leaving gaps in the history the operator relies on.
    ...    Expected: every reading is stored exactly once, in the order it was sent, and the
    ...    gateway is still alive afterwards. The backlog is split between the gateway buffer and
    ...    the broker queue (the broker only hands out a limited window of unacknowledged
    ...    messages), so the test does not assume where each reading waits.
    [Tags]    resilience    gateway    buffer
    ${device_id}=    Register Fresh Device
    Stop Backend
    FOR    ${i}    IN RANGE    ${BACKLOG_SIZE}
        ${temp}=    Evaluate    20.0 + ${i} * 0.5
        ${reading}=    Generate Normal Reading    temperature=${temp}
        Publish Reading    ${device_id}    ${reading}
    END
    Wait Until Keyword Succeeds    60s    2s    Gateway Log Should Contain    Buffered. Queue size: 10
    Start Backend
    Wait Until Keyword Succeeds    90s    3s    Telemetry Count Should Be    ${device_id}    ${BACKLOG_SIZE}
    ${response}=    Get Telemetry    ${device_id}
    ${in_order}=    Evaluate    [r['temperature'] for r in sorted($response.json(), key=lambda r: r['id'])]
    ${expected}=    Evaluate    [20.0 + i * 0.5 for i in range(${BACKLOG_SIZE})]
    Should Be Equal    ${in_order}    ${expected}
    Gateway Should Be Running

*** Keywords ***
Start Environment
    Create API Session
    Start Backend
    Start Gateway

Stop Environment
    Terminate All Processes    kill=${True}
    Disconnect From Broker