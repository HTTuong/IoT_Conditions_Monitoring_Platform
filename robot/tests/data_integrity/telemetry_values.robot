*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session

*** Variables ***
&{JSON_HEADERS}    Content-Type=application/json

*** Test Cases ***
Defect R-DI-01: Out Of Range Battery Is Currently Accepted
    [Documentation]
    ...    Risk: a battery level of 101% or -1% is stored as-is, so dashboards and any future
    ...    low-battery rule work on impossible values.
    ...    Expected (correct behaviour): 422 and no record. Not implemented yet.
    ...    Automation: PINS the defect. Passes while the API accepts and stores the impossible
    ...    value; fails with "looks FIXED" once validation exists, then flip it to expect 422.
    [Tags]    data_integrity    validation    R-DI-01
    [Template]    Impossible Value Is Accepted And Stored
    battery    101
    battery    -1

Defect R-DI-02: Non-Finite Numbers Are Currently Accepted
    [Documentation]
    ...    Risk: NaN and Infinity pass the range checks (every comparison with NaN is False) and
    ...    are committed, so corrupt rows enter history.
    ...    Expected (correct behaviour): 422 and no record. Not implemented yet.
    ...    Automation: PINS the defect. Passes while these values return 201; fails with
    ...    "looks FIXED" once they are rejected, then flip it to expect 422.
    [Tags]    data_integrity    validation    R-DI-02
    [Template]    Non-Finite Value Is Accepted
    temperature    NaN
    vibration      NaN
    battery        NaN
    vibration      Infinity
    battery        Infinity

Defect R-DI-02: Infinite Temperature Currently Crashes With 500
    [Documentation]
    ...    Risk: the range validator does reject temperature=Infinity, but FastAPI echoes the
    ...    input in the 422 body and the JSON encoder cannot encode it, so the client gets 500.
    ...    Expected (correct behaviour): a clean 422. Not implemented yet.
    ...    Automation: PINS the defect. Passes while the status is 500; fails with "looks FIXED"
    ...    once it is 422.
    [Tags]    data_integrity    validation    R-DI-02
    ${device_id}=    Register Fresh Device
    ${response}=    Post Raw Reading    ${device_id}    temperature    Infinity
    Should Be Equal As Integers    ${response.status_code}    500
    ...    R-DI-02 looks FIXED: temperature=Infinity now returns ${response.status_code}. Flip this test to expect 422.

Valid Boundary Values Are Accepted And Stored Unchanged
    [Documentation]
    ...    Risk: tightening validation wrongly rejects legitimate extremes, or the database
    ...    rounds a value so history no longer matches what the device sent.
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

Impossible Value Is Accepted And Stored
    [Arguments]    ${field}    ${value}
    ${device_id}=    Register Fresh Device
    ${response}=    Post Raw Reading    ${device_id}    ${field}    ${value}
    Should Be Equal As Integers    ${response.status_code}    201
    ...    R-DI-01 looks FIXED: ${field}=${value} now returns ${response.status_code}. Flip this test to expect 422.
    ${records}=    Get Telemetry    ${device_id}
    ${stored}=    Evaluate    $records.json()[0]['${field}']
    Should Be Equal As Numbers    ${stored}    ${value}

Non-Finite Value Is Accepted
    [Arguments]    ${field}    ${value}
    ${device_id}=    Register Fresh Device
    ${response}=    Post Raw Reading    ${device_id}    ${field}    ${value}
    Should Be Equal As Integers    ${response.status_code}    201
    ...    R-DI-02 looks FIXED: ${field}=${value} now returns ${response.status_code}. Flip this test to expect 422.

Accepted Value Is Stored Unchanged
    [Arguments]    ${field}    ${value}
    ${device_id}=    Register Fresh Device
    ${response}=    Post Raw Reading    ${device_id}    ${field}    ${value}
    Should Be Equal As Integers    ${response.status_code}    201
    ${records}=    Get Telemetry    ${device_id}
    ${stored}=    Evaluate    $records.json()[0]['${field}']
    Should Be Equal As Numbers    ${stored}    ${value}