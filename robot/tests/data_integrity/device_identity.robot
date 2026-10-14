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

Padded Device Id Is Rejected Or Trimmed
    [Documentation]
    ...    Risk: " dev-1" and "dev-1" become two different devices that look identical to an
    ...    operator, and telemetry for one never matches the other.
    ...    Expected: either 422, or the stored id has no surrounding whitespace.
    [Tags]    data_integrity    validation
    [Template]    Padded Id Is Rejected Or Trimmed
    1    0
    0    1
    2    2

Concurrent Registrations Of The Same Id Yield Exactly One Device
    [Documentation]
    ...    Risk: registration is check-then-insert, so simultaneous requests for one id can hit the
    ...    unique constraint and surface as 500 instead of 409.
    ...    Expected: across 5 rounds of 10 simultaneous requests, exactly one 201 per round, the rest
    ...    409, and never a 5xx.
    [Tags]    data_integrity    concurrency
    FOR    ${round}    IN RANGE    5
        ${token}=    Evaluate    uuid.uuid4().hex[:10]    modules=uuid
        ${codes}=    Register Concurrently    ${API_BASE_URL}    race-${token}    10
        ${created}=    Evaluate    $codes.count(201)
        ${unexpected}=    Evaluate    [c for c in $codes if c not in (201, 409)]
        Should Be Empty    ${unexpected}    Round ${round}: unexpected status codes ${codes}
        Should Be Equal As Integers    ${created}    1    Round ${round}: ${codes}
    END

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