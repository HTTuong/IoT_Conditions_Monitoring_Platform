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

Normal Reading After A Spike Resolves The Alert
    [Documentation]
    ...    Risk: an alert is never closed after the machine recovers, so the dashboard shows a fault
    ...    that no longer exists.
    ...    Expected: the first normal reading closes the alert; it moves from active to resolved.
    [Tags]    anomaly_alert
    ${device_id}=    Register Fresh Device
    Send Reading    ${device_id}    ${95.0}    ${2.0}
    Active Alert Types Should Be    ${device_id}    high_temperature
    Send Reading    ${device_id}    ${50.0}    ${2.0}
    Active Alert Types Should Be    ${device_id}
    Resolved Alert Count Should Be    ${device_id}    1

Anomaly After Recovery Creates A New Alert
    [Documentation]
    ...    Risk: once an alert has been resolved, the same fault returning is silently ignored
    ...    (the old resolved alert is mistaken for an open one).
    ...    Expected: a new, separate alert is created; the earlier one stays resolved.
    [Tags]    anomaly_alert
    ${device_id}=    Register Fresh Device
    Send Reading    ${device_id}    ${95.0}    ${2.0}
    Send Reading    ${device_id}    ${50.0}    ${2.0}
    Send Reading    ${device_id}    ${96.0}    ${2.0}
    ${active}=    Get Alerts For Device    ${device_id}    ${False}
    ${resolved}=    Get Alerts For Device    ${device_id}    ${True}
    Length Should Be    ${active}    1
    Length Should Be    ${resolved}    1
    Should Not Be Equal As Integers    ${active}[0][id]    ${resolved}[0][id]

Temperature And Vibration Alerts Are Independent
    [Documentation]
    ...    Risk: resolving one metric closes (or hides) the alert of another metric, so a still-failing
    ...    sensor looks healthy.
    ...    Expected: each alert type opens and closes on its own.
    [Tags]    anomaly_alert
    ${device_id}=    Register Fresh Device
    Send Reading    ${device_id}    ${95.0}    ${9.0}
    Active Alert Types Should Be    ${device_id}    high_temperature    high_vibration
    Send Reading    ${device_id}    ${50.0}    ${9.0}
    Active Alert Types Should Be    ${device_id}    high_vibration

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