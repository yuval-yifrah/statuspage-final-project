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

# Create statuspage user (fix the group creation issue)
RUN groupadd --system statuspage && \
    useradd --system --gid statuspage --home-dir /opt/status-page statuspage

# Create application directory
WORKDIR /opt/status-page

# Copy application code
COPY . .

# Install Python dependencies with rq-scheduler fix
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt && \
    pip uninstall -y rq_scheduler || true && \
    pip install --no-cache-dir --upgrade --force-reinstall "rq-scheduler>=0.14.0"

# Test that rq_scheduler works
RUN python -c "import rq, rq_scheduler; from rq_scheduler import Scheduler; print('RQ version:', rq.__version__); print('rq_scheduler OK')"

# Create media directory
RUN mkdir -p statuspage/media

# Set ownership
RUN chown -R statuspage:statuspage /opt/status-page

# Switch to statuspage user
USER statuspage

# Set working directory for Django
WORKDIR /opt/status-page

# Expose port 8000
EXPOSE 8000

# Run database migrations and start server
CMD ["bash", "-c", "cd statuspage && python manage.py migrate && python manage.py collectstatic --noinput && gunicorn --bind 0.0.0.0:8000 statuspage.wsgi:application"]
