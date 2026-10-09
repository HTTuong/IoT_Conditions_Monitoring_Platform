*** Variables ***
${API_BASE_URL}             http://localhost:8000
${MQTT_BROKER_HOST}         localhost
${MQTT_BROKER_PORT}         1883
${TEMPERATURE_THRESHOLD}    ${80.0}
${VIBRATION_THRESHOLD}      ${8.0}
${DASHBOARD_URL}            ${API_BASE_URL}/dashboard/

${PROJECT_ROOT}      ${CURDIR}/../..
${BACKEND_PYTHON}    ${PROJECT_ROOT}/venv/bin/python
${GATEWAY_PYTHON}    ${PROJECT_ROOT}/venv/bin/python