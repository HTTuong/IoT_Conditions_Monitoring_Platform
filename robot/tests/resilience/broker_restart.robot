*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Resource    ../../resources/mqtt_keywords.resource
Resource    ../../resources/service_keywords.resource
Library    ../../libraries/DeviceSimulator.py
Suite Setup    Start Environment
Suite Teardown    Stop Environment

*** Test Cases ***
Gateway Reconnects And Resumes Forwarding After Broker Restart
    [Documentation]
    ...    Risk: after the MQTT broker restarts, the gateway stays disconnected (or subscribed
    ...    to nothing), so every later reading is silently lost until someone restarts it.
    ...    Expected: the gateway reconnects on its own and forwards a reading published
    ...    after the restart, stored exactly once.
    [Tags]    resilience    gateway    broker
    ${device_id}=    Register Fresh Device
    ${connects_before}=    Gateway Connection Count
    Stop Broker
    Start Broker
    Wait Until Keyword Succeeds    30s    1s    Gateway Connection Count Should Exceed    ${connects_before}
    ${reading}=    Generate Normal Reading    temperature=${46.5}
    Wait Until Keyword Succeeds    30s    2s    Publish Reading    ${device_id}    ${reading}
    Wait Until Keyword Succeeds    30s    1s    Telemetry Count Should Be    ${device_id}    1

*** Keywords ***
Start Environment
    Create API Session
    Start Backend
    Start Gateway

Stop Environment
    Run Keyword And Ignore Error    Start Broker
    Terminate All Processes    kill=${True}
    Disconnect From Broker

Gateway Connection Count Should Exceed
    [Arguments]    ${previous}
    ${count}=    Gateway Connection Count
    Should Be True    ${count} > ${previous}