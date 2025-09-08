import boto3
import json
import os
from functools import lru_cache


# --- Secrets Manager (סיסמאות בלבד) ---
@lru_cache(maxsize=1)
def get_db_credentials():
    secret_name = os.getenv("SECRET_MANAGER_NAME", "ly-statuspage-db-credentials")
    region_name = os.getenv("AWS_REGION", "us-east-1")

    client = boto3.client("secretsmanager", region_name=region_name)
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response["SecretString"])


db_creds = get_db_credentials()


# --- ConfigMap / Env (פרטי משאב מה-Terraform) ---
DATABASE = {
    'NAME': os.getenv("DATABASE_NAME", "statuspage"),
    'USER': db_creds["username"],
    'PASSWORD': db_creds["password"],
    'HOST': os.getenv("DATABASE_HOST", "localhost"),
    'PORT': os.getenv("DATABASE_PORT", "5432"),
    'CONN_MAX_AGE': 300,
}

# Redis אפשר לעשות דומה:
REDIS = {
    'tasks': {
        'HOST': os.getenv("REDIS_HOST", "localhost"),
        'PORT': int(os.getenv("REDIS_PORT", "6379")),
        'PASSWORD': os.getenv("REDIS_PASSWORD", ""),
        'DATABASE': 0,
        'SSL': False,
    },
    'caching': {
        'HOST': os.getenv("REDIS_HOST", "localhost"),
        'PORT': int(os.getenv("REDIS_PORT", "6379")),
        'PASSWORD': os.getenv("REDIS_PASSWORD", ""),
        'DATABASE': 1,
        'SSL': False,
    }
}

SITE_URL = os.getenv("SITE_URL", "http://localhost")

SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("SECRET_KEY must be set!")

DEBUG = str(os.getenv("DEBUG", "false")).lower() == "true"

