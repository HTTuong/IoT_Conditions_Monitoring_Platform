*** Settings ***
Resource    variables.resource
Library    Collections
Library    ../libraries/MqttLibrary.py    ${MQTT_BROKER_HOST}    ${MQTT_BROKER_PORT}

*** Keywords ***
Publish Reading
    [Arguments]    ${device_id}    ${reading}
    Set To Dictionary    ${reading}    device_id=${device_id}
    Publish Message    factory/line1/${device_id}/telemetry    ${reading}