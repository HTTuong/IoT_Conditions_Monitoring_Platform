*** Settings ***
Library    Collections
Library    RequestsLibrary
Library    ../../libraries/LoadHelper.py
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session

*** Variables ***
${ROUNDS}                 ${5}
${CONCURRENT_REQUESTS}    ${20}

*** Test Cases ***
Simultaneous Anomalies Create Only One Active Alert
    [Documentation]
    ...    Risk: the "is there already an open alert?" check and the insert are two separate steps
    ...    with no database constraint, so simultaneous anomalous readings from one device each
    ...    pass the check and each create an alert, flooding the operator with duplicates.
    ...    Expected: however many readings arrive at the same moment, exactly one alert is open.
    ...    Note: this is a race, so a failure proves the bug but a pass proves nothing by itself.
    ...    Several rounds with fresh devices raise the chance of exposing it.
    [Tags]    anomaly_alert    concurrency
    @{duplicated}=    Create List
    FOR    ${round}    IN RANGE    ${ROUNDS}
        ${device_id}=    Register Fresh Device
        ${body}=    Create Dictionary    device_id=${device_id}    temperature=${95.0}    vibration=${2.0}
        ${statuses}=    Post Concurrently    ${API_BASE_URL}/telemetry    ${body}    ${CONCURRENT_REQUESTS}
        ${failed}=    Evaluate    [s for s in $statuses if s != 201]
        Should Be Empty    ${failed}    Some concurrent requests did not return 201: ${failed}
        Telemetry Count Should Be    ${device_id}    ${CONCURRENT_REQUESTS}
        ${alerts}=    Get Alerts For Device    ${device_id}    ${False}
        ${count}=    Get Length    ${alerts}
        IF    ${count} > 1
            ${entry}=    Set Variable    ${device_id}: ${count} active alerts
            Append To List    ${duplicated}    ${entry}
        END
    END
    Should Be Empty    ${duplicated}    Duplicate active alerts found: ${duplicated}