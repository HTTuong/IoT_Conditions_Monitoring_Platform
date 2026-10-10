*** Settings ***
Library    Process
Library    OperatingSystem
Library    RequestsLibrary
Resource    variables.resource

*** Keywords ***
Start Backend
    Start Process    ${BACKEND_PYTHON}    -m    uvicorn    app.main:app    --port    8000
    ...    cwd=${PROJECT_ROOT}/services/backend    alias=backend
    ...    stdout=${OUTPUT_DIR}/backend.log    stderr=STDOUT
    Wait Until Keyword Succeeds    30s    1s    Backend Should Be Healthy

Stop Backend
    Terminate Process    backend    kill=${True}

Backend Should Be Healthy
    ${running}=    Is Process Running    backend
    IF    not ${running}
        ${log}=    Get File    ${OUTPUT_DIR}/backend.log
        ${tail}=    Evaluate    "\\n".join($log.splitlines()[-20:])
        Fatal Error    Backend process exited during startup. Last log lines:\n${tail}
    END
    GET On Session    api    /health    expected_status=200

Start Gateway
    Start Process    ${GATEWAY_PYTHON}    -u    src/gateway.py
    ...    cwd=${PROJECT_ROOT}/services/gateway    alias=gateway
    ...    stdout=${OUTPUT_DIR}/gateway.log    stderr=STDOUT
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    Connected to broker

Stop Gateway
    Terminate Process    gateway    kill=${True}

Gateway Log Should Contain
    [Arguments]    ${text}
    ${log}=    Get File    ${OUTPUT_DIR}/gateway.log
    Should Contain    ${log}    ${text}

Stop Broker
    ${result}=    Run Process    docker    compose    stop    mosquitto    cwd=${PROJECT_ROOT}
    Should Be Equal As Integers    ${result.rc}    0    ${result.stderr}

Start Broker
    ${result}=    Run Process    docker    compose    start    mosquitto    cwd=${PROJECT_ROOT}
    Should Be Equal As Integers    ${result.rc}    0    ${result.stderr}

Gateway Connection Count
    ${log}=    Get File    ${OUTPUT_DIR}/gateway.log
    ${count}=    Get Count    ${log}    Connected to broker
    RETURN    ${count}