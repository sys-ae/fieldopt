-- Simulation clock driver. pg_cron runs the tick inside the database, so nothing outside
-- Postgres is required to play a demo day.
--
-- The tick stays scheduler-agnostic on purpose: api.sim_tick() is an ordinary function, so
-- an external cron (or any client) calling it works identically. If pg_cron is unavailable
-- — managed Postgres often omits it — skip this file and schedule the call however you like.
create extension if not exists pg_cron;

do $$
begin
	perform cron.unschedule('fieldopt-sim-tick')
	where exists (select 1 from cron.job where jobname = 'fieldopt-sim-tick');

	perform cron.schedule('fieldopt-sim-tick', '1 seconds', 'select api.sim_tick(1)');

	-- Nightly reseed, so a long-running demo box wakes up on a fresh day. Replaces
	-- _daily_reseed_loop from the retired FastAPI app, which did the same at 04:00 UTC.
	perform cron.unschedule('fieldopt-daily-reseed')
	where exists (select 1 from cron.job where jobname = 'fieldopt-daily-reseed');

	perform cron.schedule('fieldopt-daily-reseed', '0 4 * * *', 'select api.seed_demo()');
end
$$;
