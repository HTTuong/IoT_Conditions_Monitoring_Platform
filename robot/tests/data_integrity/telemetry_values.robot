*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session

*** Variables ***
&{JSON_HEADERS}    Content-Type=application/json

*** Test Cases ***
Out Of Range Battery Is Rejected
    [Documentation]
    ...    Risk: a battery level of 101% or -1% is stored as-is, so dashboards and any future
    ...    low-battery rule work on impossible values.
    ...    Expected: 422, and no telemetry record is created.
    [Tags]    data_integrity    validation
    [Template]    Reading With Field Is Rejected
    battery    101
    battery    -1

Non-Finite Numbers Are Rejected
    [Documentation]
    ...    Risk: NaN and Infinity pass the range checks (every comparison with NaN is False),
    ...    get committed, and then make the response serializer fail, so the device's history
    ...    endpoint returns 500 forever.
    ...    Expected: 422, and no telemetry record is created.
    [Tags]    data_integrity    validation
    [Template]    Reading With Field Is Rejected
    temperature    NaN
    vibration      NaN
    battery        NaN
    temperature    Infinity
    vibration      Infinity
    battery        Infinity

Valid Boundary Values Are Accepted And Stored Unchanged
    [Documentation]
    ...    Risk: tightening validation (previous tests) wrongly rejects legitimate extremes,
    ...    or the database rounds a value so history no longer matches what the device sent.
    ...    Expected: 201, and the stored value equals the sent value.
    [Tags]    data_integrity    validation
    [Template]    Accepted Value Is Stored Unchanged
    temperature    -50
    temperature    200
    temperature    36.6
    vibration      0
    battery        0
    battery        100
    battery        33.3


*** Keywords ***
Post Raw Reading
    [Arguments]    ${device_id}    ${field}    ${value}
    ${raw}=    Set Variable    {"device_id": "${device_id}", "${field}": ${value}}
    ${response}=    POST On Session    api    /telemetry    data=${raw}
    ...    headers=${JSON_HEADERS}    expected_status=any
    RETURN    ${response}

Reading With Field Is Rejected
    [Arguments]    ${field}    ${value}
    ${device_id}=    Register Fresh Device
    ${response}=    Post Raw Reading    ${device_id}    ${field}    ${value}
    Should Be Equal As Integers    ${response.status_code}    422
    ...    ${field}=${value} should be rejected but got ${response.status_code}
    ${records}=    Get Telemetry    ${device_id}
    Length Should Be    ${records.json()}    0

Accepted Value Is Stored Unchanged
    [Arguments]    ${field}    ${value}
    ${device_id}=    Register Fresh Device
    ${response}=    Post Raw Reading    ${device_id}    ${field}    ${value}
    Should Be Equal As Integers    ${response.status_code}    201
    ${records}=    Get Telemetry    ${device_id}
    ${stored}=    Evaluate    $records.json()[0]['${field}']
    Should Be Equal As Numbers    ${stored}    ${value}