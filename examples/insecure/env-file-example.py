# examples/insecure/env-file-example.py
# ANTI-PATTERN: .env files shared over Slack, checked into repos

import os

DB_PASS    = os.environ.get("DB_PASSWORD")  # Often from a .env file in the repo
STRIPE_KEY = os.environ.get("STRIPE_KEY")   # Visible in process listings (ps aux)

# Problems:
# - .env files are frequently committed by accident (missing/incorrect .gitignore)
# - Shared informally via Slack/email/Notion with no access control or expiry
# - Every process and child process can read the full environment, so secrets
#   are visible in `ps aux`, crash dumps, and error/log output
# - No rotation, no audit trail of who has a copy of the file
# - Same credentials are often reused across dev, staging, and prod
