*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Resource    ../../resources/mqtt_keywords.resource
Resource    ../../resources/service_keywords.resource
Library    Process
Library    ../../libraries/DeviceSimulator.py
Suite Setup    Start Environment
Suite Teardown    Stop Environment

*** Test Cases ***
Gateway Survives A Hung Backend And Delivers After It Recovers
    [Documentation]
    ...    Risk: the backend is alive but not answering (frozen, overloaded). The gateway's HTTP
    ...    request times out, and the unhandled timeout exception kills the gateway process or
    ...    its MQTT thread, so readings are lost while nobody is alerted.
    ...    Expected: the gateway treats the timeout like an outage, buffers the reading, stays
    ...    running, and delivers it once the backend answers again.
    ...    Known to FAIL today: only ConnectionError is caught in gateway.py.
    [Tags]    resilience    gateway    known-bug
    ${device_id}=    Register Fresh Device
    Send Signal To Process    SIGSTOP    backend
    ${reading}=    Generate Normal Reading    temperature=${47.5}
    Publish Reading    ${device_id}    ${reading}
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    Buffered. Queue size: 1
    Process Should Be Running    gateway
    Send Signal To Process    SIGCONT    backend
    Wait Until Keyword Succeeds    30s    2s    Telemetry Count Should Be    ${device_id}    1

*** Keywords ***
Start Environment
    Create API Session
    Start Backend
    Start Gateway

Stop Environment
    Run Keyword And Ignore Error    Send Signal To Process    SIGCONT    backend
    Terminate All Processes    kill=${True}
    Disconnect From Broker