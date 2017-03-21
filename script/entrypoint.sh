#!/usr/bin/env bash

CMD="airflow"
TRY_LOOP="10"
POSTGRES_HOST="postgres"
POSTGRES_PORT="5432"
RABBITMQ_HOST="rabbitmq"
RABBITMQ_CREDS="airflow:airflow"
FERNET_KEY=$(python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")

# Generate Fernet key
sed -i "s/{FERNET_KEY}/${FERNET_KEY}/" $AIRFLOW_HOME/airflow.cfg

# wait for rabbitmq
if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] || [ "$1" = "flower" ] ; then
  echo "$(date) - waiting for RabbitMQ..."
  RABBIT_RESPONSE=$(curl -so /dev/null --connect-timeout 2 --retry 10 --retry-max-time 20 -w "%{http_code}" -u $RABBITMQ_CREDS http://$RABBITMQ_HOST:15672/api/whoami )
  if [ "$RABBIT_RESPONSE" != "200" ] ; then
      echo "$(date) - $RABBITMQ_HOST not reachable after 20 seconds of trying..."
      exit 1
  else
     echo "$(date) - $RABBITMQ_HOST is up"
  fi
fi

# wait for DB
if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] ; then
  i=0
  while ! nc -z -w 2 $POSTGRES_HOST $POSTGRES_PORT; do
    echo "$(date) - Waiting for postgres"
    i=$(($i + 1))
    if [ $i -ge $TRY_LOOP ]; then
      echo "$(date) - ${POSTGRES_HOST}:${POSTGRES_PORT} still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for ${POSTGRES_HOST}:${POSTGRES_PORT}... $i/$TRY_LOOP"
    sleep 1
  done
  if [ "$1" = "webserver" ]; then
    echo "Initialize database..."
    $CMD initdb
  fi
fi

_term() { 
  echo "$(date) - entrypoint.sh: Recieved TERM/INT, forwarding to airflow"
  RESPAWN=false
  kill -TERM "$child" 
}
_quit() { 
  echo "$(date) - entrypoint.sh: Recieved QUIT, forwarding to airflow"
  RESPAWN=false
  kill -QUIT "$child" 
}


if [ "$1" = "scheduler" ]; then 
  RESPAWN=true
  trap _term SIGTERM
  trap _term SIGINT
  trap _quit SIGQUIT
  while [ "$RESPAWN" = true ] ; do
    echo "$(date) - entrypoint.sh: Booting scheduler with respawn"
    $CMD "$@" &
    child=$!
    wait "$child"
  done
else
  echo "$(date) - entrypoint.sh: Starting $1"
  exec $CMD "$@"
fi
