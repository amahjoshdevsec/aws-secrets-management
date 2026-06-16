import os
import boto3
import json
import psycopg2
from functools import lru_cache


@lru_cache(maxsize=1)
def get_db_credentials(secret_name: str = "prod/database/credentials"):
    """
    Retrieve DB credentials from Secrets Manager.
    Cached to avoid hitting the API on every request (reduce latency + cost).
    """
    client = boto3.client("secretsmanager", region_name=os.environ["AWS_REGION"])
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response["SecretString"])


def get_db_connection():
    creds = get_db_credentials()
    return psycopg2.connect(
        host=creds["host"],
        port=creds["port"],
        user=creds["username"],
        password=creds["password"],
        dbname=creds["dbname"]
    )


# Usage
conn = get_db_connection()
# No credentials in code. IAM role grants access. Fully auditable via CloudTrail.
