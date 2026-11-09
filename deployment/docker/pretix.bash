#!/bin/bash
cd /pretix/src
export DJANGO_SETTINGS_MODULE=production_settings
export DATA_DIR=/data/
export HOME=/pretix

AUTOMIGRATE=${AUTOMIGRATE:-yes}
NUM_WORKERS_DEFAULT=$((2 * $(nproc)))
export NUM_WORKERS=${NUM_WORKERS:-$NUM_WORKERS_DEFAULT}

if [ ! -d /data/logs ]; then
    mkdir /data/logs;
fi
if [ ! -d /data/media ]; then
    mkdir /data/media;
fi

# ATmosphere Conference addition: optionally render /etc/pretix/pretix.cfg from
# environment variables, so secrets live in the orchestrator (Dokploy) instead of
# a bind-mounted config file. No-op unless PRETIX_CONFIG_FROM_ENV=yes.
# /etc/pretix is chowned to pretixuser in the Dockerfile for this.
if [ "${PRETIX_CONFIG_FROM_ENV:-}" = "yes" ]; then
    : "${PRETIX_SECRET:?PRETIX_SECRET is required when PRETIX_CONFIG_FROM_ENV=yes}"
    : "${PRETIX_URL:?PRETIX_URL is required when PRETIX_CONFIG_FROM_ENV=yes}"
    : "${PRETIX_DATABASE_PASSWORD:?PRETIX_DATABASE_PASSWORD is required when PRETIX_CONFIG_FROM_ENV=yes}"
    _redis_auth=""
    if [ -n "${PRETIX_REDIS_PASSWORD:-}" ]; then
        _redis_auth=":${PRETIX_REDIS_PASSWORD}@"
    fi
    umask 077
    cat > /etc/pretix/pretix.cfg <<EOF
[pretix]
instance_name=${PRETIX_INSTANCE_NAME:-pretix}
url=${PRETIX_URL}
currency=${PRETIX_CURRENCY:-EUR}
datadir=/data
trust_x_forwarded_for=on
trust_x_forwarded_proto=on
secret=${PRETIX_SECRET}

[database]
backend=postgresql
name=${PRETIX_DATABASE_NAME:-pretix}
user=${PRETIX_DATABASE_USER:-pretix}
password=${PRETIX_DATABASE_PASSWORD}
host=${PRETIX_DATABASE_HOST:-db}
port=${PRETIX_DATABASE_PORT:-5432}

[mail]
from=${PRETIX_MAIL_FROM}
host=${PRETIX_MAIL_HOST}
port=${PRETIX_MAIL_PORT:-465}
ssl=${PRETIX_MAIL_SSL:-on}
user=${PRETIX_MAIL_USER}
password=${PRETIX_MAIL_PASSWORD}

[redis]
location=redis://${_redis_auth}${PRETIX_REDIS_HOST:-redis}/0
sessions=true

[celery]
broker=redis://${_redis_auth}${PRETIX_REDIS_HOST:-redis}/2
backend=redis://${_redis_auth}${PRETIX_REDIS_HOST:-redis}/1
EOF
    unset _redis_auth
fi

if [ "$1" == "cron" ]; then
    exec python3 -m pretix runperiodic
fi

if [ "$AUTOMIGRATE" != "skip" ]; then
  python3 -m pretix migrate --noinput
fi

if [ "$1" == "all" ]; then
    exec sudo -E /usr/bin/supervisord -n -c /etc/supervisord.all.conf
fi

if [ "$1" == "web" ]; then
    exec sudo -E /usr/bin/supervisord -n -c /etc/supervisord.web.conf
fi

if [ "$1" == "webworker" ]; then
    exec gunicorn pretix.wsgi \
        --name pretix \
        --workers $NUM_WORKERS \
        --max-requests 1200 \
        --max-requests-jitter 50 \
        --log-level=info \
        --bind=unix:/tmp/pretix.sock
fi

if [ "$1" == "taskworker" ]; then
    shift
    exec celery -A pretix.celery_app worker -l info "$@"
fi

if [ "$1" == "upgrade" ]; then
    exec python3 -m pretix updateassets
fi

exec python3 -m pretix "$@"
