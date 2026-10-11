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
Gateway Survives A Hung Backend And Resumes Consuming After It Recovers
    [Documentation]
    ...    Risk: the backend is alive but not answering (frozen, overloaded). The gateway's HTTP
    ...    request times out, and the unhandled timeout exception kills the gateway's MQTT thread,
    ...    so it silently stops consuming while the process still looks healthy.
    ...    Expected: the gateway treats the timeout like an outage, buffers the reading and stays
    ...    running. Once the backend answers, the reading is stored (at least once: a timed-out
    ...    request may still have been processed by the backend, so a duplicate is acceptable)
    ...    and the gateway keeps consuming new messages.
    [Tags]    resilience    gateway
    ${device_id}=    Register Fresh Device
    Send Signal To Process    SIGSTOP    backend
    ${reading}=    Generate Normal Reading    temperature=${47.5}
    Publish Reading    ${device_id}    ${reading}
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    Buffered. Queue size: 1
    Process Should Be Running    gateway
    Send Signal To Process    SIGCONT    backend
    Wait Until Keyword Succeeds    30s    2s    Telemetry Count Should Be At Least    ${device_id}    1
    ${sentinel}=    Generate Normal Reading    temperature=${55.5}
    Publish Reading    ${device_id}    ${sentinel}
    Wait Until Keyword Succeeds    30s    2s    Telemetry Should Contain Temperature    ${device_id}    ${55.5}

*** Keywords ***
Start Environment
    Create API Session
    Start Backend
    Start Gateway

Stop Environment
    Run Keyword And Ignore Error    Send Signal To Process    SIGCONT    backend
    Terminate All Processes    kill=${True}
    Disconnect From Broker

Telemetry Count Should Be At Least
    [Arguments]    ${device_id}    ${minimum}
    ${response}=    Get Telemetry    ${device_id}
    ${count}=    Get Length    ${response.json()}
    Should Be True    ${count} >= ${minimum}

Telemetry Should Contain Temperature
    [Arguments]    ${device_id}    ${temperature}
    ${response}=    Get Telemetry    ${device_id}
    ${temps}=    Evaluate    [r['temperature'] for r in $response.json()]
    Should Contain    ${temps}    ${temperature}   1