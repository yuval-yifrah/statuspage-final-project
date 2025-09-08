# Use Python 3.10+ as required
FROM python:3.10-slim

# Install system packages required by Status-Page
RUN apt-get update && apt-get install -y \
    python3-dev \
    build-essential \
    libxml2-dev \
    libxslt1-dev \
    libffi-dev \
    libpq-dev \
    libssl-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Create status-page user
RUN groupadd --system status-page || true && \
    useradd --system --gid status-page --home-dir /opt/status-page status-page

# Create application directory
WORKDIR /opt/status-page

# Copy application code
COPY . .

# Create virtual environment and install dependencies
RUN python3 -m venv venv && \
    . venv/bin/activate && \
    pip install --upgrade pip && \
    pip install -r requirements.txt

# Copy and set up configuration
RUN cp statuspage/statuspage/configuration_example.py statuspage/statuspage/configuration.py

# Generate secret key
RUN cd statuspage && python3 ../generate_secret_key.py > /tmp/secret_key.txt

# Set ownership
RUN chown -R status-page:status-page /opt/status-page

# Switch to status-page user
USER status-page

# Expose port 8000
EXPOSE 8000

# Set working directory for Django
WORKDIR /opt/status-page/statuspage

# Run database migrations and start gunicorn
CMD ["/bin/bash", "-c", "source /opt/status-page/venv/bin/activate && python3 manage.py migrate && python3 manage.py collectstatic --noinput && gunicorn --config /opt/status-page/gunicorn.py statuspage.wsgi"]

