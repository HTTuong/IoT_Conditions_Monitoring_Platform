*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Library    ../../libraries/DataIntegrityHelper.py
Suite Setup    Create API Session

*** Test Cases ***
Whitespace-Only Device Id Is Rejected
    [Documentation]
    ...    Risk: "   " (3 spaces) satisfies min_length=3, so an invisible, unusable device is registered.
    ...    Expected: 422.
    [Tags]    data_integrity    validation
    ${body}=    Create Dictionary    device_id=${SPACE}${SPACE}${SPACE}    name=Blank id
    ${response}=    POST On Session    api    /devices    json=${body}    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    422

Whitespace-Only Device Name Is Rejected
    [Documentation]
    ...    Risk: a blank name satisfies min_length=1 and shows as an empty cell on the dashboard.
    ...    Expected: 422.
    [Tags]    data_integrity    validation
    ${token}=    Evaluate    uuid.uuid4().hex[:8]    modules=uuid
    ${body}=    Create Dictionary    device_id=blank-${token}    name=${SPACE}${SPACE}
    ${response}=    POST On Session    api    /devices    json=${body}    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    422

*** Keywords ***
Padded Id Is Rejected Or Trimmed
    [Arguments]    ${lead}    ${trail}
    ${token}=    Evaluate    uuid.uuid4().hex[:8]    modules=uuid
    ${padded}=    Evaluate    ' ' * ${lead} + 'pad-${token}' + ' ' * ${trail}
    ${body}=    Create Dictionary    device_id=${padded}    name=Padded id
    ${response}=    POST On Session    api    /devices    json=${body}    expected_status=any
    IF    ${response.status_code} == 422
        Pass Execution    Rejected as expected.
    END
    Should Be Equal As Integers    ${response.status_code}    201
    ${stored}=    Evaluate    $response.json()['device_id']
    Should Be Equal    ${stored}    ${stored.strip()}