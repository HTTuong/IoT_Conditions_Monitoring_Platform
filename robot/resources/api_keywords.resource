*** Settings ***
Library    RequestsLibrary
Resource    variables.resource

*** Keywords ***
Create API Session
    Create Session    api    ${API_BASE_URL}

Register Device
    [Arguments]    ${device_id}    ${name}=${device_id}
    ${body}=    Create Dictionary    device_id=${device_id}    name=${name}
    ${response}=    POST On Session    api    /devices    json=${body}    expected_status=any
    RETURN    ${response}

Get Device
    [Arguments]    ${device_id}
    ${response}=    GET On Session    api    /devices/${device_id}    expected_status=any
    RETURN    ${response}

Deactivate Device
    [Arguments]    ${device_id}
    ${response}=    PATCH On Session    api    /devices/${device_id}/deactivate    expected_status=any
    RETURN    ${response}

Send Telemetry
    [Arguments]    ${device_id}    ${temperature}=${50.0}    ${vibration}=${2.0}
    ${body}=    Create Dictionary    device_id=${device_id}    temperature=${temperature}    vibration=${vibration}
    ${response}=    POST On Session    api    /telemetry    json=${body}    expected_status=any
    RETURN    ${response}