*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Resource    ../../resources/mqtt_keywords.resource
Resource    ../../resources/service_keywords.resource
Library    Collections
Library    ../../libraries/DeviceSimulator.py
Suite Setup    Start Environment
Suite Teardown    Stop Environment

*** Test Cases ***
Rejected Reading Must Not Block Valid Readings Buffered Behind It
    [Documentation]
    ...    Risk: one reading the backend rejects with 4xx (temperature out of range) is
    ...    buffered at the head of the gateway queue and retried forever. During a later,
    ...    short backend outage valid readings queue up behind it and are never delivered.
    ...    Expected: the poison reading is discarded (or parked) and the valid reading is
    ...    stored once the backend is back.
    ...    Known to FAIL today: the retry loop never skips the head of the queue.
    [Tags]    resilience    gateway    known-bug
    ${device_id}=    Register Fresh Device
    ${poison}=    Create Dictionary    temperature=${999}
    Publish Reading    ${device_id}    ${poison}
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    Backend rejected (422)
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    Buffered. Queue size: 1
    Stop Backend
    ${valid}=    Generate Normal Reading    temperature=${55.5}
    Publish Reading    ${device_id}    ${valid}
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    Buffered. Queue size: 2
    Start Backend
    Wait Until Keyword Succeeds    30s    2s    Telemetry Count Should Be    ${device_id}    1

*** Keywords ***
Start Environment
    Create API Session
    Start Backend
    Start Gateway

Stop Environment
    Terminate All Processes    kill=${True}
    Disconnect From Broker