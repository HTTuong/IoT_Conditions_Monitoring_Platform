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

Reading Without Temperature Does Not Clear An Open Alert
    [Documentation]
    ...    Risk: a reading that simply omits temperature (battery-only) is treated as "temperature
    ...    is fine" and closes the alert. Control for the NaN test: absence is not normality.
    ...    Expected: the high-temperature alert stays open.
    [Tags]    data_integrity    alerts
    ${device_id}=    Register Fresh Device
    ${hot}=    Create Dictionary    device_id=${device_id}    temperature=${120.0}
    POST On Session    api    /telemetry    json=${hot}
    ${partial}=    Create Dictionary    device_id=${device_id}    battery=${80.0}
    POST On Session    api    /telemetry    json=${partial}
    ${types}=    Active Alert Types Of Device    ${device_id}
    Should Contain    ${types}    high_temperature

Telemetry Timestamp Carries A Timezone And Is Current
    [Documentation]
    ...    Risk: timestamps serialized without a UTC marker are read as local time by browsers,
    ...    so the dashboard shows readings hours off from reality (3h in Finland).
    ...    Expected: the timestamp has an explicit offset and is within 60 s of now (UTC).
    [Tags]    data_integrity    time
    ${device_id}=    Register Fresh Device
    ${body}=    Create Dictionary    device_id=${device_id}    battery=${80.0}
    POST On Session    api    /telemetry    json=${body}
    ${records}=    Get Telemetry    ${device_id}
    ${ts}=    Evaluate    $records.json()[0]['timestamp']
    ${parsed}=    Evaluate    datetime.datetime.fromisoformat($ts.replace('Z', '+00:00'))    modules=datetime
    ${aware}=    Evaluate    $parsed.tzinfo is not None
    Should Be True    ${aware}    Timestamp '${ts}' has no timezone offset
    ${skew}=    Evaluate    abs((datetime.datetime.now(datetime.timezone.utc) - $parsed).total_seconds())    modules=datetime
    Should Be True    ${skew} < 60    Timestamp '${ts}' is ${skew}s away from now


*** Keywords ***
Active Alert Types Of Device
    [Arguments]    ${device_id}
    ${response}=    GET On Session    api    /alerts    params=resolved=false
    ${types}=    Evaluate    [a['alert_type'] for a in $response.json() if a['device_id'] == $device_id]
    RETURN    ${types}