# ==========================================
# STAGE 1: BUILDER
# ==========================================
FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.lock .

RUN python -m pip install --no-cache-dir --require-hashes --only-binary=:all: --prefix=/install -r requirements.lock

# ==========================================
# STAGE 2: RUNTIME
# ==========================================
FROM python:3.12-slim AS runtime

# Apply operating system security updates
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY --from=builder /install /usr/local

# Create non-root application user
RUN groupadd --system appgroup && useradd --system --gid appgroup --create-home appuser

# Copy application as root and make it read-only
COPY main.py .
RUN chmod 0444 main.py

USER appuser

EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)" || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
