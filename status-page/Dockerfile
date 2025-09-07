# Dockerfile for StatusPage Django Application
FROM python:3.10-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

# Set work directory
WORKDIR /app

# Install system dependencies (minimal required for your requirements.txt)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
        libpq-dev \
        libxml2-dev \
        libxslt1-dev \
        libffi-dev \
        libssl-dev \
        libjpeg-dev \
        libfreetype6-dev \
        liblcms2-dev \
        libwebp-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better Docker layer caching
COPY requirements.txt /app/

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy project files
COPY . /app/

# Create non-root user
RUN addgroup --system statuspage \
    && adduser --system --group statuspage

# Change ownership of the app directory
RUN chown -R statuspage:statuspage /app

# Switch to non-root user
USER statuspage

# Change to the statuspage subdirectory where manage.py is located
WORKDIR /app/statuspage

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8000', timeout=10)" || exit 1

# Command to run the application from the statuspage directory
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "120", "statuspage.wsgi:application"]
