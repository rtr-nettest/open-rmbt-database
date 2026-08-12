# CORINE Land Cover (CLC) — download & import

This describes how to obtain the **CORINE Land Cover (CLC)** dataset and load it into the
`rmbt` database. The land-cover code of a test is derived from these polygons: for each
test location the intersecting CLC class is looked up and stored in
`test_location.land_cover`.

> **The database schema defines everything needed** — the target tables
> `clc18` and `clc18_legend`, the sequence, the GiST index, the grants, and the trigger
> that fills `land_cover` on insert. This document only covers **downloading the data and
> loading the rows into the existing (empty) tables**. You do not need to create tables,
> indexes, grants or triggers by hand.

## Data source & license

CORINE Land Cover is provided by the Copernicus Land Monitoring Service.

- DOI (vector): https://doi.org/10.2909/71c95a07-e296-44fc-b22b-415f42acfdf0

The data is free to use, but **the source must be attributed** (see the DOIs above).
**Downloading requires a (free) user registration.**

A cached version can be found here: https://opendatacache.netztest.at/data/corine/

## What to download

On the download portal, select all current land-cover data. At the time of writing the
current release is **version 2018, status 2020**: `v2020_20u1`.

The download produces one outer ZIP containing the ZIPs of the selected products:

| Area   | Version      | Res.  | Type   | Format   | Size   | Product |
| ------ | ------------ | ----- | ------ | -------- | ------ | ------- |
| Europe | v2020_20u1   | 100 m | Raster | GeoTIFF  | 125 MB | `u2018_clc2018_v2020_20u1_raster100m` |
| Europe | v2020_20u1   | —     | Vector | GDB      | 5 GB   | `u2018_clc2018_v2020_20u1_fgdb` |
| Europe | v2020_20u1   | —     | Vector | GPKG     | 4 GB   | `u2018_clc2018_v2020_20u1_geoPackage` |

We use the **GeoPackage (GPKG)** vector product below.

Unpack the outer archive (the file name is a numeric id, e.g. `97977.zip`):

```bash
unzip 97977.zip
# Archive:  97977.zip
#   inflating: Results/u2018_clc2018_v2020_20u1_fgdb.zip
#   inflating: Results/u2018_clc2018_v2020_20u1_geoPackage.zip
#   inflating: Results/u2018_clc2018_v2020_20u1_raster100m.zip

unzip Results/u2018_clc2018_v2020_20u1_geoPackage.zip
```

This yields the GeoPackage `U2018_CLC2018_V2020_20u1.gpkg` and, under `Legend/`, the
legend CSV `CLC_legend.csv`.

## Prerequisites (GDAL)

The import uses `ogr2ogr` from GDAL. On Debian/Ubuntu:

```bash
apt -y install gdal-bin
```

## Inspect the GeoPackage

```bash
ogrinfo U2018_CLC2018_V2020_20u1.gpkg
```

The GeoPackage contains the main Europe layer `u2018_clc2018_v2020_20u1` plus several
`*_fr_*` layers for the French overseas territories (`glp`, `guf`, `mtq`, `myt`, `reu`).
**Only the main layer is needed** for our purposes.

## Import the polygons into `clc18`

Load **only** the main layer into the existing `clc18` table. Two things matter:

1. **Restrict to the single relevant layer** — the French overseas layers are not needed.
2. **Use the static target name `clc18`** (`-nln clc18`) instead of the versioned source
   layer name. This way a future update within CLC18 does not require a code change:
   the trigger and queries always refer to `clc18`.

Because the schema already created an empty `clc18` table, append into it (`-append`)
rather than letting `ogr2ogr` create a new table:

```bash
ogr2ogr -f "PostgreSQL" \
  PG:"host=localhost user=rmbt dbname=rmbt password=<RMBT_PW>" \
  U2018_CLC2018_V2020_20u1.gpkg \
  -append -nln clc18 \
  u2018_clc2018_v2020_20u1
```

Resulting table (already defined by the schema — shown for reference):

```
rmbt=# \d clc18
  Column  |            Type             | Nullable |             Default
----------+-----------------------------+----------+----------------------------------
 objectid | integer                     | not null | nextval('clc18_objectid_seq'...)
 code_18  | character varying(3)        |          |
 remark   | character varying(20)       |          |
 area_ha  | double precision            |          |
 id       | character varying(18)       |          |
 shape    | geometry(MultiPolygon,3035) |          |
Indexes:
    "clc18_pkey" PRIMARY KEY, btree (objectid)
    "clc18_shape_geom_idx" gist (shape)
```

The main layer is roughly **5.5 GB** once loaded:

```sql
SELECT pg_size_pretty(pg_total_relation_size('clc18'));  -- ~5.5 GB
```

## Import the legend into `clc18_legend`

The `clc18_legend` table is likewise already defined by the schema. Load the legend CSV
into it from `psql` (adjust the path to wherever you unpacked the GeoPackage):

```sql
\copy public.clc18_legend (grid_code, clc_code, label3, rgb) \
  FROM '/var/lib/postgresql/corine/Results/u2018_clc2018_v2020_20u1_geoPackage/Legend/CLC_legend.csv' \
  WITH (FORMAT csv, HEADER true, DELIMITER ';')
```

## Verify

CLC geometries are stored in the **LAEA Europe** projection (SRID **3035**). PostGIS in
WGS84 (SRID **4326**) uses **longitude, latitude** order. A test point in Vienna is
`POINT(16.24554517 48.20248683)`.

```sql
WITH test_point AS (
    SELECT ST_Transform(
               ST_SetSRID(ST_MakePoint(16.24554517, 48.20248683), 4326),
               3035
           ) AS pt
)
SELECT
    t.code_18,
    t.remark
FROM clc18 t, test_point p
WHERE t.shape && p.pt
  AND ST_Intersects(t.shape, p.pt);
```

This should return the CLC class of the point. Once `clc18` is populated, the insert
trigger on test locations automatically fills `test_location.land_cover` with the
matching `code_18` — no further action required.

## What the schema already provides (do **not** recreate)

All of the following exist in `schema/schema.sql` (and the migrations); listed here only
so you understand what the import relies on:

- Tables `clc18` and `clc18_legend`, sequence `clc18_objectid_seq`, primary key, and the
  GiST index `clc18_shape_geom_idx` on `clc18.shape`.
- Grants: `SELECT` on `clc18` and `clc18_legend` to `rmbt_group_read_only`; full rights on
  `clc18_legend` to `rmbt`. (If you import in a way that recreates a table, re-apply at
  least: all rights for `rmbt`, and `SELECT` for `rmbt_group_read_only`.)
- The trigger that derives `land_cover` from `clc18`:

  ```sql
  -- add land_cover (using Corine classification)
  -- Transform the point to LAEA (3035) and pick the intersecting CLC code_18.
  BEGIN
      SELECT t.code_18::INTEGER
          INTO NEW.land_cover
          FROM clc18 t
          WHERE t.shape && ST_Transform(NEW.geom3857, 3035)
            AND ST_Intersects(t.shape, ST_Transform(NEW.geom3857, 3035))
          LIMIT 1;
  EXCEPTION
      WHEN undefined_table THEN
          -- ignore a missing clc18 table, just leave land_cover NULL
          RAISE NOTICE '%', SQLERRM;
  END;
  ```

## Notes (differences from the previous dataset)

This replaces the older, Austria-only `clc12_all_oesterreich` table (~100 MB, CLC 2012):

- The classification column changed from `code_12` to **`code_18`**, and there are **new
  codes** — the legend is loaded into `clc18_legend` accordingly (the old `clc_legend`
  belongs to the previous CLC12 data).
- The old `bbox` column was a manual bounding-box optimization; it is **no longer needed**
  — the GiST index on `shape` with the `&&` operator covers this.
- Geometry is stored in SRID **3035**; the new dataset uses `geometry(MultiPolygon,3035)`
  (the old one was `MultiPolygonZM`).
