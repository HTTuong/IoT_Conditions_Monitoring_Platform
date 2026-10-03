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

