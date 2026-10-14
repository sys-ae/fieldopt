# FieldOpt — Docker shortcuts.
#
# First run:
#   make up        — start postgres (with pg_cron) + postgrest + nginx
#   make pg-apply  — install the SQL (schema helpers, RPC functions)
#   make pg-seed   — load the demo day (dates land on today)
#   Browse http://localhost:8081
#
# Other commands:
#   make demo      — enable the sim UI (app.is_demo flag), then press Start Demo
#   make no-demo   — disable it again
#   make pg-sync   — push web/ static assets into nginx without an image rebuild
#   make down      — stop containers (DB volume kept)
#   make clean     — stop + wipe DB volume
#   make logs      — tail nginx + postgrest
#   make ps        — list running containers

COMPOSE := docker compose -p fieldopt
PSQL := docker exec -i fieldopt-postgres psql -U fieldopt -d fieldopt

.PHONY: up demo no-demo down clean logs ps rebuild pg-apply pg-seed pg-sync

up:
	$(COMPOSE) up -d --build --remove-orphans

# Apply the pg-native artifacts (bootstrap, then functions in file order) and reload PostgREST.
# File order matters: 24_engine.sql supersedes the clock-only sim_tick from 02_clock.sql.
pg-apply:
	@for f in db/postgrest/00_bootstrap.sql $$(ls db/functions/*.sql | sort); do \
		echo "-- $$f"; \
		$(PSQL) -q -v ON_ERROR_STOP=1 < $$f || exit 1; \
	done
	@docker kill -s SIGUSR1 fieldopt-postgrest >/dev/null 2>&1 || true

# Reseed the demo day from SQL (no Python). Dates land relative to today.
pg-seed:
	$(PSQL) -q -v ON_ERROR_STOP=1 < db/seeds/01_seed.sql
	@echo "seeded: demo day = today"

# Push web/ into the running nginx without an image rebuild (dev loop).
pg-sync:
	docker cp web/. fieldopt-web:/usr/share/nginx/html/
	docker cp deploy/nginx.conf fieldopt-web:/etc/nginx/conf.d/default.conf
	docker exec fieldopt-web nginx -s reload

demo:
	$(PSQL) -q -c "alter database fieldopt set app.is_demo='true'"
	@docker kill -s SIGUSR1 fieldopt-postgrest >/dev/null 2>&1 || true
	@echo "demo UI on — reload http://localhost:8081 and press Start Demo"

no-demo:
	$(PSQL) -q -c "alter database fieldopt set app.is_demo='false'"
	@docker kill -s SIGUSR1 fieldopt-postgrest >/dev/null 2>&1 || true
	@echo "demo UI off"

down:
	$(COMPOSE) down --remove-orphans

clean:
	$(COMPOSE) down -v --remove-orphans

logs:
	$(COMPOSE) logs -f web postgrest postgres

ps:
	$(COMPOSE) ps

rebuild:
	$(COMPOSE) build --no-cache postgres web postgrest
