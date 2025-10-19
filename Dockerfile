# Use a specific version of Python slim image for better reproducibility
FROM python:3.11-slim as builder

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100 \
    # Set default values that can be overridden at runtime
    MINIO_ENDPOINT=minio:9000 \
    MINIO_ACCESS_KEY=minioadmin \
    MINIO_SECRET_KEY=minioadmin

# Install system dependencies required for building
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements first to leverage Docker cache
COPY resources/requirements.txt .

# Install Python dependencies
RUN pip install --user -r requirements.txt

# Final stage
FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH="/home/appuser/.local/bin:$PATH"

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user and switch to it
RUN addgroup --system appgroup && \
    adduser --system --no-create-home --disabled-login --disabled-password --ingroup appgroup appuser && \
    mkdir -p /app && \
    chown -R appuser:appgroup /app

# Set working directory
WORKDIR /app

# Copy only necessary files from builder
COPY --from=builder /root/.local /home/appuser/.local
COPY --chown=appuser:appgroup resources/ .

# Install application dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Ensure sensitive environment variables are not hardcoded
RUN echo "MINIO_ACCESS_KEY and MINIO_SECRET_KEY should be provided at runtime" \
    && echo "using environment variables or AWS Secrets Manager"

# Set non-sensitive environment variables
ENV MINIO_ENDPOINT=minio:9000 \
    BUCKET_NAME=analytics-data \
    GUNICORN_CMD_ARGS="--bind=0.0.0.0:5000 --workers=4 --threads=2 --worker-class=gthread --log-level=info --timeout=120 --worker-tmp-dir /dev/shm"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:5000/health || exit 1

# Change to non-root user
USER appuser

# Expose the port the app runs on
EXPOSE 5000

# Command to run the application
CMD ["gunicorn", "flask_app:app"]
