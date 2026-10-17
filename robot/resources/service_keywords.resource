*** Settings ***
Library    Process
Library    OperatingSystem
Library    RequestsLibrary
Resource    variables.resource

*** Keywords ***
Start Backend
    IF    '${SERVICE_MODE}' == 'docker'
        Try Compose    unpause    backend
        Run Compose    restart    -t    0    backend
    ELSE
        Start Process    ${BACKEND_PYTHON}    -m    uvicorn    app.main:app    --port    8000
        ...    cwd=${PROJECT_ROOT}/services/backend    alias=backend
        ...    stdout=${OUTPUT_DIR}/backend.log    stderr=STDOUT
    END
    Wait Until Keyword Succeeds    30s    1s    Backend Should Be Healthy

Stop Backend
    IF    '${SERVICE_MODE}' == 'docker'
        Run Compose    stop    -t    0    backend
    ELSE
        Terminate Process    backend    kill=${True}
    END

Freeze Backend
    IF    '${SERVICE_MODE}' == 'docker'
        Run Compose    pause    backend
    ELSE
        Send Signal To Process    SIGSTOP    backend
    END

Unfreeze Backend
    IF    '${SERVICE_MODE}' == 'docker'
        Run Compose    unpause    backend
    ELSE
        Send Signal To Process    SIGCONT    backend
    END

Backend Should Be Healthy
    IF    '${SERVICE_MODE}' != 'docker'
        ${running}=    Is Process Running    backend
        IF    not ${running}
            ${log}=    Get File    ${OUTPUT_DIR}/backend.log
            ${tail}=    Evaluate    "\\n".join($log.splitlines()[-20:])
            Fatal Error    Backend process exited during startup. Last log lines:\n${tail}
        END
    END
    GET On Session    api    /health    expected_status=200

Start Gateway
    IF    '${SERVICE_MODE}' == 'docker'
        # A fresh container means a fresh log, like the new log file of the process mode.
        Run Compose    up    -d    --force-recreate    --no-deps    gateway
    ELSE
        Start Process    ${GATEWAY_PYTHON}    -u    src/gateway.py
        ...    cwd=${PROJECT_ROOT}/services/gateway    alias=gateway
        ...    stdout=${OUTPUT_DIR}/gateway.log    stderr=STDOUT
    END
    Wait Until Keyword Succeeds    15s    1s    Gateway Log Should Contain    Connected to broker

Stop Gateway
    IF    '${SERVICE_MODE}' == 'docker'
        Run Compose    stop    -t    0    gateway
    ELSE
        Terminate Process    gateway    kill=${True}
    END

Gateway Should Be Running
    IF    '${SERVICE_MODE}' == 'docker'
        ${result}=    Run Compose    ps    --status    running    --services
        ${services}=    Evaluate    $result.stdout.split()
        Should Contain    ${services}    gateway    Gateway container is not running
    ELSE
        Process Should Be Running    gateway
    END

Read Gateway Log
    IF    '${SERVICE_MODE}' == 'docker'
        ${result}=    Run Compose    logs    --no-color    --no-log-prefix    gateway
        ${log}=    Catenate    SEPARATOR=\n    ${result.stdout}    ${result.stderr}
    ELSE
        ${log}=    Get File    ${OUTPUT_DIR}/gateway.log
    END
    RETURN    ${log}

Gateway Log Should Contain
    [Arguments]    ${text}
    ${log}=    Read Gateway Log
    Should Contain    ${log}    ${text}

Stop Broker
    ${result}=    Run Process    docker    compose    stop    mosquitto    cwd=${PROJECT_ROOT}
    Should Be Equal As Integers    ${result.rc}    0    ${result.stderr}

Start Broker
    ${result}=    Run Process    docker    compose    start    mosquitto    cwd=${PROJECT_ROOT}
    Should Be Equal As Integers    ${result.rc}    0    ${result.stderr}

Gateway Connection Count
    ${log}=    Read Gateway Log
    ${count}=    Get Count    ${log}    Connected to broker
    RETURN    ${count}

Run Compose
    [Arguments]    @{args}
    ${result}=    Run Process    docker    compose    --profile    app    @{args}    cwd=${PROJECT_ROOT}
    Should Be Equal As Integers    ${result.rc}    0    docker compose ${args} failed: ${result.stderr}
    RETURN    ${result}

Try Compose
    [Arguments]    @{args}
    Run Process    docker    compose    --profile    app    @{args}    cwd=${PROJECT_ROOT}