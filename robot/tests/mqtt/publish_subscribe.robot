*** Settings ***
Resource    ../../resources/variables.resource
Library    ../../libraries/MqttLibrary.py    ${MQTT_BROKER_HOST}    ${MQTT_BROKER_PORT}
Test Setup    Clear Received Messages
Suite Teardown    Disconnect From Broker

*** Test Cases ***
Message Published On A Topic Is Received On The Same Topic
    [Tags]    mqtt    smoke
    Subscribe To Topic    factory/#
    ${payload}=    Create Dictionary    device_id=sensor-001    temperature=${45.2}    vibration=${2.1}
    Publish Message    factory/line1/sensor-001/telemetry    ${payload}
    ${received}=    Wait For Message    topic_filter=factory/#    timeout=5
    Should Be Equal    ${received}[device_id]    sensor-001
    Should Be Equal As Numbers    ${received}[temperature]    45.2