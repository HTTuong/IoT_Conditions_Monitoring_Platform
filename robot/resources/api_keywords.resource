*** Settings ***
Library    RequestsLibrary
Resource    variables.resource

*** Keywords ***
Create API Session
    Create Session    api    ${API_BASE_URL}

Register Device
    [Arguments]    ${device_id}    ${device_type}=sensor
    ${body}=    Create Dictionary    device_id=${device_id}    device_type=${device_type}
    ${response}=    POST On Session    api    /devices    json=${body}    expected_status=any
    RETURN    ${response}

Get Device
    [Arguments]    ${device_id}
    ${response}=    GET On Session    api    /devices/${device_id}    expected_status=any
    RETURN    ${response}