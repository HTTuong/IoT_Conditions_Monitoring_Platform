*** Settings ***
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Library    Collections
Library    ../../libraries/DataIntegrityHelper.py
Suite Setup    Create API Session

*** Test Cases ***
Defect R-DI-05: Whitespace-Only Device Id Is Currently Not Rejected
    [Documentation]
    ...    Risk: "   " (3 spaces) satisfies min_length=3, so an invisible, unusable id reaches the
    ...    database. Observed so far: 500 (cause not yet diagnosed).
    ...    Expected (correct behaviour): 422. Not implemented yet.
    ...    Automation: PINS the defect loosely, because the exact failure is undiagnosed. Passes
    ...    while the status is anything but 422 (201, 409 on a rerun, or 500); fails with
    ...    "looks FIXED" once it is 422.
    [Tags]    data_integrity    validation    R-DI-05
    ${body}=    Create Dictionary    device_id=${SPACE}${SPACE}${SPACE}    name=Blank id
    ${response}=    POST On Session    api    /devices    json=${body}    expected_status=any
    Should Not Be Equal As Integers    ${response.status_code}    422
    ...    R-DI-05 looks FIXED: a whitespace-only id is now rejected with 422. Flip this test to expect 422.

Defect R-DI-05: Whitespace-Only Device Name Is Currently Accepted
    [Documentation]
    ...    Risk: a blank name satisfies min_length=1 and shows as an empty cell on the dashboard.
    ...    Expected (correct behaviour): 422. Not implemented yet.
    ...    Automation: PINS the defect. Passes while the API returns 201; fails with
    ...    "looks FIXED" once it is 422.
    [Tags]    data_integrity    validation    R-DI-05
    ${token}=    Evaluate    uuid.uuid4().hex[:8]    modules=uuid
    ${body}=    Create Dictionary    device_id=blank-${token}    name=${SPACE}${SPACE}
    ${response}=    POST On Session    api    /devices    json=${body}    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    201
    ...    R-DI-05 looks FIXED: a whitespace-only name now returns ${response.status_code}. Flip this test to expect 422.

Defect R-DI-05: Padded Device Id Is Currently Stored Untrimmed
    [Documentation]
    ...    Risk: " dev-1" and "dev-1" become two different devices that look identical to an
    ...    operator, and telemetry for one never matches the other.
    ...    Expected (correct behaviour): 422, or the stored id has no surrounding whitespace.
    ...    Automation: PINS the defect. Passes while the id is stored exactly as sent; fails with
    ...    "looks FIXED" once it is rejected or trimmed.
    [Tags]    data_integrity    validation    R-DI-05
    [Template]    Padded Id Is Stored Untrimmed
    1    0
    0    1
    2    2

Defect R-DI-06: Concurrent Registrations Of One Id Currently Produce 500s
    [Documentation]
    ...    Risk: registration is check-then-insert, so simultaneous requests for one id hit the
    ...    unique constraint and surface as 500 instead of 409.
    ...    Expected (correct behaviour): exactly one 201, the rest 409, never a 5xx.
    ...    Automation: PINS the defect over 5 rounds of 10 simultaneous requests. Always checks the
    ...    safe part (exactly one device created per round, only 201/409/500 returned). Passes
    ...    while at least one 500 appears; fails with "looks FIXED" if none does (fixed, or the
    ...    race did not trigger, so re-run once to tell them apart).
    [Tags]    data_integrity    concurrency    R-DI-06
    ${all_codes}=    Create List
    FOR    ${round}    IN RANGE    5
        ${token}=    Evaluate    uuid.uuid4().hex[:10]    modules=uuid
        ${codes}=    Register Concurrently    ${API_BASE_URL}    race-${token}    10
        ${created}=    Evaluate    $codes.count(201)
        Should Be Equal As Integers    ${created}    1
        ...    Round ${round}: expected exactly one device created, got ${codes}
        ${others}=    Evaluate    [c for c in $codes if c not in (201, 409, 500)]
        Should Be Empty    ${others}    Round ${round}: unexpected status codes ${codes}
        Append To List    ${all_codes}    @{codes}
    END
    ${server_errors}=    Evaluate    len([c for c in $all_codes if c == 500])
    Should Be True    ${server_errors} > 0
    ...    R-DI-06 looks FIXED (or the race did not trigger): no 500 in ${all_codes}. Re-run once; if still none, flip to require only 201/409.

*** Keywords ***
Padded Id Is Stored Untrimmed
    [Arguments]    ${lead}    ${trail}
    ${token}=    Evaluate    uuid.uuid4().hex[:8]    modules=uuid
    ${padded}=    Evaluate    ' ' * ${lead} + 'pad-${token}' + ' ' * ${trail}
    ${body}=    Create Dictionary    device_id=${padded}    name=Padded id
    ${response}=    POST On Session    api    /devices    json=${body}    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    201
    ...    R-DI-05 looks FIXED: a padded id now returns ${response.status_code}. Flip this test to expect 422 or a trimmed id.
    ${stored}=    Evaluate    $response.json()['device_id']
    Should Be Equal    ${stored}    ${padded}
    ...    R-DI-05 looks FIXED: the stored id was trimmed. Flip this test to require trimming.