*** Settings ***
Library    RequestsLibrary
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session

*** Test Cases ***
Repeated Anomalies Create Only One Active Alert
    [Documentation]
    ...    Risk: every anomalous reading creates a new alert, so one overheating machine floods the
    ...    operator with hundreds of identical alerts.
    ...    Expected: while an alert for the same device and type is open, further anomalies add none.
    [Tags]    anomaly_alert
    ${device_id}=    Register Fresh Device
    FOR    ${i}    IN RANGE    3
        Send Reading    ${device_id}    ${95.0}    ${2.0}
    END
    Active Alert Types Should Be    ${device_id}    high_temperature

*** Keywords ***
Send Reading
    [Arguments]    ${device_id}    ${temperature}    ${vibration}
    ${response}=    Send Telemetry    ${device_id}    temperature=${temperature}    vibration=${vibration}
    Should Be Equal As Integers    ${response.status_code}    201

Send Vibration Only
    [Arguments]    ${device_id}    ${vibration}
    ${body}=    Create Dictionary    device_id=${device_id}    vibration=${vibration}
    ${response}=    POST On Session    api    /telemetry    json=${body}    expected_status=any
    Should Be Equal As Integers    ${response.status_code}    201

Active Alert Types Should Be
    [Arguments]    ${device_id}    @{expected}
    ${alerts}=    Get Alerts For Device    ${device_id}    ${False}
    ${actual}=    Evaluate    sorted([a['alert_type'] for a in $alerts])
    ${wanted}=    Evaluate    sorted($expected)
    Should Be Equal    ${actual}    ${wanted}

Resolved Alert Count Should Be
    [Arguments]    ${device_id}    ${expected}
    ${alerts}=    Get Alerts For Device    ${device_id}    ${True}
    Length Should Be    ${alerts}    ${expected}