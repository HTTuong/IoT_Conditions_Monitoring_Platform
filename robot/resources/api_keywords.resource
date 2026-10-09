*** Settings ***
Library    RequestsLibrary
Library    ../libraries/DeviceSimulator.py
Resource    variables.resource

*** Keywords ***
Create API Session
    Create Session    api    ${API_BASE_URL}

Register Device
    [Arguments]    ${device_id}    ${name}=${device_id}
    ${body}=    Create Dictionary    device_id=${device_id}    name=${name}
    ${response}=    POST On Session    api    /devices    json=${body}    expected_status=any
    RETURN    ${response}

Register Fresh Device
    ${device_id}=    Generate Device Id
    ${response}=    Register Device    device_id=${device_id}
    Should Be Equal As Integers    ${response.status_code}    201
    RETURN    ${device_id}

Get Device
    [Arguments]    ${device_id}
    ${response}=    GET On Session    api    /devices/${device_id}    expected_status=any
    RETURN    ${response}

Deactivate Device
    [Arguments]    ${device_id}
    ${response}=    PATCH On Session    api    /devices/${device_id}/deactivate    expected_status=any
    RETURN    ${response}

Get Telemetry
    [Arguments]    ${device_id}
    ${response}=    GET On Session    api    /telemetry/${device_id}    expected_status=any
    RETURN    ${response}

Send Telemetry
    [Arguments]    ${device_id}    ${temperature}=${50.0}    ${vibration}=${2.0}
    ${body}=    Create Dictionary    device_id=${device_id}    temperature=${temperature}    vibration=${vibration}
    ${response}=    POST On Session    api    /telemetry    json=${body}    expected_status=any
    RETURN    ${response}

Get Alerts For Device
    [Arguments]    ${device_id}    ${resolved}
    ${params}=    Create Dictionary    resolved=${resolved}
    ${response}=    GET On Session    api    /alerts    params=${params}    expected_status=any
    ${alerts}=    Evaluate    [a for a in $response.json() if a['device_id'] == $device_id]
    RETURN    ${alerts}

Telemetry Count Should Be
    [Arguments]    ${device_id}    ${expected}
    ${response}=    Get Telemetry    ${device_id}
    Length Should Be    ${response.json()}    ${expected}