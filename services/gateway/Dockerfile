FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY src ./src

RUN useradd --create-home --uid 10001 appuser
USER appuser

CMD ["python", "-u", "src/gateway.py"]