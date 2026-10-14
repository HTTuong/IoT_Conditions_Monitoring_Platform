*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session

*** Variables ***
&{JSON_HEADERS}    Content-Type=application/json

*** Test Cases ***
Non-Finite Reading Does Not Clear An Open Alert
    [Documentation]
    ...    Risk: a NaN temperature compares as "not above threshold", so the backend treats it
    ...    as normal and silently resolves a genuine high-temperature alert.
    ...    Expected: the alert is still open afterwards (the reading may be rejected or ignored,
    ...    but must never close the alert).
    [Tags]    data_integrity    alerts
    ${device_id}=    Register Fresh Device
    ${hot}=    Create Dictionary    device_id=${device_id}    temperature=${120.0}
    POST On Session    api    /telemetry    json=${hot}
    ${before}=    Active Alert Types Of Device    ${device_id}
    Should Contain    ${before}    high_temperature
    ${raw}=    Set Variable    {"device_id": "${device_id}", "temperature": NaN}
    POST On Session    api    /telemetry    data=${raw}    headers=${JSON_HEADERS}    expected_status=any
    ${after}=    Active Alert Types Of Device    ${device_id}
    Should Contain    ${after}    high_temperature


*** Keywords ***
Active Alert Types Of Device
    [Arguments]    ${device_id}
    ${response}=    GET On Session    api    /alerts    params=resolved=false
    ${types}=    Evaluate    [a['alert_type'] for a in $response.json() if a['device_id'] == $device_id]
    RETURN    ${types}