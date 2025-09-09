import os
import secrets

#
# Required Settings
#

# This is a list of valid fully-qualified domain names (FQDNs) for the Status-Page server.
ALLOWED_HOSTS = os.environ.get('ALLOWED_HOSTS', '*').split(',')

# PostgreSQL database configuration
DATABASE = {
    'NAME': os.environ.get('DATABASE_NAME', 'statuspage'),
    'USER': os.environ.get('DATABASE_USER', ''),
    'PASSWORD': os.environ.get('DATABASE_PASSWORD', ''),
    'HOST': os.environ.get('DATABASE_HOST', 'localhost'),
    'PORT': os.environ.get('DATABASE_PORT', '5432'),
    'CONN_MAX_AGE': 300,
}

# Redis database settings - tasks and caching
REDIS = {
    'tasks': {
        'HOST': os.environ.get('REDIS_HOST', 'localhost'),
        'PORT': int(os.environ.get('REDIS_PORT', 6379)),
        'PASSWORD': os.environ.get('REDIS_PASSWORD', ''),
        'DATABASE': int(os.environ.get('REDIS_DB', 0)),
        'SSL': os.environ.get('REDIS_SSL', 'False').lower() == 'true',
    },
    'caching': {
        'HOST': os.environ.get('REDIS_HOST', 'localhost'),
        'PORT': int(os.environ.get('REDIS_PORT', 6379)),
        'PASSWORD': os.environ.get('REDIS_PASSWORD', ''),
        'DATABASE': int(os.environ.get('REDIS_CACHE_DB', 1)),
        'SSL': os.environ.get('REDIS_SSL', 'False').lower() == 'true',
    }
}

# Define the URL which will be used e.g. in E-Mails
SITE_URL = os.environ.get('SITE_URL', 'https://statuspage.example.com')

# Generate or use provided secret key
SECRET_KEY = os.environ.get('SECRET_KEY')
if not SECRET_KEY:
    # Generate a random secret key if none provided
    SECRET_KEY = secrets.token_urlsafe(50)

#
# Optional Settings
#

# Specify administrators
ADMINS = [
    # ('Admin', 'admin@example.com'),
]

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
        'OPTIONS': {
            'min_length': 8,
        }
    },
]

# Base URL path
BASE_PATH = ''

# CORS settings
CORS_ORIGIN_ALLOW_ALL = False
CORS_ORIGIN_WHITELIST = []
CORS_ORIGIN_REGEX_WHITELIST = []

# Enable debugging based on environment
DEBUG = os.environ.get('DEBUG', 'False').lower() == 'true'

# Email settings
EMAIL = {
    'SERVER': os.environ.get('EMAIL_SERVER', 'localhost'),
    'PORT': int(os.environ.get('EMAIL_PORT', 25)),
    'USERNAME': os.environ.get('EMAIL_USERNAME', ''),
    'PASSWORD': os.environ.get('EMAIL_PASSWORD', ''),
    'USE_SSL': os.environ.get('EMAIL_USE_SSL', 'False').lower() == 'true',
    'USE_TLS': os.environ.get('EMAIL_USE_TLS', 'False').lower() == 'true',
    'TIMEOUT': 10,
    'FROM_EMAIL': os.environ.get('EMAIL_FROM', ''),
}

# Internal IPs
INTERNAL_IPS = ('127.0.0.1', '::1')

# Logging configuration
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {process:d} {thread:d} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'verbose'
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'INFO',
    },
    'loggers': {
        'django': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
    },
}

# Login timeout
LOGIN_TIMEOUT = None

# Media root
MEDIA_ROOT = '/opt/status-page/statuspage/media'

# Field choices override
FIELD_CHOICES = {}

# Plugins
PLUGINS = []

# Plugins configuration
PLUGINS_CONFIG = {}

# RQ settings
RQ_DEFAULT_TIMEOUT = 300

# Cookie names
CSRF_COOKIE_NAME = 'csrftoken'
SESSION_COOKIE_NAME = 'sessionid'

# Time zone
TIME_ZONE = 'UTC'

# Date/time formatting
DATE_FORMAT = 'N j, Y'
SHORT_DATE_FORMAT = 'Y-m-d'
TIME_FORMAT = 'g:i a'
SHORT_TIME_FORMAT = 'H:i:s'
DATETIME_FORMAT = 'N j, Y g:i a'
SHORT_DATETIME_FORMAT = 'Y-m-d H:i'
