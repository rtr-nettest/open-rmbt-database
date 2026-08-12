# Fixed & mobile network coverage (BB-Atlas) — download & import

This describes how to obtain **fixed network coverage** data from the Austrian
**Breitbandatlas (BB-Atlas)** and load it into the `rmbt` database, plus how it is
combined with **mobile-network coverage** into the materialized view the application
actually queries.

> **The database schema defines the whole pipeline** — the raw import table
> `bb_atlas_festnetz_<version>`, the `cov_bb_fixed` view on top of it, the `cov_mno`
> mobile table, the `cov_mno_fn` materialized view, the raster index and the grants. This
> document covers the recurring task of **importing a new quarterly release** into that
> structure. Object *definitions* live in `schema/schema.sql`; they are shown below only
> for reference.

## How the pipeline fits together

```
BB-Atlas CSV  ──►  bb_atlas_festnetz_<version>   (raw import, original BB-Atlas columns)
                            │
                            ▼
                     cov_bb_fixed  (VIEW: maps raw columns → stable legacy names)
                            │
   cov_mno  (mobile) ──►    ▼
                     cov_mno_fn  (MATERIALIZED VIEW = cov_bb_fixed  UNION  cov_mno)
                            │
                            ▼
                   queried by the application
```

The raw CSV is imported **unchanged** into a table whose name carries the release version
(e.g. `bb_atlas_festnetz_2025q4`). A **view** (`cov_bb_fixed`) maps the BB-Atlas column
names to the stable legacy names the rest of the database expects. This way a new release
only requires creating a new versioned table and re-pointing the view — no downstream code
changes. `cov_mno_fn` unions the fixed data with the mobile data and is what queries hit.

## Data source

- **Fixed** (BB-Atlas Festnetz), data.gv.at dataset page:
  https://www.data.gv.at/datasets/588b9fdc-d2dd-4628-b186-f7b974065d40?locale=de
  — direct download, e.g.:
  `https://data.breitbandbuero.gv.at/Breitbandatlas/BB-Atlas-Festnetz-Verfuegbarkeit_2025q4_20260511.zip`
CC BY 3.0 (Breitbandbüro)
- **Mobile**: derived from the RTR coverage database (`frq.rtr.at`); see below.

## Download & unpack

Unzip into an `opendata/` tree. The BB-Atlas download expands to `fixed/`, `mobile/` and
`grants/` (funded-rollout) subdirectories; only `fixed/` is used here (mobile coverage
comes from `frq` instead — see below), e.g.:

```
opendata/bbatlas/fixed/BB-Atlas-Festnetz_2025q2_20251117.csv
opendata/bbatlas/mobile/BB-Atlas-Mobilfunknetz_2025q2_20251110.csv
opendata/bbatlas/grants/BB-Atlas-Gefoerderter-Ausbau_2025q4_20260107.gpkg
```

The fixed-network CSV has this header (semicolon-free, comma-separated):

```
"l000100v3","agg_id","infrastrukturanbieterin","technik","download","upload","bearbeitung_bbb"
"100mN28244E46561",1014,"EPnet GmbH Co KG","WLAN",100,20,2025-11-17T08:55:08Z
...
```

## Import a new fixed-network release

Replace `<version>` with the release (e.g. `2025q4`) and adjust the CSV path throughout.

**1. Create the versioned raw table** (original BB-Atlas columns):

```sql
CREATE TABLE bb_atlas_festnetz_<version> (
    l000100v3               VARCHAR(50),
    agg_id                  INTEGER,
    infrastrukturanbieterin VARCHAR(100),
    technik                 VARCHAR(50),
    download                DOUBLE PRECISION,
    upload                  DOUBLE PRECISION,
    bearbeitung_bbb         TIMESTAMPTZ
);
GRANT ALL PRIVILEGES ON TABLE bb_atlas_festnetz_<version> TO rmbt;
```

**2. Load the CSV** (run as the `postgres` OS user so the server can read the file):

```bash
psql -d rmbt -c "
COPY bb_atlas_festnetz_<version>
FROM '/var/lib/postgresql/opendata/bbatlas/fixed/BB-Atlas-Festnetz_<version>.csv'
CSV HEADER;"
```

**3. Re-point the `cov_bb_fixed` view** at the new table. The view maps the BB-Atlas
column names to the stable legacy names:

```sql
CREATE OR REPLACE VIEW cov_bb_fixed AS
SELECT
    ROW_NUMBER() OVER ()                        AS uid,
    l000100v3                                   AS raster,
    infrastrukturanbieterin                     AS operator,
    technik                                      AS technology,
    download::float4                            AS dl_max_mbit,
    upload::float4                              AS ul_max_mbit,
    TO_CHAR(bearbeitung_bbb, 'YYYY-MM-DD')     AS date
FROM bb_atlas_festnetz_<version>;
```

**4. Refresh the combined materialized view** (takes ~3 min):

```sql
REFRESH MATERIALIZED VIEW public.cov_mno_fn;
```

**5. Drop the previous quarter's raw table** once the view points at the new one:

```sql
DROP TABLE bb_atlas_festnetz_<previous_version>;
```

### Column mapping (legacy `cov_bb_fixed` → BB-Atlas CSV)

Earlier, `cov_bb_fixed` was a standalone table; the BB-Atlas column names then changed, so
it is now a view over the raw import table using this mapping:

| Legacy column (`cov_bb_fixed`) | BB-Atlas CSV column     |
| ------------------------------ | ----------------------- |
| `raster`                       | `l000100v3`             |
| `operator`                     | `infrastrukturanbieterin` |
| `technology`                   | `technik`               |
| `dl_max_mbit`                  | `download`              |
| `ul_max_mbit`                  | `upload`                |
| `date`                         | `bearbeitung_bbb`       |
| —                              | `agg_id` (new, unused)  |

## Mobile-network coverage (`cov_mno`)

Mobile coverage is available in the `frq` database. Dump only the **current** snapshot per
operator (filter by the relevant `operator` / `rfc_date` / `reference` — adjust to the
latest release), then load it into `cov_mno`:

```bash
# On the frq host, dump the current mobile snapshot to CSV:
psql -d frq -c "
COPY (
    SELECT uid, operator, reference, license, rfc_date,
           raster, dl_normal, ul_normal, dl_max, ul_max
    FROM cov_mno
    -- rfc_date values below are placeholders; set each to the operator's actual latest release
    WHERE (operator = 'HGRAZ'  AND rfc_date = '2029-01-11')
       OR (operator = 'H3A'    AND rfc_date = '2029-02-09' AND reference = 'F1/16')
       OR (operator = 'MASS'   AND rfc_date = '2029-03-30')
       OR (operator = 'LIWEST' AND rfc_date = '2029-04-26')
       OR (operator = 'SBG'    AND rfc_date = '2029-05-20')
       OR (operator = 'TMA'    AND rfc_date = '2029-06-21' AND reference = 'F1/16')
       OR (operator = 'A1TA'   AND rfc_date = '2029-07-31' AND reference = 'F1/16')
) TO '/var/lib/postgresql/cov_mno_filtered.csv' WITH CSV HEADER;"
```

Load it into `cov_mno` in the `rmbt` database, then refresh the combined view:

```bash
psql -d rmbt -c "COPY cov_mno FROM '/var/lib/postgresql/cov_mno_filtered.csv' CSV HEADER;"
psql -d rmbt -c "REFRESH MATERIALIZED VIEW public.cov_mno_fn;"
```

## What the schema already provides (do **not** recreate)

All of the following exist in `schema/schema.sql`; listed here only so you understand what
the import relies on:

- Raw table `bb_atlas_festnetz_2025q4` (the currently referenced version).
- View `cov_bb_fixed` over that table (the column mapping above).
- Mobile table `cov_mno` (uid, operator, reference, license, rfc_date, raster,
  dl_normal, ul_normal, dl_max, ul_max) with its primary key and raster indexes.
- Materialized view `cov_mno_fn` = `cov_bb_fixed` (as `BBfixed`, license `CCBY4.0 BMLRT`,
  Mbit/s converted to bit/s) **UNION** `cov_mno` (as `mobile`).
- Index `idx_cov_mno_fn_raster` on `cov_mno_fn (raster)` for fast lookups.
- Grants: `SELECT` on `cov_mno_fn` to `rmbt`; `ALL` on `bb_atlas_festnetz_2025q4` to `rmbt`.

When you introduce a **new** versioned `bb_atlas_festnetz_<version>` table, grant it to
`rmbt` (step 1 above); the view and materialized view names stay the same.

## Notes

- The raw BB-Atlas CSV is kept in its **original format**; the release version is encoded
  in the table name, and `cov_bb_fixed` provides a stable interface on top.
- `cov_mno_fn` is what the application queries — always `REFRESH` it after importing either
  fixed or mobile data (≈3 min).
