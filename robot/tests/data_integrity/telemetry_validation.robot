*** Settings ***
Library    RequestsLibrary
Library    ../../libraries/DeviceSimulator.py
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session

*** Test Cases ***
Telemetry Without Any Measurement Is Rejected
    [Documentation]
    ...    Risk: a reading containing only a device_id is stored as a row of nulls, polluting
    ...    history and making a silent device look active.
    ...    Expected: 422, and no telemetry record is created.
    [Tags]    data_integrity
    ${device_id}=    Generate Device Id
    Register Device    device_id=${device_id}
    ${body}=    Create Dictionary    device_id=${device_id}
    ${response}=    POST On Session    api    /telemetry    json=${body}    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    422
    ${records}=    Get Telemetry    ${device_id}
    Length Should Be    ${records.json()}    0