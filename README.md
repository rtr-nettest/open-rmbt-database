# Open-RMBT Database

This repository contains the database definition for **Open RMBT** (RTR-NetTest).
More information and other components of Open RMBT can be found here: https://github.com/rtr-nettest/open-rmbt

The database is built on PostgreSQL/PostGIS and used by the measurement backend (Control Server,
Statistics Server and Map Server).

## Repository layout

| Path | Contents                                                                                                                                                          |
| --- |-------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `schema/schema.sql` | **Current snapshot** of the full schema (`pg_dump`): all tables, views, functions, triggers and extensions.                                                       |
| `migrations/` | Flyway-style versioned migration files (`V<n>__<name>.sql`). `V1__initial_schema.sql` = initial schema. Each future database change adds a new numbered file here. |
| `usersetup/` | **One-time cluster bootstrap** (`init_security.sql`): roles, passwords and permissions.                                                                           |
| `data/` | Seed / reference data (`COPY … FROM stdin`): `client_type`, `mcc2country`, `network_type`, `qoe_classification`, `settings`, `test_server`, `test_server_types`.  |
| `scripts/` | Helper scripts for 3rd party Open Data (currently empty).                                                                                                         |
| `LICENSE` | Apache License 2.0.                                                                                                                                               |

### Schema snapshot vs. migrations

- **`schema/schema.sql` is a point-in-time snapshot** of the current database, regenerated
  with `pg_dump`. Use it to stand up a fresh database quickly.
- **Every change to the database adds a new numbered migration file** in `migrations/`
  (`V2__…sql`, `V3__…sql`, …). Migrations are the source of truth for *how the schema
  evolves over time*; the snapshot is the convenience "current state". Keep both in sync
  when you change the database.

## Prerequisites

You need **PostgreSQL** with the **PostGIS** extension. The schema also uses `hstore` and
`postgis_raster`, which ship with the PostGIS package.

On Debian/Ubuntu (adjust the version to your installed PostgreSQL, e.g. `17`):

```bash
sudo apt update
sudo apt install postgresql postgresql-contrib postgresql-17-postgis-3
```

The required extensions (`hstore`, `postgis`, `postgis_raster`) are created automatically
by the schema — you only need the packages installed.

## Setting up the database

Create the database (run as the `postgres` OS/DB user):

```bash
createdb rmbt
```

The application roles (`postgres`, `replication`, `rmbt`, `rmbt_control`, and the
NOLOGIN group roles `rmbt_group_control` / `rmbt_group_read_only`) are created by the
cluster bootstrap `usersetup/init_security.sql`. This is a **one-time, per-cluster**
step.

## Passwords / secrets

`usersetup/init_security.sql` sets role passwords using **placeholders**, not real
values:

```sql
ALTER ROLE postgres    ... PASSWORD '$(POSTGRES_PW)';
ALTER ROLE replication ... PASSWORD '$(REPLICATION_PW)';
ALTER ROLE rmbt        ... PASSWORD '$(RMBT_PW)';
ALTER ROLE rmbt_control... PASSWORD '$(RMBT_CONTROL_PW)';
```

You must supply real passwords **before importing**, either by substituting from
environment variables or by editing the file manually.


## Importing

Import a SQL file into the `rmbt` database with `psql`:

```bash
psql -1 -e rmbt < <file>.sql
```

- `-1` runs the whole file in a **single transaction** (all-or-nothing).
- `-e` **echoes** each statement as it runs.

Recommended order for a fresh setup:

```bash
# 1. One-time cluster bootstrap: roles & permissions.
#    (See "Passwords" above — substitute placeholders first.)
#    Roles are cluster-wide, so run against the 'postgres' database.
#    Skip this step if your cluster already has the rmbt roles.
psql -1 -e postgres < usersetup/init_security.sql

# 2. Load the schema into the database created above — either the current snapshot ...
psql -1 -e rmbt < schema/schema.sql
#    ... or replay the migrations in order:
psql -1 -e rmbt < migrations/V1__initial_schema.sql

# 3. Reference / seed data
for f in data/*.sql; do psql -1 -e rmbt < "$f"; done
```

## License

Licensed under the [Apache License 2.0](LICENSE).
