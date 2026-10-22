# ---------- etap 1: zależności ----------
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- etap 2: obraz uruchomieniowy ----------
FROM python:3.12-slim

LABEL org.opencontainers.image.title="rejestr-serwerow" \
      org.opencontainers.image.description="Rejestr serwerów i usług IT — projekt Student16"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    FLASK_APP=app

WORKDIR /srv
COPY --from=builder /install /usr/local
COPY app ./app
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# aplikacja nie działa jako root
RUN useradd --system --uid 10001 --no-create-home appuser \
    && chmod +x /usr/local/bin/docker-entrypoint.sh
USER appuser

EXPOSE 8000
HEALTHCHECK --interval=20s --timeout=3s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2).status == 200 else 1)"

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "app:create_app()"]
