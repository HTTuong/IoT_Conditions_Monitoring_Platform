*** Settings ***
Library    RequestsLibrary
Library    ../../libraries/DeviceSimulator.py
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session

*** Test Cases ***
Register Device Missing Device Id Returns Unprocessable Entity
    [Documentation]
    ...    Risk: a required field (device_id) is missing but the backend accepts it anyway,
    ...    creating an invalid/unidentifiable record.
    ...    Expected: backend returns 422 (Pydantic validation error); no device is created.
    [Tags]    device
    ${body}=    Create Dictionary    name=Missing Id Sensor
    ${response}=    POST On Session    api    /devices    json=${body}    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    422

Deactivating A Device Updates Its Status
    [Documentation]
    ...    Risk: the deactivate endpoint returns a correct response but doesn't actually
    ...    persist the status change in the database.
    ...    Expected: after deactivating, GET-ing the device again must show status=inactive
    ...    not just trusting the PATCH response.
    [Tags]    device
    ${device_id}=    Generate Device Id    
    Register Device    device_id=${device_id}
    Deactivate Device    device_id=${device_id}
    ${response}=    Get Device    device_id=${device_id}
    Should Be Equal    ${response.json()}[status]    inactive

Sending Telemetry For Unregistered Device Returns Not Found
    [Documentation]
    ...    Risk: the backend silently accepts telemetry for a device that was never registered,
    ...    creating orphaned data.
    ...    Expected: 404, and no telemetry record is created.
    [Tags]    device
    ${device_id}=    Generate Device Id
    ${response}=    Send Telemetry    device_id=${device_id}    temperature=${50.0}    vibration=${2.0}
    Should Be Equal As Integers    ${response.status_code}    404

New Device Status Transitions From Offline To Active After First Telemetry
    [Documentation]
    ...    Risk: a newly registered device that has never sent any data shows up as active on
    ...    the dashboard, misleading an operator into thinking it's online.
    ...    Expected: status=offline right after registration; transitions to active immediately
    ...    after the first telemetry reading.
    [Tags]    device
    ${device_id}=    Generate Device Id
    Register Device    device_id=${device_id}
    ${device}=    Get Device    device_id=${device_id}
    Should Be Equal    ${device.json()}[status]    offline
    Send Telemetry    device_id=${device_id}    temperature=${50.0}    vibration=${2.0}
    ${device_after}=    Get Device    device_id=${device_id}
    Should Be Equal    ${device_after.json()}[status]    active