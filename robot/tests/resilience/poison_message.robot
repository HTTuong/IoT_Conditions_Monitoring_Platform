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
    ...    Risk: one reading the backend rejects with 4xx (temperature out of range) stays at the
    ...    head of the gateway queue and is retried forever. During a later, short backend outage
    ...    valid readings queue up behind it and are never delivered.
    ...    Expected: the rejected reading is dropped, and the valid reading is stored once the
    ...    backend is back.
    [Tags]    resilience    gateway
    ${device_id}=    Register Fresh Device
    ${poison}=    Create Dictionary    temperature=${999}
    Publish Reading    ${device_id}    ${poison}
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    Backend rejected (422)
    Stop Backend
    ${valid}=    Generate Normal Reading    temperature=${55.5}
    Publish Reading    ${device_id}    ${valid}
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    (device=${device_id} temperature=55.5)
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