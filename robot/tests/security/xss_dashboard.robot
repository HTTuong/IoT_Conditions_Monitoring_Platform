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

*** Keywords ***
Start Suite
    Create API Session
    New Browser    chromium    headless=${HEADLESS}