*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session

*** Variables ***
&{JSON_HEADERS}    Content-Type=application/json

*** Test Cases ***
Defect R-DI-03: NaN Reading Currently Closes An Open Alert
    [Documentation]
    ...    Risk: a NaN temperature compares as "not above threshold", so the backend treats it
    ...    as normal and silently resolves a genuine high-temperature alert.
    ...    Expected (correct behaviour): the alert stays open. Not implemented yet.
    ...    Automation: PINS the defect. Passes while the alert is closed by the NaN reading;
    ...    fails with "looks FIXED" once it stays open.
    [Tags]    data_integrity    alerts    R-DI-03
    ${device_id}=    Register Fresh Device
    ${hot}=    Create Dictionary    device_id=${device_id}    temperature=${120.0}
    POST On Session    api    /telemetry    json=${hot}
    ${before}=    Active Alert Types Of Device    ${device_id}
    Should Contain    ${before}    high_temperature    Precondition failed: the alert was never created
    ${raw}=    Set Variable    {"device_id": "${device_id}", "temperature": NaN}
    POST On Session    api    /telemetry    data=${raw}    headers=${JSON_HEADERS}    expected_status=any
    ${after}=    Active Alert Types Of Device    ${device_id}
    Should Not Contain    ${after}    high_temperature
    ...    R-DI-03 looks FIXED: the alert survived the NaN reading. Flip this test to require it stays open.

Reading Without Temperature Does Not Clear An Open Alert
    [Documentation]
    ...    Risk: a reading that simply omits temperature (battery-only) is treated as "temperature
    ...    is fine" and closes the alert. Control for R-DI-03: absence is not normality.
    ...    Expected: the high-temperature alert stays open.
    [Tags]    data_integrity    alerts
    ${device_id}=    Register Fresh Device
    ${hot}=    Create Dictionary    device_id=${device_id}    temperature=${120.0}
    POST On Session    api    /telemetry    json=${hot}
    ${partial}=    Create Dictionary    device_id=${device_id}    battery=${80.0}
    POST On Session    api    /telemetry    json=${partial}
    ${types}=    Active Alert Types Of Device    ${device_id}
    Should Contain    ${types}    high_temperature

Defect R-DI-04: Telemetry Timestamp Currently Has No Timezone Offset
    [Documentation]
    ...    Risk: timestamps serialized without a UTC marker are read as local time by browsers,
    ...    so the dashboard shows readings hours off from reality (3h in Finland).
    ...    Expected (correct behaviour): an explicit offset (Z or +00:00). Not implemented yet.
    ...    Automation: PINS the defect. Passes while the timestamp is naive AND equals UTC now
    ...    (proof it is mislabeled); fails with "looks FIXED" once an offset is present.
    [Tags]    data_integrity    time    R-DI-04
    ${device_id}=    Register Fresh Device
    ${body}=    Create Dictionary    device_id=${device_id}    battery=${80.0}
    POST On Session    api    /telemetry    json=${body}
    ${records}=    Get Telemetry    ${device_id}
    ${ts}=    Evaluate    $records.json()[0]['timestamp']
    ${parsed}=    Evaluate    datetime.datetime.fromisoformat($ts.replace('Z', '+00:00'))    modules=datetime
    ${naive}=    Evaluate    $parsed.tzinfo is None
    Should Be True    ${naive}
    ...    R-DI-04 looks FIXED: timestamp '${ts}' now carries an offset. Flip this test to require one.
    ${skew}=    Evaluate
    ...    abs((datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) - $parsed).total_seconds())
    ...    modules=datetime
    Should Be True    ${skew} < 60
    ...    Timestamp '${ts}' is ${skew}s from UTC now, so the documented defect has changed shape.

Telemetry From A Deactivated Device Does Not Reactivate It
    [Documentation]
    ...    Risk: a reading from a decommissioned device flips it back to active, undoing an
    ...    operator's decision.
    ...    Expected: the device stays inactive (the reading may be rejected or stored).
    [Tags]    data_integrity    device
    ${device_id}=    Register Fresh Device
    PATCH On Session    api    /devices/${device_id}/deactivate
    ${body}=    Create Dictionary    device_id=${device_id}    temperature=${40.0}
    POST On Session    api    /telemetry    json=${body}    expected_status=any
    ${device}=    GET On Session    api    /devices/${device_id}
    Should Be Equal    ${device.json()}[status]    inactive

*** Keywords ***
Active Alert Types Of Device
    [Arguments]    ${device_id}
    ${response}=    GET On Session    api    /alerts    params=resolved=false
    ${types}=    Evaluate    [a['alert_type'] for a in $response.json() if a['device_id'] == $device_id]
    RETURN    ${types}