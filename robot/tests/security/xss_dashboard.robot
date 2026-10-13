*** Settings ***
Documentation
...    Risk: the dashboard writes device data into the page with innerHTML without escaping it.
...    Anyone who can register a device can then run script in an operator's browser.
...    Expected: device data is always shown as plain text; markup is never parsed and no
...    injected script runs.
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Library    Browser    retry_assertions_for=10s
Suite Setup    Start Suite
Suite Teardown    Close Browser
Test Setup    New Context
Test Teardown    Close Context

*** Variables ***
${HEADLESS}       ${True}
${DEVICES_ROW}    css=\#devices-table tbody tr

*** Test Cases ***
Plain Device Name Is Displayed As Entered
    [Documentation]
    ...    Control test: proves the selectors and the registration flow work, so a red result in
    ...    the XSS tests below means a real vulnerability and not a broken test.
    [Tags]    security    xss    control
    ${device_id}=    Register Fresh Device
    New Page    ${DASHBOARD_URL}
    Get Text    ${DEVICES_ROW}:has-text("${device_id}") td:nth-child(2)    ==    ${device_id}

Markup In Device Name Is Displayed As Text, Not Parsed
    [Documentation]
    ...    Risk: a device name containing HTML is parsed by the browser, so the page shows (and can
    ...    be altered by) attacker-controlled markup.
    ...    Expected: the Name cell shows the literal characters that were registered.
    [Tags]    security    xss
    ${device_id}=    Generate Device Id
    ${marker}=    Evaluate    uuid.uuid4().hex[:8]    modules=uuid
    ${name}=    Set Variable    <b>${marker}</b>
    ${response}=    Register Device    device_id=${device_id}    name=${name}
    Should Be Equal As Integers    ${response.status_code}    201
    New Page    ${DASHBOARD_URL}
    Get Text    ${DEVICES_ROW}:has-text("${device_id}") td:nth-child(2)    ==    ${name}

Markup In Device Id Is Displayed As Text, Not Parsed
    [Documentation]
    ...    Risk: the device id is written into both a link and a table cell without escaping, so
    ...    markup in the id breaks out of the link and is parsed as HTML.
    ...    Expected: either the API refuses such an id, or the Device ID cell shows it literally.
    [Tags]    security    xss
    ${marker}=    Evaluate    uuid.uuid4().hex[:8]    modules=uuid
    ${device_id}=    Set Variable    <b>${marker}</b>
    ${response}=    Register Device    device_id=${device_id}    name=Security test
    IF    ${response.status_code} == 422
        Pass Execution    The API rejects markup in device_id, so it can never be rendered.
    END
    Should Be Equal As Integers    ${response.status_code}    201
    New Page    ${DASHBOARD_URL}
    Get Text    ${DEVICES_ROW}:has-text("${marker}") td:nth-child(1)    ==    ${device_id}

Script In Device Name Does Not Execute
    [Documentation]
    ...    Risk: an <img onerror=...> payload in a device name executes JavaScript in the browser of
    ...    every operator who opens the dashboard (stored XSS).
    ...    Expected: the payload never runs. The payload would set the page title to XSS-EXECUTED.
    [Tags]    security    xss
    ${device_id}=    Generate Device Id
    ${payload}=    Set Variable    <img src=x onerror="document.title='XSS-EXECUTED'">
    ${response}=    Register Device    device_id=${device_id}    name=${payload}
    Should Be Equal As Integers    ${response.status_code}    201
    New Page    ${DASHBOARD_URL}
    Wait For Elements State    ${DEVICES_ROW}:has-text("${device_id}")    attached
    Sleep    1s    # a negative check needs a short, bounded wait for the script to have its chance
    Get Title    !=    XSS-EXECUTED

Device Detail Page Shows Device Id From The URL As Text
    [Documentation]
    ...    Control for the second page: it takes the id from the query string and writes it with
    ...    textContent, which is safe.
    ...    Expected: markup in the URL is displayed literally, never parsed.
    [Tags]    security    xss    control
    ${marker}=    Evaluate    uuid.uuid4().hex[:8]    modules=uuid
    New Page    ${DASHBOARD_URL}device-detail.html?device_id=%3Cb%3E${marker}%3C%2Fb%3E
    Get Text    id=device-title    ==    Device: <b>${marker}</b>

*** Keywords ***
Start Suite
    Create API Session
    New Browser    chromium    headless=${HEADLESS}