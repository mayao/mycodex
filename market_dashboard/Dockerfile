FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY . /app

RUN mkdir -p /app/uploads /app/cache /app/output \
    && useradd --create-home --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 8008

CMD ["python", "app.py", "--host", "0.0.0.0", "--port", "8008"]
