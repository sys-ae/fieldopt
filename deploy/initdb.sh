#!/bin/sh
# Runs once, on a fresh data volume: create the schema, install the application, load the
# demo day. Order matters — tables, then bootstrap, then functions in file order, then seeds.
# (The tables used to be created by SQLAlchemy's create_all; db/schema/schema.sql is the
# pg_dump of that, and is now the only thing that defines them.)
set -e

run() {
	psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$1"
}

# \restrict / \unrestrict are pg_dump meta-commands this psql does not accept
sed '/^\\restrict/d; /^\\unrestrict/d' /opt/fieldopt/schema/schema.sql \
	| psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"

run /opt/fieldopt/postgrest/00_bootstrap.sql
for f in /opt/fieldopt/functions/*.sql; do
	run "$f"
done
run /opt/fieldopt/seeds/01_seed.sql
