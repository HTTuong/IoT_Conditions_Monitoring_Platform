*** Settings ***
Library    RequestsLibrary
Resource    ../../resources/variables.resource
Suite Setup    Create Session    api    ${API_BASE_URL}

*** Test Cases ***
Backend Health Check Returns OK
    [Tags]    smoke
    ${response}=    GET On Session    api    /health
    Should Be Equal As Integers    ${response.status_code}    200
    Should Be Equal        ${response.json()}[status]    ok  