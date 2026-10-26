#!/usr/bin/env bash
# Menyiapkan database RADIUS di container docker-postgres. Aman dijalankan berulang.
# Membuat user + database "radius" lalu memuat skema bawaan FreeRADIUS.
set -euo pipefail

PG="docker-postgres"
IMG="freeradius/freeradius-server:latest-3.2"
PASS="${RADIUS_DB_PASSWORD:-r3tRadius}"   # harus sama dengan RADIUS_DB_PASSWORD di radius.yml

docker exec "$PG" psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='radius'" | grep -q 1 \
  || docker exec "$PG" psql -U postgres -c "CREATE USER radius WITH PASSWORD '$PASS';"

docker exec "$PG" psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='radius'" | grep -q 1 \
  || docker exec "$PG" psql -U postgres -c "CREATE DATABASE radius OWNER radius;"

# Skema hanya dimuat jika tabel belum ada (memuat ulang menghasilkan error "index already exists").
if [ "$(docker exec "$PG" psql -U radius -d radius -tAc "SELECT to_regclass('public.radcheck') IS NOT NULL")" = "t" ]; then
  echo "Skema sudah ada, dilewati."
else
  docker run --rm --entrypoint cat "$IMG" /etc/freeradius/mods-config/sql/main/postgresql/schema.sql \
    | docker exec -i "$PG" psql -q -U radius -d radius
fi

echo "Selesai. Tabel RADIUS:"
docker exec "$PG" psql -U radius -d radius -c "\dt"
