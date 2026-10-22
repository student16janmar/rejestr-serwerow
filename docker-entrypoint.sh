#!/bin/sh
# Przed startem tworzy tabele (raz, przed uruchomieniem workerów Gunicorna).
set -e
if [ "${SKIP_INIT_DB:-0}" != "1" ]; then
  flask init-db
fi
exec "$@"
