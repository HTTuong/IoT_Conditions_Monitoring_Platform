*** Settings ***
Library    RequestsLibrary
Library    ../../libraries/DeviceSimulator.py
Library    ../../libraries/TelemetryValidator.py
Resource    ../../resources/variables.resource
Resource    ../../resources/api_keywords.resource
Suite Setup    Create API Session

*** Test Cases ***
Temperature Above Threshold Triggers High Temperature Alert
    [Documentation]
    ...    Risk: anomaly logic silently does not add flag or alert for thresholds or flag it with wrong alert.
    ...    Expected: An alert alert_type=high_temperature is created, matches correctly to the trigger telemetry
    [Tags]    anomaly_alert
    ${device_id}=    Generate Device Id
    Register Device    device_id=${device_id}
    ${reading}=    Generate Anomaly Reading
    ...    temperature_threshold=${TEMPERATURE_THRESHOLD}    vibration_threshold=${VIBRATION_THRESHOLD}
    ...    anomaly_type=temperature
    ${response}=    Send Telemetry    device_id=${device_id}    temperature=${reading}[temperature]    vibration=${reading}[vibration]
    Should Be Equal As Integers    ${response.status_code}    201
    Validate Telemetry Schema    ${response.json()}
    ${alerts}=    GET On Session    api    /alerts    expected_status=any
    ${device_alerts}=    Evaluate    [a for a in $alerts.json() if a['device_id'] == '${device_id}']
    Length Should Be    ${device_alerts}    1
    ${is_valid}=    Alert Matches Telemetry    ${device_alerts}[0]    ${reading}
    ...    temperature_threshold=${TEMPERATURE_THRESHOLD}    vibration_threshold=${VIBRATION_THRESHOLD}
    Should Be True    ${is_valid}