*** Settings ***
Library    RequestsLibrary
Library    String
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session

*** Test Cases ***
Register Valid Device
    [Tags]    smoke    device
    ${suffix}=    Generate Random String    6    [LOWER][NUMBERS]
    ${device_id}=    Set Variable    sensor-smoke-${suffix}
    ${response}=    Register Device    device_id=${device_id}
    Should Be Equal As Integers    ${response.status_code}    201
    Should Be Equal    ${response.json()}[device_id]    ${device_id}

Register Duplicate Device Returns Conflict
    [Tags]    device
    ${suffix}=    Generate Random String    6    [LOWER][NUMBERS]
    ${device_id}=    Set Variable    sensor-smoke-${suffix}
    Register Device    device_id=${device_id}
    ${response}=    Register Device    device_id=${device_id}
    Should Be Equal As Integers    ${response.status_code}    409