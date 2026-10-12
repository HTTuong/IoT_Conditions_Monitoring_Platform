*** Settings ***
Documentation
...    Risk: an off-by-one in the threshold comparison (>= instead of >, or the wrong threshold for
...    the wrong metric) raises false alarms that operators learn to ignore, or misses a real fault.
...    Expected: an alert is raised only when a value is strictly above its threshold, and only for
...    the metric that crossed it.
Library    RequestsLibrary
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session
Test Template    Active Alerts For Reading Should Be

*** Test Cases ***    TEMPERATURE    VIBRATION    EXPECTED ALERT TYPES
Both Values Normal Raise No Alert
    ${50.0}    ${2.0}    none
Temperature Exactly At Threshold Raises No Alert
    ${TEMPERATURE_THRESHOLD}    ${2.0}    none
Temperature Just Above Threshold Raises High Temperature
    ${80.1}    ${2.0}    high_temperature
Vibration Exactly At Threshold Raises No Alert
    ${50.0}    ${VIBRATION_THRESHOLD}    none
Vibration Just Above Threshold Raises High Vibration
    ${50.0}    ${8.1}    high_vibration
Both Just Above Thresholds Raise Both Alerts
    ${80.1}    ${8.1}    high_temperature,high_vibration

*** Keywords ***
Active Alerts For Reading Should Be
    [Arguments]    ${temperature}    ${vibration}    ${expected_types}
    ${device_id}=    Register Fresh Device
    ${response}=    Send Telemetry    ${device_id}    temperature=${temperature}    vibration=${vibration}
    Should Be Equal As Integers    ${response.status_code}    201
    ${alerts}=    Get Alerts For Device    ${device_id}    ${False}
    ${actual}=    Evaluate    sorted([a['alert_type'] for a in $alerts])
    ${expected}=    Evaluate    sorted([t for t in '${expected_types}'.split(',') if t != 'none'])
    Should Be Equal    ${actual}    ${expected}