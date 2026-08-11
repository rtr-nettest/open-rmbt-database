--
-- PostgreSQL database dump
--

\restrict Pvfl7gTzgcJ6fWbaftaYmDfPrcVzRIcLwbji9VAKPV4Z6ccizk9fGcRLfMP1vfp

-- Dumped from database version 17.10 (Debian 17.10-0+deb13u1)
-- Dumped by pg_dump version 17.10 (Debian 17.10-0+deb13u1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: postgres
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO postgres;

--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry, geography, and raster spatial types and functions';


--
-- Name: postgis_raster; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_raster WITH SCHEMA public;


--
-- Name: EXTENSION postgis_raster; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis_raster IS 'PostGIS raster types and functions';


--
-- Name: cov_geo_location_assignment_type; Type: TYPE; Schema: public; Owner: rmbt
--

CREATE TYPE public.cov_geo_location_assignment_type AS (
	location public.geometry,
	accuracy numeric
);


ALTER TYPE public.cov_geo_location_assignment_type OWNER TO rmbt;

--
-- Name: mobiletech; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.mobiletech AS ENUM (
    'unknown',
    '2G',
    '3G',
    '4G',
    'mixed'
);


ALTER TYPE public.mobiletech OWNER TO postgres;

--
-- Name: qostest; Type: TYPE; Schema: public; Owner: rmbt
--

CREATE TYPE public.qostest AS ENUM (
    'website',
    'http_proxy',
    'non_transparent_proxy',
    'dns',
    'tcp',
    'udp',
    'traceroute',
    'voip',
    'traceroute_masked'
);


ALTER TYPE public.qostest OWNER TO rmbt;

--
-- Name: cov_get_donor_geo_location(bigint); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.cov_get_donor_geo_location(test_uid bigint) RETURNS public.cov_geo_location_assignment_type
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
	SELECT ST_Line_Interpolate_Point(ST_MakeLine(geom_pre,geom_post), time_relative), 
		GREATEST(accuracy_post, accuracy_pre, ST_Distance(geom_post::geography, geom_pre::geography))::numeric from
		(select p1.*, p2.*, p1.dist_pre/(p1.dist_pre+p2.dist_post) as time_relative from 
			(select extract(epoch from (ct.test_start_time - cg.time)) as dist_pre, cg.location as geom_pre, cg.accuracy as accuracy_pre from coverage_test ct 
				join coverage_geo_location cg on cg.client_uuid = ct.geo_location_donor_uuid
				where cg.provider='gps' and ct.uid = test_uid and cg.time < ct.test_start_time and (ct.test_start_time - INTERVAL '6 minutes') < cg.time order by cg.time desc limit 1) as p1,
			(select extract(epoch from (cg.time - ct.test_start_time)) as dist_post, cg.location as geom_post, cg.accuracy as accuracy_post from coverage_test ct 
				join coverage_geo_location cg on cg.client_uuid = ct.geo_location_donor_uuid
				where cg.provider='gps' and ct.uid = test_uid and cg.time >= ct.test_start_time and (ct.test_start_time + INTERVAL '6 minutes') > cg.time order by cg.time asc limit 1) as p2
		) as t1;
$$;


ALTER FUNCTION public.cov_get_donor_geo_location(test_uid bigint) OWNER TO rmbt;

--
-- Name: cov_get_own_geo_location(bigint, integer); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.cov_get_own_geo_location(test_uid bigint, max_age integer) RETURNS public.cov_geo_location_assignment_type
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
	dist_pre numeric;
	accuracy_pre numeric;
	geom_pre geometry;
	dist_post numeric;
	accuracy_post numeric;
	geom_post geometry;
	geom_accuracy numeric;
BEGIN

	select extract(epoch from (ct.test_start_time - cg.time)), cg.location, cg.accuracy into dist_pre, geom_pre, accuracy_pre from coverage_test ct 
			join coverage_geo_location cg on cg.client_uuid = ct.client_uuid
			where ct.uid = test_uid and cg.time < ct.test_start_time 
				and extract(epoch from (ct.test_start_time - cg.time)) <= max_age
			order by cg.time desc limit 1;

	select extract(epoch from (cg.time - ct.test_start_time)), cg.location, cg.accuracy into dist_post, geom_post, accuracy_post from coverage_test ct 
			join coverage_geo_location cg on cg.client_uuid = ct.client_uuid
			where ct.uid = test_uid and cg.time >= ct.test_start_time 
				and extract(epoch from (cg.time - ct.test_start_time)) <= max_age
			order by cg.time asc limit 1;

	raise notice '% % %',accuracy_post, accuracy_pre, ST_Distance(geom_post::geography, geom_pre::geography);
	geom_accuracy := GREATEST(accuracy_post, accuracy_pre, ST_Distance(geom_post::geography, geom_pre::geography));

	IF (dist_pre NOTNULL OR dist_post NOTNULL) THEN
		-- raise notice '% % % % ', geom_pre, geom_post, coalesce(dist_pre,9999), coalesce(dist_post,9999);
		IF (coalesce(dist_pre, (max_age+1)) < coalesce(dist_post, (max_age+1))) THEN
			RETURN ROW(geom_pre, geom_accuracy);
		ELSE
			RETURN ROW(geom_post, geom_accuracy);
		END IF;
	ELSE
		RETURN NULL;
	END IF;
END;
$$;


ALTER FUNCTION public.cov_get_own_geo_location(test_uid bigint, max_age integer) OWNER TO rmbt;

--
-- Name: cov_get_own_geo_location_uid(bigint, integer); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.cov_get_own_geo_location_uid(test_uid bigint, max_age integer) RETURNS bigint
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
	dist_pre numeric;
	uid_pre bigint;
	dist_post numeric;
	uid_post bigint;
BEGIN

	select extract(epoch from (ct.test_start_time - cg.time)), cg.uid into dist_pre, uid_pre from coverage_test ct 
			join coverage_geo_location cg on cg.client_uuid = ct.geo_location_donor_uuid
			where ct.uid = test_uid and cg.time < ct.test_start_time 
				and extract(epoch from (ct.test_start_time - cg.time)) <= max_age
			order by cg.time desc limit 1;

	select extract(epoch from (cg.time - ct.test_start_time)), cg.uid into dist_post, uid_post from coverage_test ct 
			join coverage_geo_location cg on cg.client_uuid = ct.geo_location_donor_uuid
			where ct.uid = test_uid and cg.time >= ct.test_start_time 
				and extract(epoch from (cg.time - ct.test_start_time)) <= max_age
			order by cg.time asc limit 1;

	IF (dist_pre NOTNULL OR dist_post NOTNULL) THEN
		IF (coalesce(dist_pre, (max_age+1)) < coalesce(dist_post, (max_age+1))) THEN
			RETURN uid_pre;
		ELSE
			RETURN uid_post;
		END IF;
	ELSE
		RETURN NULL;
	END IF;
END;
$$;


ALTER FUNCTION public.cov_get_own_geo_location_uid(test_uid bigint, max_age integer) OWNER TO rmbt;

--
-- Name: cov_get_signal_strength_items(bigint); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.cov_get_signal_strength_items(test_uid bigint) RETURNS TABLE(signal_strength integer, time_ns bigint, name character varying, type character varying)
    LANGUAGE sql IMMUTABLE STRICT ROWS 100
    AS $$
	SELECT COALESCE(_j.signal->>'signal_strength', _j.signal->>'lte_rsrp',_j.signal->>'wifi_rssi')::integer AS signal_strength,
		(_j.signal->>'time_ns')::bigint AS time_ns, nt.name, nt.type FROM
			(SELECT jsonb_array_elements(ct.signal_items) AS signal FROM coverage_test ct WHERE ct.uid=test_uid) AS _j
		JOIN network_type nt ON nt.uid = (signal->>'network_id')::int;
$$;


ALTER FUNCTION public.cov_get_signal_strength_items(test_uid bigint) OWNER TO rmbt;

--
-- Name: cov_signal_json_to_csv(jsonb); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.cov_signal_json_to_csv(signals jsonb) RETURNS character varying
    LANGUAGE sql IMMUTABLE STRICT
    AS $$

SELECT string_agg(
round(((s->>'time_ns')::double precision / 1000000000)::numeric, 3)
|| ';' || (s->'lte_rsrp')
, ';')
 FROM jsonb_array_elements(signals) s;
$$;


ALTER FUNCTION public.cov_signal_json_to_csv(signals jsonb) OWNER TO rmbt;

--
-- Name: fix_geometry_columns(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fix_geometry_columns() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
	mislinked record;
	result text;
	linked integer;
	deleted integer;
	foundschema integer;
BEGIN

	-- Since 7.3 schema support has been added.
	-- Previous postgis versions used to put the database name in
	-- the schema column. This needs to be fixed, so we try to
	-- set the correct schema for each geometry_colums record
	-- looking at table, column, type and srid.
	
	return 'This function is obsolete now that geometry_columns is a view';

END;
$$;


ALTER FUNCTION public.fix_geometry_columns() OWNER TO postgres;

--
-- Name: get_bev_vgd(public.geometry); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_bev_vgd(location public.geometry) RETURNS TABLE(kg_nr character varying, kg_nr_bev integer, kg character varying, meridian character varying, gkz character varying, gkz_bev integer, pg character varying, bkz character varying, pb character varying, fa_nr character varying, fa character varying, gb_kz character varying, gb character varying, va_nr character varying, va character varying, bl_kz character varying, bl character varying, st_kz smallint, st character varying, fl double precision, geom public.geometry)
    LANGUAGE plpgsql
    AS $$

BEGIN


    BEGIN
        RETURN QUERY
            SELECT bev_vgd.kg_nr,
                   bev_vgd.kg_nr::integer,
                   bev_vgd.kg,
                   bev_vgd.meridian,
                   bev_vgd.gkz,
                   bev_vgd.gkz::integer,
                   bev_vgd.pg,
                   bev_vgd.bkz,
                   bev_vgd.pb,
                   bev_vgd.fa_nr,
                   bev_vgd.fa,
                   bev_vgd.gb_kz,
                   bev_vgd.gb,
                   bev_vgd.va_nr,
                   bev_vgd.va,
                   bev_vgd.bl_kz,
                   bev_vgd.bl,
                   bev_vgd.st_kz,
                   bev_vgd.st,
                   bev_vgd.fl,
                   bev_vgd.geom

            FROM bev_vgd
            WHERE within(st_transform(location, 31287), bev_vgd.geom)
            LIMIT 1;

    EXCEPTION
        WHEN undefined_table THEN
            -- just return NULL, but ignore missing database
            RAISE NOTICE '%', SQLERRM;
    END;

END;


$$;


ALTER FUNCTION public.get_bev_vgd(location public.geometry) OWNER TO postgres;

--
-- Name: get_gkz_sa(public.geometry); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_gkz_sa(location public.geometry) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    gkz_sa INTEGER := NULL;
BEGIN
    IF (location IS NULL) THEN
        RETURN NULL;
    end if;
    BEGIN
        SELECT sa.id::INTEGER INTO gkz_sa
        FROM statistik_austria_gem sa
        WHERE within(st_transform(location, 31287), sa.geom)
        LIMIT 1;

    EXCEPTION
        WHEN undefined_table THEN
            -- just return NULL, but ignore missing database
            RAISE NOTICE '%', SQLERRM;
    END;
    RETURN gkz_sa;
END;

$$;


ALTER FUNCTION public.get_gkz_sa(location public.geometry) OWNER TO postgres;

--
-- Name: get_replication_delay(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_replication_delay() RETURNS SETOF pg_stat_replication
    LANGUAGE sql SECURITY DEFINER
    AS $$ SELECT * FROM pg_catalog.pg_stat_replication; $$;


ALTER FUNCTION public.get_replication_delay() OWNER TO postgres;

--
-- Name: get_sync_code(uuid); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.get_sync_code(client_uuid uuid) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE 
	return_code VARCHAR;
	count integer;
	
BEGIN
count := 0;
SELECT sync_code INTO return_code FROM client WHERE client.uuid = CAST(client_uuid AS UUID);

if (return_code ISNULL OR char_length(return_code) < 1) then
	LOOP
		return_code := random_sync_code(7);
		BEGIN
			UPDATE client
			SET sync_code = return_code
			WHERE client.uuid = CAST(client_uuid AS UUID);
			return return_code;
		EXCEPTION WHEN unique_violation THEN
			-- return NULL when tried 10 times;
			if (count > 10) then
				return NULL;
			end if;
			count := count + 1;
		END;
	END LOOP;
else 
	return return_code;
end if;
END;
$$;


ALTER FUNCTION public.get_sync_code(client_uuid uuid) OWNER TO rmbt;

--
-- Name: getnewsstatus(boolean, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.getnewsstatus(boolean, timestamp with time zone, timestamp with time zone) RETURNS character varying
    LANGUAGE plpgsql
    AS $_$
DECLARE
    active alias for $1;
    startDate alias for $2;
    endDate alias for $3;
    now       timestamp with time zone;
    isEnded   boolean;
    isStarted boolean;
BEGIN
    now := NOW();
    isEnded := endDate IS NOT NULL AND endDate < now;
    isStarted := startDate < now;

    RETURN CASE
               WHEN active AND NOT isEnded AND NOT isStarted
                   THEN 'SCHEDULED'
               WHEN active AND NOT isEnded AND isStarted
                   THEN 'PUBLISHED'
               WHEN active AND isEnded
                   THEN 'EXPIRED'
               ELSE 'DRAFT'
        END;
END;
$_$;


ALTER FUNCTION public.getnewsstatus(boolean, timestamp with time zone, timestamp with time zone) OWNER TO postgres;

--
-- Name: rmbt_fill_open_uuid(); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.rmbt_fill_open_uuid() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
 _t RECORD;
 _uuid uuid;
BEGIN

FOR _t IN SELECT uid,client_id,time FROM test WHERE open_uuid IS NULL ORDER BY uid LOOP
    SELECT INTO _uuid open_uuid FROM test WHERE client_id=_t.client_id AND (_t.time - INTERVAL '4 hours' < time) AND uid<_t.uid ORDER BY uid DESC LIMIT 1;
    IF (_uuid IS NULL) THEN
        _uuid = gen_random_uuid();
    END IF;
    UPDATE test SET open_uuid=_uuid WHERE uid=_t.uid;
END LOOP;

END;$$;


ALTER FUNCTION public.rmbt_fill_open_uuid() OWNER TO rmbt;

--
-- Name: rmbt_get_country_iso_a2(public.geometry); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rmbt_get_country_iso_a2(point public.geometry) RETURNS character varying
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
  -- ISO3266 two digit country code (e.g. 'US')
  a2 varchar(5);
BEGIN

	-- Example query: select rmbt_get_country_iso_a2(st_setsrid(ST_GeomFromText('POINT(-71.064544 42.28787)'),4326));

	
	select into a2 ac.iso_a2 from admin_0_countries ac where point && ac.geom and within(point,ac.geom) and char_length(iso_a2) = 2;
    return a2;
    
END;
$$;


ALTER FUNCTION public.rmbt_get_country_iso_a2(point public.geometry) OWNER TO postgres;

--
-- Name: rmbt_get_distance_iso_a2(public.geometry, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rmbt_get_distance_iso_a2(point public.geometry, a2 character varying) RETURNS double precision
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
  -- ISO3266 two digit country code (e.g. 'US')
  distance float;
BEGIN
    -- returns the distance in meter (m) betweeen location in WGS84 (EPSG:4236) and a two digit country code (e.g. 'US')
	
	-- Example query: select rmbt_get_distance_iso_a2(st_setsrid(ST_GeomFromText('POINT(-71.064544 42.28787)'),4326),'CA');
 		
	return  ST_DistanceSpheroid(point,(select geom from admin_0_countries ac where iso_a2=a2),'SPHEROID["WGS 84",6378137,298.257223563]');
    
END;
$$;


ALTER FUNCTION public.rmbt_get_distance_iso_a2(point public.geometry, a2 character varying) OWNER TO postgres;

--
-- Name: rmbt_get_sync_code(uuid); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.rmbt_get_sync_code(client_uuid uuid) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE 
	return_code VARCHAR;
	count integer;
	
BEGIN
count := 0;
SELECT sync_code INTO return_code FROM client WHERE client.uuid = CAST(client_uuid AS UUID) AND sync_code_timestamp + INTERVAL '1 month' > NOW();

if (return_code ISNULL OR char_length(return_code) < 1) then
	LOOP
		return_code := random_sync_code(12);
		BEGIN
			UPDATE client
			SET sync_code = return_code,
			sync_code_timestamp = NOW()
			WHERE client.uuid = CAST(client_uuid AS UUID);
			return return_code;
		EXCEPTION WHEN unique_violation THEN
			-- return NULL when tried 10 times;
			if (count > 10) then
				return NULL;
			end if;
			count := count + 1;
		END;
	END LOOP;
else 
	return return_code;
end if;
END;
$$;


ALTER FUNCTION public.rmbt_get_sync_code(client_uuid uuid) OWNER TO rmbt;

--
-- Name: rmbt_log_changed_columns(text, text, record, record, text[]); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.rmbt_log_changed_columns(id text, op text, old_row record, new_row record, excluded_cols text[] DEFAULT '{}'::text[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
-- logs all changed columns in one line
-- usage in insert/update trigger functions: PERFORM rmbt_log_changed_columns('Identification string', TG_OP, OLD, NEW, ARRAY['column_name_to_ignore']);
-- optional parameter: excluded_cols / ARRAY['column_name_to_ignore']
-- example for trigger_test():
-- BEGIN
--     -- Errors are caught in case of run-time problems in order to avoid stopping the execution of the trigger function
--     PERFORM rmbt_log_changed_columns(concat_ws('=', 'test.client_id', coalesce(NEW.client_id::text, OLD.client_id::text, 'NULL!!!')), TG_OP, OLD, NEW);
-- EXCEPTION
--     WHEN insufficient_privilege THEN
--         RAISE NOTICE 'No permission to call rmbt_log_changed_columns(): ERROR [%] %', SQLSTATE, SQLERRM;
--     WHEN undefined_function THEN
--         RAISE NOTICE 'Missing rmbt_log_changed_columns(): ERROR [%] %', SQLSTATE, SQLERRM;
--     WHEN OTHERS THEN
--         RAISE NOTICE 'Unexpected rmbt_log_changed_columns(): ERROR [%] %', SQLSTATE, SQLERRM;
-- END; -- BEGIN ... EXCEPTION
-- must have either: 
--  GRANT EXECUTE ON FUNCTION rmbt_log_changed_columns(text, text, record, record, text[]) TO rmbt_control;
--  or
--  DROP FUNCTION/CREATE FUNCTION without any GRANTs at all (Access privileges/proacl must be empty/NULL with \df+ rmbt_log_changed_columns)
-- usage in terminal (ask AI for anyelement): select rmbt_log_changed_columns('Some identifier', 'UPDATE', (select test from test where uid=54413563), (select test from test where uid=54413562), ARRAY['android_permissions'] );
DECLARE
    changes text;
    v_op text := upper(op);
BEGIN
    IF v_op = 'INSERT' THEN
        SELECT string_agg(
                   format(
                       '%I: %s -> %s',
                       n.key,
                       'NULL',
                       CASE WHEN n.value = 'null'::jsonb THEN 'NULL' ELSE n.value::text END
                   ),
                   ', ' ORDER BY n.key
               )
        INTO changes
        FROM jsonb_each(to_jsonb(new_row)) AS n
        WHERE NOT (n.key = ANY(excluded_cols))
          AND n.value <> 'null'::jsonb;

    ELSIF v_op = 'UPDATE' THEN
        SELECT string_agg(
                   format(
                       '%I: %s -> %s',
                       n.key,
                       CASE WHEN o.value = 'null'::jsonb THEN 'NULL' ELSE o.value::text END,
                       CASE WHEN n.value = 'null'::jsonb THEN 'NULL' ELSE n.value::text END
                   ),
                   ', ' ORDER BY n.key
               )
        INTO changes
        FROM jsonb_each(to_jsonb(new_row)) AS n
        JOIN jsonb_each(to_jsonb(old_row)) AS o USING (key)
        WHERE n.value IS DISTINCT FROM o.value
          AND NOT (n.key = ANY(excluded_cols));

    ELSIF v_op = 'DELETE' THEN
        SELECT string_agg(
                   format(
                       '%I: %s -> %s',
                       o.key,
                       CASE WHEN o.value = 'null'::jsonb THEN 'NULL' ELSE o.value::text END,
                       'NULL'
                   ),
                   ', ' ORDER BY o.key
               )
        INTO changes
        FROM jsonb_each(to_jsonb(old_row)) AS o
        WHERE NOT (o.key = ANY(excluded_cols))
          AND o.value <> 'null'::jsonb;

    ELSE
        RAISE EXCEPTION 'Unsupported operation type: %', op;
    END IF;

    IF changes IS NOT NULL THEN
        RAISE NOTICE '{%} [%] Changed columns: %', id, v_op, changes;
    END IF;
END;
$$;


ALTER FUNCTION public.rmbt_log_changed_columns(id text, op text, old_row record, new_row record, excluded_cols text[]) OWNER TO rmbt;

--
-- Name: rmbt_lte_rsrp(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rmbt_lte_rsrp(otu uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
   declare
      rsrp int4;

	BEGIN

   select min(rs.lte_rsrp) into rsrp from radio_signal rs 
left join radio_cell rc on rc.uuid  = rs.cell_uuid 
where rs.open_test_uuid = otu  and rc.active = true and (rc.primary_data_subscription is null or rc.primary_data_subscription ='true') group by rs.open_test_uuid;

if (rsrp is null) then
   select min(s.lte_rsrp) into rsrp from signal s where s.open_test_uuid = otu; 
  end if;
   
    return rsrp;
	END;
$$;


ALTER FUNCTION public.rmbt_lte_rsrp(otu uuid) OWNER TO postgres;

--
-- Name: rmbt_lte_rsrq(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.rmbt_lte_rsrq(otu uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
   declare
      rsrq int4;

	BEGIN

   select min(rs.lte_rsrq) into rsrq from radio_signal rs 
left join radio_cell rc on rc.uuid  = rs.cell_uuid 
where rs.open_test_uuid = otu  and rc.active = true and (rc.primary_data_subscription is null or rc.primary_data_subscription ='true') group by rs.open_test_uuid;

if (rsrq is null) then
   select min(s.lte_rsrq) into rsrq from signal s where s.open_test_uuid = otu; 
  end if;
   
    return rsrq;
	END;
$$;


ALTER FUNCTION public.rmbt_lte_rsrq(otu uuid) OWNER TO postgres;

--
-- Name: rmbt_random_sync_code(integer); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.rmbt_random_sync_code(integer) RETURNS text
    LANGUAGE sql
    AS $_$

    select upper(
        substring(
            (
                SELECT string_agg(md5(random()::TEXT), '')
                FROM generate_series(1, CEIL($1 / 32.)::integer)
                ),
        (33-$1))
    );

$_$;


ALTER FUNCTION public.rmbt_random_sync_code(integer) OWNER TO rmbt;

--
-- Name: rmbt_set_provider_from_as(bigint); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.rmbt_set_provider_from_as(_test_id bigint) RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
  _asn bigint;
  _rdns character varying;
  _provider_id integer;
  _provider_name character varying;
BEGIN

SELECT
  ap.provider_id,
  p.shortname
  FROM test t
  JOIN as2provider ap
  ON t.public_ip_asn=ap.asn 
  AND (ap.dns_part IS NULL OR t.public_ip_rdns ILIKE ap.dns_part /*Case insensitive regexp, DJ per #235:*/ OR t.public_ip_rdns ~* ap.dns_part)
  JOIN provider p
  ON p.uid = ap.provider_id
  WHERE t.uid = _test_id
  ORDER BY dns_part IS NOT NULL DESC
  LIMIT 1
  INTO _provider_id, _provider_name;

IF _provider_id IS NOT NULL THEN
  UPDATE test SET provider_id = _provider_id WHERE uid = _test_id;
  RETURN _provider_name;
ELSE
  RETURN NULL;
END IF;

END;
$$;


ALTER FUNCTION public.rmbt_set_provider_from_as(_test_id bigint) OWNER TO rmbt;

--
-- Name: trigger_geo_location(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trigger_geo_location() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
	BEGIN

		
    IF (TG_OP = 'INSERT' and new.location is not NULL) then
       new.geom3857=st_setsrid(new.location,3857);
       new.geom4326=st_transform(new.geom3857,4326);
     end if;
    RETURN NEW;

	END;
$$;


ALTER FUNCTION public.trigger_geo_location() OWNER TO postgres;

--
-- Name: trigger_qos_test_result(); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.trigger_qos_test_result() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
--
BEGIN
  IF  (TG_OP = 'INSERT' OR TG_OP = 'UPDATE')
  -- timeout is reported although the duration is shorter than the preconfigured one
  AND ((NEW."result" ->> 'duration_ns')::bigint < (NEW."result" ->> 'dns_objective_timeout')::bigint)
  AND ((NEW."result" ->> 'dns_result_info') = 'TIMEOUT'::TEXT) THEN
    NEW.deleted = TRUE;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.trigger_qos_test_result() OWNER TO rmbt;

--
-- Name: trigger_radio_cell(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trigger_radio_cell() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- post process if location is updated
  IF (TG_OP = 'INSERT') THEN
    -- ignore Android/NetMonster invalid/unknown value 0x7fffFFFF or negative values 
    IF (new.location_id = 2147483647 OR new.location_id < 0) THEN
      new.location_id = NULL;
    END IF;
    -- ignore Android/NetMonster invalid/unknown value 0x7fffFFFF or negative values
    IF (new.area_code = 2147483647 OR new.area_code < 0) THEN
      new.area_code = NULL;
    END IF;  
    -- workaround for 3.x apps which swap area_code and location_id was removed according to #1745
  END IF;
RETURN NEW;
END;
$$;


ALTER FUNCTION public.trigger_radio_cell() OWNER TO postgres;

--
-- Name: trigger_test(); Type: FUNCTION; Schema: public; Owner: rmbt
--

CREATE FUNCTION public.trigger_test() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    _country_location      varchar;
    _tmp_uuid              uuid;
    _tmp_uid               integer;
    _tmp_time              timestamp;
    _mcc_sim               VARCHAR;
    _mcc_net               VARCHAR;
    -- limit for accurate location (differs from map where 2000m and 10000m are thresholds)
    _min_accuracy CONSTANT integer := 3000;
    _tmp_geom4326          geometry;
    _rec                   RECORD; -- variable of type record, e.g. for storing a row of a table

BEGIN
    -- for speeding up migration, e.g. of columns in #1709, currently commented out
    -- all triggers can be disabled for a session  with a "SET session_replication_role = replica; update ... " as well
    --if TG_OP = 'UPDATE' and new.row_update is distinct from old.row_update then return new; end if;

    -- for general debug purposes
    -- activate logging with: show log_min_messages; ALTER SYSTEM SET log_min_messages = 'notice'; SELECT pg_reload_conf(); -- default: 'warning'
    -- deactivate logging with: ALTER SYSTEM RESET log_min_messages; SELECT pg_reload_conf(); show log_min_messages; -- default: 'warning'
    RAISE NOTICE 'BRKPT@triger_test() BEGIN: TG_OP= %, old.status= %, new.status= %, old.open_test_uuid= %, new.open_test_uuid= %, (test.)old.uuid= %, (test.)new.uuid= %', TG_OP, old.status, new.status, old.open_test_uuid, new.open_test_uuid, old.uuid, new.uuid;

    -- log all changed columns
    -- !!! mind access privileges (proacl), cf. comments in the function !!!
    BEGIN
    -- Errors are caught in case of run-time problems in order to avoid stopping the execution of the trigger function
        PERFORM rmbt_log_changed_columns(concat_ws('=', 'test.client_id', coalesce(NEW.client_id::text, OLD.client_id::text, 'NULL!!!')), TG_OP, OLD, NEW);
    EXCEPTION
        WHEN insufficient_privilege THEN
            RAISE NOTICE 'No permission to call rmbt_log_changed_columns(): ERROR [%] %', SQLSTATE, SQLERRM;
        WHEN undefined_function THEN
            RAISE NOTICE 'Missing rmbt_log_changed_columns(): ERROR [%] %', SQLSTATE, SQLERRM;
        WHEN OTHERS THEN
            RAISE NOTICE 'Unexpected rmbt_log_changed_columns(): ERROR [%] %', SQLSTATE, SQLERRM;      
    END; -- BEGIN ... EXCEPTION

    -- debug IP adresses
    RAISE NOTICE 'BRKPT@triger_test() ip_addresses : TG_OP= %, time old/new= % / %, status old/new= % / %, client_id old/new= % / %, open_test_uuid old/new= % / %, client_public_ip old/new= % / %, client_public_ip_anonymized old/new= % / %, server_ip old/new= % / %, public_ip_rdns old/new= % / %, client_ip_local old/new= % / %, client_ip_local_anonymized old/new= % / %, client_ip_local_type old/new= % / %, source_ip old/new= % / %, source_ip_anonymized old/new= % / %', TG_OP, old.time, new.time, old.status, new.status, old.client_id, new.client_id, old.open_test_uuid, new.open_test_uuid, old.client_public_ip, new.client_public_ip, old.client_public_ip_anonymized, new.client_public_ip_anonymized, old.server_ip, new.server_ip, old.public_ip_rdns, new.public_ip_rdns, old.client_ip_local, new.client_ip_local, old.client_ip_local_anonymized, new.client_ip_local_anonymized, old.client_ip_local_type, new.client_ip_local_type, old.source_ip, new.source_ip, old.source_ip_anonymized, new.source_ip_anonymized; 

    -- for debugging of deadlocks, according to https://wiki.postgresql.org/wiki/Lock_Monitoring and https://www.postgresql.org/docs/current/view-pg-locks.html
    FOR _rec IN SELECT pl.relation::regclass, *
        FROM pg_locks pl
        LEFT JOIN pg_stat_activity psa
        ON pl.pid = psa.pid where not pl.granted
    LOOP
        RAISE NOTICE 'BRKPT@triger_test() BEGIN: pg_locks row= %', _rec;
    END LOOP;
   
	-- workaround against deletion of client_software_version update
    IF (TG_OP = 'UPDATE' and new.client_software_version is null ) THEN
       NEW.client_software_version = old.client_software_version;
       RAISE NOTICE 'BRKPT@triger_test(): Deletion of client_software_version not accepted';
    END IF;
	
		 -- log if status changes from FINISHED to something else
    IF ((TG_OP = 'UPDATE') and (new.status is distinct from old.status) and old.status = 'FINISHED' ) THEN
       NEW.comment = 'Status FINISHED modified';
       NEW.implausible = true;
       RAISE NOTICE 'BRKPT@triger_test(): Status FINISHED modified';
    END IF;

    -- #715 workaround for bug in old clients which swap cell_area_code,cell_location_id for Android version 3.x.x clients
    -- was removed according to #1745

    -- calc logarithmic speed downlink
    IF ((TG_OP = 'INSERT' OR NEW.speed_download IS DISTINCT FROM OLD.speed_download) AND NEW.speed_download > 0) THEN
        NEW.speed_download_log = (log(NEW.speed_download::double precision / 10)) / 4;
    END IF;
    -- calc logarithmic speed uplink
    IF ((TG_OP = 'INSERT' OR NEW.speed_upload IS DISTINCT FROM OLD.speed_upload) AND NEW.speed_upload > 0) THEN
        NEW.speed_upload_log = (log(NEW.speed_upload::double precision / 10)) / 4;
    END IF;
    -- calc median and logarithmic ping, ping_shortest is fallback only
    IF ((TG_OP = 'INSERT' OR NEW.ping_shortest IS DISTINCT FROM OLD.ping_shortest) AND NEW.ping_shortest > 0) THEN
        NEW.ping_shortest_log = (log(NEW.ping_shortest::double precision / 1000000)) / 3;
        -- ping_median (from ping table)
        -- old: SELECT INTO NEW.ping_median floor(median(coalesce(value_server, value))) FROM ping WHERE NEW.uid = test_id;
        SELECT INTO NEW.ping_median floor(percentile_cont(0.5) WITHIN GROUP (ORDER BY coalesce(value_server, value))) FROM ping WHERE NEW.uid = test_id;
        -- for very old clients which don't deliver speed items:
        IF (NEW.ping_median IS NULL) THEN
            NEW.ping_median = NEW.ping_shortest;
            RAISE NOTICE 'BRKPT@Very old client detected: old.open_test_uuid= %, new.open_test_uuid= %', old.open_test_uuid, new.open_test_uuid;
        END IF;
        NEW.ping_median_log = (log(NEW.ping_median::double precision / 1000000)) / 3;
    END IF;
 
  -- migration to "clean" location projections:
 -- DZ 2023-04-02 now in ControlServer  
 --  IF ((NEW.location IS NOT NULL) AND (new.location is distinct from old.location)) THEN
 --        new.geom3857=st_setsrid(new.location,3857); 
 --       new.geom4326=st_transform(new.geom3857,4326);
 -- end if;     
   
   --  process location in table test_location

    IF ((NEW.geom4326 IS NOT NULL) AND (new.geom4326 is distinct from old.geom4326) AND
        (NEW.geo_location_uuid IS NOT NULL) ) THEN
        UPDATE test_location
        SET geo_location_uuid = NEW.geo_location_uuid,
            geom4326          = new.geom4326,
            -- geom3857 might be removed in the future from test_location
            geom3857	      = new.geom3857,
            -- location is obsolete and shall be removed from test_location when migration is finished
            location          = NEW.location,
            geo_lat           = NEW.geo_lat,
            geo_long          = NEW.geo_long,
            geo_accuracy      = NEW.geo_accuracy,
            geo_provider      = NEW.geo_provider
        WHERE open_test_uuid  = NEW.open_test_uuid;
        IF NOT FOUND THEN
            INSERT INTO test_location (geo_location_uuid,open_test_uuid, geom4326, geom3857, location, geo_lat,
                                       geo_long, geo_accuracy, geo_provider)
            VALUES (NEW.geo_location_uuid,NEW.open_test_uuid, new.geom4326, new.geom3857, NEW.location, NEW.geo_lat,
                    NEW.geo_long, NEW.geo_accuracy, NEW.geo_provider);
        END IF;
    END IF;

    select into _country_location country_location from test_location tl where tl.open_test_uuid = NEW.open_test_uuid;

    -- end of location post processing

    -- debug mobile_provider_id
    RAISE NOTICE 'BRKPT@triger_test() mobile_provider_id: TG_OP= %, time old/new= % / %, status old/new= % / %, client_id old/new= % / %, open_test_uuid old/new= % / %, _country_location= %, network_sim_operator old/new= % / %, network_operator old/new= % / %, location old/new= % / %, roaming_type old/new= % / %, mobile_provider_id old/new= % / %', TG_OP, old.time, new.time, old.status, new.status, old.client_id, new.client_id, old.open_test_uuid, new.open_test_uuid, _country_location, old.network_sim_operator, new.network_sim_operator, old.network_operator, new.network_operator, old.location, new.location, old.roaming_type, new.roaming_type, old.mobile_provider_id, new.mobile_provider_id; 
    -- set roaming_type /mobile_provider_id
    IF (TG_OP = 'INSERT'
        OR NEW.network_sim_operator IS DISTINCT FROM OLD.network_sim_operator
        OR NEW.network_operator IS DISTINCT FROM OLD.network_operator
        OR NEW.time IS DISTINCT FROM OLD.time
        OR NEW.location IS DISTINCT FROM OLD.location
        ) THEN

        IF (NEW.network_sim_operator IS NULL OR NEW.network_operator IS NULL) THEN
            NEW.roaming_type = NULL;
        ELSE
            IF (NEW.network_sim_operator = NEW.network_operator) THEN
                NEW.roaming_type = 0; -- no roaming
            ELSE
                _mcc_sim := split_part(NEW.network_sim_operator, '-', 1);
                _mcc_net := split_part(NEW.network_operator, '-', 1);
                -- TODO not correct for India - #1050 (old)
                IF (_mcc_sim = _mcc_net) THEN
                    NEW.roaming_type = 1; -- national roaming
                ELSE
                    NEW.roaming_type = 2; -- international roaming
                END IF;
            END IF;
        END IF;

        -- set mobile_provider_id
        -- do not set if outside Austria
        IF ((NEW.roaming_type IS NULL AND _country_location IS DISTINCT FROM 'AT') OR
            NEW.roaming_type IS NOT DISTINCT FROM 2) THEN -- not for foreign networks #659 
            NEW.mobile_provider_id = NULL;
        ELSE
            SELECT INTO NEW.mobile_provider_id provider_id
            FROM mccmnc2provider
            WHERE mcc_mnc_sim = NEW.network_sim_operator
              AND (valid_from IS NULL OR valid_from <= NEW.time)
              AND (valid_to IS NULL OR valid_to >= NEW.time)
              AND (mcc_mnc_network IS NULL OR mcc_mnc_network = NEW.network_operator)
            ORDER BY mcc_mnc_network NULLS LAST
            LIMIT 1;
        END IF;
    END IF;
    -- end of network_sim_operator

    -- set mobile_provider_id (again?)
    IF ((TG_OP = 'UPDATE' AND OLD.STATUS = 'STARTED' AND NEW.STATUS = 'FINISHED')
        AND (NEW.time > (now() - INTERVAL '5 minutes'))) THEN -- update only new entries, skip old entries
        IF (NEW.network_operator is not NULL) THEN
            SELECT INTO NEW.mobile_network_id COALESCE(n.mapped_uid, n.uid)
            FROM mccmnc2name n
            WHERE NEW.network_operator = n.mccmnc
              AND (n.valid_from is null OR n.valid_from <= NEW.time)
              AND (n.valid_to is null or n.valid_to >= NEW.time)
              AND use_for_network = TRUE
            ORDER BY n.uid NULLS LAST
            LIMIT 1;
        END IF;

        -- set network_sim_operator
        IF (NEW.network_sim_operator is not NULL) THEN
            SELECT INTO NEW.mobile_sim_id COALESCE(n.mapped_uid, n.uid)
            FROM mccmnc2name n
            WHERE NEW.network_sim_operator = n.mccmnc
              AND (n.valid_from is null OR n.valid_from <= NEW.time)
              AND (n.valid_to is null or n.valid_to >= NEW.time)
              AND (NEW.network_sim_operator = n.mcc_mnc_network_mapping OR n.mcc_mnc_network_mapping is NULL)
              AND use_for_sim = TRUE
            ORDER BY n.uid NULLS LAST
            LIMIT 1;
        END IF;

    END IF;
    -- end of mobile_provider_id (again?)

    -- ignore automated tests from CLI
    IF ((TG_OP = 'UPDATE') AND (NEW.time > (now() - INTERVAL '5 minutes')) AND NEW.network_type = 97/*CLI*/ AND
        NEW.deleted = FALSE) THEN
        NEW.deleted = TRUE;
        NEW.comment = 'Exclude CLI per #211';
    END IF;


    -- plausibility check on distance from previous test
    IF ((TG_OP = 'UPDATE' AND OLD.STATUS = 'STARTED' AND NEW.STATUS = 'FINISHED')
        AND (NEW.time > (now() - INTERVAL '5 minutes'))
        AND NEW.geo_accuracy is not null
        AND NEW.geo_accuracy <= 10000) THEN

        SELECT INTO _tmp_uid uid
        FROM test
        WHERE client_id = NEW.client_id
          AND time < NEW.time -- #668 allow only past tests
          AND (NEW.time - INTERVAL '24 hours' < time)
          AND geo_accuracy is not null
          AND geo_accuracy <= 10000
        ORDER BY uid DESC
        LIMIT 1;

        IF _tmp_uid is not null THEN
            SELECT INTO NEW.dist_prev ST_DistanceSpheroid(t.geom4326,new.geom4326,'SPHEROID["WGS 84",6378137,298.257223563]')
             -- #668 improve geo precision for the calculation of the distance (in meters) to a previous test      
            FROM test t
            WHERE uid = _tmp_uid;
            IF NEW.dist_prev is not null THEN
                SELECT INTO _tmp_time time
                FROM test t
                WHERE uid = _tmp_uid;
                NEW.speed_prev = NEW.dist_prev / GREATEST(0.000001, EXTRACT(EPOCH FROM (NEW.time - _tmp_time))) *
                                 3.6; -- #668 speed in km/h and don't allow division by zero
            END IF;
        END IF;
    END IF;
    -- end of plausibility check

    -- set network_group_name and network_group_type based on network_type
    IF NEW.network_type > 0 -- AND NEW.time > (now() - INTERVAL '5 minutes') -- disabled due to #1857
    THEN
        SELECT group_name, type
        INTO NEW.network_group_name, NEW.network_group_type
        FROM network_type
        WHERE uid = NEW.network_type;
    END IF;

    -- set open_uuid
    -- #759 Finalisation loop mode
    IF (TG_OP = 'UPDATE' AND OLD.status = 'STARTED' AND NEW.status = 'FINISHED')
        -- disabled due to #1540: AND (NEW.time > (now() - INTERVAL '5 minutes')) -- update only new entries, skip old entries
    THEN
        _tmp_uuid = NULL;
        _tmp_geom4326 = NULL;
        SELECT open_uuid, geom4326 INTO _tmp_uuid, _tmp_geom4326
        FROM test -- find the open_uuid and geom4326
        WHERE (NEW.client_id = client_id)                                      -- of the current client
          AND (NEW.time > time)                                                -- thereby skipping the current entry (was: OLD.uid != uid)
          AND status = 'FINISHED'                                              -- of successful tests
          AND (NEW.time - time) < '4 hours'::INTERVAL                          -- within last 4 hours
          AND (NEW.time::DATE = time::DATE)                                    -- on the same day
          AND (NEW.network_group_type IS NOT DISTINCT FROM network_group_type) -- of the same technology (i.e. MOBILE, WLAN, LAN, CLI, NULL) - was: network_group_name
          AND (NEW.public_ip_asn IS NOT DISTINCT FROM public_ip_asn)           -- and of the same operator (including NULL)
        ORDER BY time DESC
        LIMIT 1; -- get only the latest test

        IF
                (_tmp_uuid IS NULL) -- previous query doesn't return any test
                OR -- OR
                (NEW.geom4326 IS NOT NULL AND _tmp_geom4326 IS NOT NULL
                    AND 
                    ST_DistanceSpheroid(new.geom4326,_tmp_geom4326,'SPHEROID["WGS 84",6378137,298.257223563]') 
                    >= 100) -- the distance to the last test >= 100m
        THEN
            _tmp_uuid = gen_random_uuid(); --generate new open_uuid
        END IF;
        NEW.open_uuid = _tmp_uuid;
    END IF;
    --end of set open_uuid

    -- plausibility check on movement during test
    IF (TG_OP = 'UPDATE' AND OLD.STATUS = 'STARTED' AND NEW.STATUS = 'FINISHED') THEN
        NEW.timestamp = now();

        SELECT INTO NEW.location_max_distance round(
                                                      ST_Distance( -- #668 improve geo precision for the calculation of the diagonal length (in meters) of the bounding box of one test
                                                              ST_SetSRID(ST_MakePoint(
                                                                                 ST_XMin(ST_Extent(ST_Transform(location, 4326))),
                                                                                 ST_YMin(ST_Extent(ST_Transform(location, 4326)))),
                                                                         4326)::geography,
                                                              ST_SetSRID(ST_MakePoint(
                                                                                 ST_XMax(ST_Extent(ST_Transform(location, 4326))),
                                                                                 ST_YMax(ST_Extent(ST_Transform(location, 4326)))),
                                                                         4326)::geography)
                                                  )
        FROM geo_location
        WHERE test_id = NEW.uid;
    END IF;

    -- plausibility check - Austrian networks outside Austria are not allowed #272
    IF ((NEW.time > (now() - INTERVAL '5 minutes')) -- update only new entries, skip old entries
        AND (
            (NEW.network_operator ILIKE '232%') -- test with Austrian mobile network operator
            )
        AND rmbt_get_distance_iso_a2(new.geom4326,'AT') > 35000 -- location is more than 35 km outside of the Austria shape
        ) 
    THEN
        NEW.status = 'UPDATE ERROR'; NEW.comment = 'Invalid location #272';
    END IF;

    -- ignore provider_id if location outside Austria
    IF ((NEW.time > (now() - INTERVAL '5 minutes')) -- update only new entries, skip old entries
        AND NEW.network_type in (97, 98, 99, 106, 107) -- CLI, LAN, WLAN, Ethernet, Bluetooth
        AND (
            (NEW.provider_id IS NOT NULL) -- Austrian operator
            )
        AND rmbt_get_distance_iso_a2(new.geom4326,'AT') > 3000 -- location is outside of the Austria shape with a tolerance of +3 km
        ) -- if
    -- TODO Do we really need such a long comment within the database here?
    THEN
        NEW.provider_id = NULL;
        NEW.comment = concat(
                'Not AT, no provider_id #664; ',
                NEW.comment, NULLIF(OLD.comment, NEW.comment));
    END IF;

    -- set mobile_provider_id2 (should replace the usage of mobile_provider_id)
    -- only for mobile tests in AT the value of the provider_id is taken
    -- because iOS doesn't supply MCC-MNC any more so the mobile statistics don't miss these tests
    IF (    NEW.provider_id IS NOT NULL
        AND NEW.network_group_type IS NOT DISTINCT FROM 'MOBILE'
        AND _country_location IS NOT DISTINCT FROM 'AT')
        -- only providers with MCC-MNC
        AND EXISTS (
            SELECT 1
            FROM provider p
            WHERE p.uid = NEW.provider_id
            AND p.mcc_mnc IS NOT NULL
        )
    THEN
        NEW.mobile_provider_id2 = NEW.provider_id;
    ELSE
        NEW.mobile_provider_id2 = NULL;
    END IF;

    -- ignore tests with model name 'unknown'
    -- TODO justified/relevant?
    IF ((NEW.time > (now() - INTERVAL '5 minutes')) -- update only new entries, skip old entries
        AND (NEW.model = 'unknown') -- model is 'unknown'
        )
    THEN
        NEW.status = 'UPDATE ERROR'; NEW.comment = 'Unknown model #356';
    END IF;

    -- implement test pinning (tests excluded from statistics)
    IF ((TG_OP = 'UPDATE' AND OLD.STATUS = 'STARTED' AND NEW.STATUS = 'FINISHED')
        AND (NEW.time > (now() - INTERVAL '5 minutes'))) -- update only new entries, skip old entries
    THEN -- Returns the uid of a previous similar test, otherwise -1. Also IF similar_test_uid = -1 then pinned = TRUE ELSE pinned=FALSE. Column similar_test_uid has a default value NULL, meaning the evaluation for similar test(s) wasn't performed yet.
        SELECT INTO NEW.similar_test_uid uid
        FROM test
        WHERE (similar_test_uid = -1 OR similar_test_uid IS NULL) -- consider only unsimilar or not yet evaluated tests
          AND NEW.open_uuid = open_uuid                           -- with the same open_uuid
          AND NEW.time > time
          AND (NEW.time - time) < '4 hours'::INTERVAL             -- in the last 4 hours
          AND NEW.public_ip_asn = public_ip_asn                   -- from the same network based on AS
          AND NEW.network_type = network_type                     -- of the same network_type
          AND CASE
                  WHEN (NEW.geom4326 IS NOT NULL AND NEW.geo_accuracy IS NOT NULL AND NEW.geo_accuracy < 2000
                      AND geom4326 IS NOT NULL AND geo_accuracy IS NOT NULL AND geo_accuracy < 2000)
                      THEN ST_DistanceSpheroid(new.geom4326,geom4326,'SPHEROID["WGS 84",6378137,298.257223563]')
                               < GREATEST(100, NEW.geo_accuracy) -- either within a radius of 100 m
                  ELSE TRUE -- or if no or inaccurate location, only other criteria count
            END
        ORDER BY time DESC -- consider the last, most previous test
        LIMIT 1;
        IF NEW.similar_test_uid IS NULL -- no similar test found
        then
            NEW.similar_test_uid = -1; -- indicate that we have searched for a similar test but nothing found
            NEW.pinned = TRUE; -- and set the pinned for the statistics
        ELSE
            NEW.pinned = FALSE; -- else in similar_test_uid the uid of a previous test is stored so the test shouldn't go into the statistics
        END IF;
    END IF; -- end test pinning

    --populate radio_signal_location for location and signal interpolation
    IF (TG_OP = 'UPDATE' AND OLD.STATUS = 'STARTED' AND NEW.STATUS = 'FINISHED') -- for ordinary tests
       OR
       ((TG_OP = 'INSERT' OR TG_OP = 'UPDATE') AND NEW.STATUS = 'SIGNAL')        -- for signal measurements
    then
       INSERT INTO radio_signal_location (last_signal_uuid, last_radio_signal_uuid, last_geo_location_uuid, next_geo_location_uuid, open_test_uuid, interpolated_location, "time") select (interpolate_radio_signal_location_v2 (new.open_test_uuid)).*
       ON CONFLICT DO NOTHING; -- conflicting rows will be ignored, the remaining will be inserted
    END IF; --location and signal interpolation

    --debugging, should be commented out for production
    --IF (TG_OP = 'INSERT') THEN RAISE warning 'rmbtdebug:TG_OP=% NEW=%',TG_OP, NEW; END IF;
    --IF (TG_OP = 'UPDATE') THEN RAISE warning 'rmbtdebug:TG_OP=% OLD=%',TG_OP, OLD; RAISE warning 'rmbtdebug:TG_OP=% NEW=%',TG_OP, NEW; END IF;
    --debugging end

    -- for debugging of deadlocks, according to https://wiki.postgresql.org/wiki/Lock_Monitoring and https://www.postgresql.org/docs/current/view-pg-locks.html
    FOR _rec IN SELECT pl.relation::regclass, *
        FROM pg_locks pl
        LEFT JOIN pg_stat_activity psa
        ON pl.pid = psa.pid where not pl.granted
    LOOP
        RAISE NOTICE 'BRKPT@triger_test() before RETURN NEW: pg_locks row= %', _rec;
    END LOOP;

    -- for general debug purposes
    RAISE NOTICE 'BRKPT@triger_test() before RETURN NEW: TG_OP= %, old.status= %, new.status= %, old.open_test_uuid= %, new.open_test_uuid= %, (test.)old.uuid= %, (test.)new.uuid= %', TG_OP, old.status, new.status, old.open_test_uuid, new.open_test_uuid, old.uuid, new.uuid;

    RETURN NEW;

    -- for general debug purposes (shouldn't be executed at all)
    RAISE NOTICE 'BRKPT@triger_test() before END - SHOULD NOT BE EXECUTED AT ALL!: TG_OP= %, old.status= %, new.status= %, old.open_test_uuid= %, new.open_test_uuid= %, (test.)old.uuid= %, (test.)new.uuid= %', TG_OP, old.status, new.status, old.open_test_uuid, new.open_test_uuid, old.uuid, new.uuid;

END;
$$;


ALTER FUNCTION public.trigger_test() OWNER TO rmbt;

--
-- Name: trigger_test_location(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trigger_test_location() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

    _min_accuracy CONSTANT integer := 2000;


BEGIN

    -- post process if location is updated
    IF (TG_OP = 'INSERT' OR NEW.location IS DISTINCT FROM OLD.location) then

        new.geom3857=st_setsrid(new.location,3857);   
        new.geom4326=st_transform(new.geom3857,4326);
       
        -- ignore if location is not accurate
        IF (NEW.location IS NULL OR NEW.geo_accuracy > _min_accuracy) THEN

        ELSE

            -- add dsr id (Austrian dauersiedlungsraum)
            SELECT dsr.id::INTEGER INTO NEW.settlement_type
            FROM dsr
            WHERE within(st_transform(NEW.geom3857, 31287), dsr.geom)
            LIMIT 1;

            -- add Austrian streets and railway (FRC 1,2,3,4,20,21)
            select q1.link_id,
                   linknet_names.link_name,
                   round(ST_DistanceSphere(q1.geom,
                                           ST_Transform(NEW.geom3857,
                                                        4326))) link_distance,
                   q1.frc,
                   q1.edge_id
            into NEW.link_id, NEW.link_name, NEW.link_distance, NEW.frc, NEW.edge_id
            from (SELECT linknet.link_id,
                         linknet.geom,
                         linknet.frc,
                         linknet.edge_id
                  FROM linknet
            -- optimize search by using boundary box on geometry
            -- bbox=ST_Expand(geom,0.01);
            WHERE ST_Transform(NEW.geom3857, 4326) && linknet.bbox

                  ORDER BY ST_Distance(linknet.geom,
                                       ST_Transform(NEW.geom3857,
                                                    4326)) ASC
                  LIMIT 1) as q1
                     LEFT JOIN linknet_names ON q1.link_id = linknet_names.link_id
             WHERE ST_DistanceSphere(q1.geom,
                                   ST_Transform(NEW.geom3857, 4326)) <=
                  10.0
            -- only if accuracy 10m or better
             AND NEW.geo_accuracy < 10.0
            -- only if GPS available
            AND (NEW.geo_provider ='' OR -- iOS (up to now)
                NEW.geo_provider IS NULL OR  -- iOS (planned)
                 NEW.geo_provider='gps');

            -- add BEV gkz (community identifier) and kg_nr (settlement identifier)
            BEGIN
                SELECT bev.gkz::INTEGER,
                       bev.kg_nr_int
                       INTO NEW.gkz_bev, NEW.kg_nr_bev
                FROM bev_vgd bev
                WHERE st_transform(NEW.geom3857, 31287) && bev.bbox
                AND within(st_transform(NEW.geom3857, 31287), bev.geom)
                LIMIT 1;
            EXCEPTION
                WHEN undefined_table THEN
                    -- just return NULL, but ignore missing database
                    RAISE NOTICE '%', SQLERRM;
            END;

            -- add SA gkz (community identifier)
            BEGIN
                SELECT sa.id::INTEGER INTO NEW.gkz_sa
                FROM statistik_austria_gem sa
                WHERE st_transform(NEW.geom3857, 31287) && sa.bbox
                AND
                within(st_transform(NEW.geom3857, 31287), sa.geom)
                LIMIT 1;
            EXCEPTION
                WHEN undefined_table THEN
                    -- just return NULL, but ignore missing database
                    RAISE NOTICE '%', SQLERRM;
            END;

            -- add land_cover (using Corine classification)
            -- Transform the point geometry to the LAEA coordinate system (3035)
            -- and pick the intersecting CLC code_18.
            BEGIN
                SELECT t.code_18::INTEGER
                    INTO NEW.land_cover
                    FROM clc18 t
                    WHERE t.shape && ST_Transform(NEW.geom3857, 3035)       
                        AND ST_Intersects(t.shape, ST_Transform(NEW.geom3857, 3035))
                    LIMIT 1;
            EXCEPTION
                WHEN undefined_table THEN
                    -- just return NULL, but ignore missing database
                    RAISE NOTICE '%', SQLERRM;
            END;

            -- add country code (country_location)
            IF (NEW.gkz_bev IS NOT NULL) THEN -- #659(mod): Austrian communities are more accurate/up-to-date for AT than admin_0_countries
                NEW.country_location = 'AT';
            ELSE
                BEGIN
                  new.country_location=rmbt_get_country_iso_a2(NEW.geom4326);
                  if (new.country_location='AT') then
                     new.country_location=null; -- #659: because admin_0_countries is inaccurate, do not allow to return 'AT'
                  end if;   
                end;        
            END IF;

            -- add altitude level from digital terrain model (DTM) #1203
            SELECT INTO NEW.dtm_level ST_Value(rast, (ST_Transform(ST_SetSRID(ST_MakePoint(NEW.geo_long, NEW.geo_lat), 4326), 31287)))
            FROM dhm
            WHERE st_intersects(rast, (ST_Transform(ST_SetSRID(ST_MakePoint(NEW.geo_long, NEW.geo_lat), 4326), 31287)));


           -- add atraster100 (Austrian 100m grid)
           BEGIN 
              SELECT atraster100.id::VARCHAR INTO NEW.atraster100
              FROM atraster100
              WHERE st_within(NEW.geom3857, atraster100.geom)
              LIMIT 1;
            EXCEPTION
                WHEN undefined_table THEN
                    -- just return NULL, but ignore missing database
                    RAISE NOTICE '%', SQLERRM;                   
            END; 
           
           -- add atraster250 (Austrian 250m grid)
           BEGIN 
              SELECT atraster250.id::VARCHAR INTO NEW.atraster250
              FROM atraster250
              WHERE st_within(NEW.geom3857, atraster250.geom)
              LIMIT 1;
            EXCEPTION
                WHEN undefined_table THEN
                    -- just return NULL, but ignore missing database
                    RAISE NOTICE '%', SQLERRM;                   
            END;
           
           
           
           
           
           
        END IF;

    END IF;
    -- end of location post processing

    RETURN NEW;


END;
$$;


ALTER FUNCTION public.trigger_test_location() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: _SCHEMA_VERSION; Type: TABLE; Schema: public; Owner: rmbt_control
--

CREATE TABLE public."_SCHEMA_VERSION" (
    installed_rank integer NOT NULL,
    version character varying(50),
    description character varying(200) NOT NULL,
    type character varying(20) NOT NULL,
    script character varying(1000) NOT NULL,
    checksum integer,
    installed_by character varying(100) NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL,
    execution_time integer NOT NULL,
    success boolean NOT NULL
);


ALTER TABLE public."_SCHEMA_VERSION" OWNER TO rmbt_control;

--
-- Name: admin_0_countries; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.admin_0_countries (
    gid integer NOT NULL,
    featurecla character varying(15),
    scalerank smallint,
    labelrank smallint,
    sovereignt character varying(32),
    sov_a3 character varying(3),
    adm0_dif smallint,
    level smallint,
    type character varying(17),
    tlc character varying(1),
    admin character varying(36),
    adm0_a3 character varying(3),
    geou_dif smallint,
    geounit character varying(36),
    gu_a3 character varying(3),
    su_dif smallint,
    subunit character varying(36),
    su_a3 character varying(3),
    brk_diff smallint,
    name character varying(29),
    name_long character varying(36),
    brk_a3 character varying(3),
    brk_name character varying(32),
    brk_group character varying(17),
    abbrev character varying(16),
    postal character varying(4),
    formal_en character varying(52),
    formal_fr character varying(35),
    name_ciawf character varying(45),
    note_adm0 character varying(16),
    note_brk character varying(63),
    name_sort character varying(36),
    name_alt character varying(19),
    mapcolor7 smallint,
    mapcolor8 smallint,
    mapcolor9 smallint,
    mapcolor13 smallint,
    pop_est double precision,
    pop_rank smallint,
    pop_year smallint,
    gdp_md integer,
    gdp_year smallint,
    economy character varying(26),
    income_grp character varying(23),
    fips_10 character varying(3),
    iso_a2 character varying(5),
    iso_a2_eh character varying(3),
    iso_a3 character varying(3),
    iso_a3_eh character varying(3),
    iso_n3 character varying(3),
    iso_n3_eh character varying(3),
    un_a3 character varying(4),
    wb_a2 character varying(3),
    wb_a3 character varying(3),
    woe_id integer,
    woe_id_eh integer,
    woe_note character varying(167),
    adm0_iso character varying(3),
    adm0_diff character varying(1),
    adm0_tlc character varying(3),
    adm0_a3_us character varying(3),
    adm0_a3_fr character varying(3),
    adm0_a3_ru character varying(3),
    adm0_a3_es character varying(3),
    adm0_a3_cn character varying(3),
    adm0_a3_tw character varying(3),
    adm0_a3_in character varying(3),
    adm0_a3_np character varying(3),
    adm0_a3_pk character varying(3),
    adm0_a3_de character varying(3),
    adm0_a3_gb character varying(3),
    adm0_a3_br character varying(3),
    adm0_a3_il character varying(3),
    adm0_a3_ps character varying(3),
    adm0_a3_sa character varying(3),
    adm0_a3_eg character varying(3),
    adm0_a3_ma character varying(3),
    adm0_a3_pt character varying(3),
    adm0_a3_ar character varying(3),
    adm0_a3_jp character varying(3),
    adm0_a3_ko character varying(3),
    adm0_a3_vn character varying(3),
    adm0_a3_tr character varying(3),
    adm0_a3_id character varying(3),
    adm0_a3_pl character varying(3),
    adm0_a3_gr character varying(3),
    adm0_a3_it character varying(3),
    adm0_a3_nl character varying(3),
    adm0_a3_se character varying(3),
    adm0_a3_bd character varying(3),
    adm0_a3_ua character varying(3),
    adm0_a3_un smallint,
    adm0_a3_wb smallint,
    continent character varying(23),
    region_un character varying(10),
    subregion character varying(25),
    region_wb character varying(26),
    name_len smallint,
    long_len smallint,
    abbrev_len smallint,
    tiny smallint,
    homepart smallint,
    min_zoom double precision,
    min_label double precision,
    max_label double precision,
    label_x double precision,
    label_y double precision,
    ne_id double precision,
    wikidataid character varying(8),
    name_ar character varying(72),
    name_bn character varying(148),
    name_de character varying(46),
    name_en character varying(44),
    name_es character varying(44),
    name_fa character varying(66),
    name_fr character varying(54),
    name_el character varying(86),
    name_he character varying(78),
    name_hi character varying(126),
    name_hu character varying(52),
    name_id character varying(46),
    name_it character varying(48),
    name_ja character varying(63),
    name_ko character varying(47),
    name_nl character varying(49),
    name_pl character varying(47),
    name_pt character varying(43),
    name_ru character varying(86),
    name_sv character varying(57),
    name_tr character varying(42),
    name_uk character varying(91),
    name_ur character varying(67),
    name_vi character varying(56),
    name_zh character varying(33),
    name_zht character varying(33),
    fclass_iso character varying(24),
    tlc_diff character varying(1),
    fclass_tlc character varying(21),
    fclass_us character varying(30),
    fclass_fr character varying(18),
    fclass_ru character varying(14),
    fclass_es character varying(18),
    fclass_cn character varying(24),
    fclass_tw character varying(15),
    fclass_in character varying(14),
    fclass_np character varying(24),
    fclass_pk character varying(15),
    fclass_de character varying(18),
    fclass_gb character varying(18),
    fclass_br character varying(12),
    fclass_il character varying(15),
    fclass_ps character varying(15),
    fclass_sa character varying(15),
    fclass_eg character varying(24),
    fclass_ma character varying(24),
    fclass_pt character varying(18),
    fclass_ar character varying(12),
    fclass_jp character varying(18),
    fclass_ko character varying(18),
    fclass_vn character varying(12),
    fclass_tr character varying(18),
    fclass_id character varying(24),
    fclass_pl character varying(18),
    fclass_gr character varying(18),
    fclass_it character varying(18),
    fclass_nl character varying(18),
    fclass_se character varying(18),
    fclass_bd character varying(24),
    fclass_ua character varying(18),
    geom public.geometry(MultiPolygon,4326)
);


ALTER TABLE public.admin_0_countries OWNER TO rmbt;

--
-- Name: admin_0_countries_gid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.admin_0_countries_gid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.admin_0_countries_gid_seq OWNER TO rmbt;

--
-- Name: admin_0_countries_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.admin_0_countries_gid_seq OWNED BY public.admin_0_countries.gid;


--
-- Name: device_map; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.device_map (
    uid integer NOT NULL,
    codename character varying(200),
    fullname character varying(200),
    source character varying(200),
    "timestamp" timestamp with time zone
);


ALTER TABLE public.device_map OWNER TO rmbt;

--
-- Name: android_device_map_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.android_device_map_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.android_device_map_uid_seq OWNER TO rmbt;

--
-- Name: android_device_map_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.android_device_map_uid_seq OWNED BY public.device_map.uid;


--
-- Name: as2provider; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.as2provider (
    uid integer NOT NULL,
    asn bigint,
    dns_part character varying(200),
    provider_id integer
);


ALTER TABLE public.as2provider OWNER TO rmbt;

--
-- Name: as2provider_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.as2provider_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.as2provider_uid_seq OWNER TO rmbt;

--
-- Name: as2provider_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.as2provider_uid_seq OWNED BY public.as2provider.uid;


--
-- Name: atraster; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.atraster (
    gid integer NOT NULL,
    id character varying(254),
    name character varying(254),
    geom public.geometry(MultiPolygon,3035)
);


ALTER TABLE public.atraster OWNER TO rmbt;

--
-- Name: atraster100; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.atraster100 (
    gid integer NOT NULL,
    id character varying(254),
    name character varying(254),
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE public.atraster100 OWNER TO rmbt;

--
-- Name: atraster100_gid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.atraster100_gid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.atraster100_gid_seq OWNER TO rmbt;

--
-- Name: atraster100_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.atraster100_gid_seq OWNED BY public.atraster100.gid;


--
-- Name: atraster250; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.atraster250 (
    gid integer NOT NULL,
    id character varying(254),
    name character varying(254),
    geom public.geometry(MultiPolygon,3857)
);


ALTER TABLE public.atraster250 OWNER TO rmbt;

--
-- Name: atraster250_gid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.atraster250_gid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.atraster250_gid_seq OWNER TO rmbt;

--
-- Name: atraster250_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.atraster250_gid_seq OWNED BY public.atraster250.gid;


--
-- Name: atraster_gid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.atraster_gid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.atraster_gid_seq OWNER TO rmbt;

--
-- Name: atraster_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.atraster_gid_seq OWNED BY public.atraster.gid;


--
-- Name: bb_atlas_festnetz_2025q4; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bb_atlas_festnetz_2025q4 (
    l000100v3 character varying(50),
    agg_id integer,
    infrastrukturanbieterin character varying(100),
    technik character varying(50),
    download double precision,
    upload double precision,
    bearbeitung_bbb timestamp with time zone
);


ALTER TABLE public.bb_atlas_festnetz_2025q4 OWNER TO postgres;

--
-- Name: bev_vgd; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.bev_vgd (
    gid integer NOT NULL,
    meridian smallint,
    gkz integer,
    bkz smallint,
    fa_nr smallint,
    bl_kz smallint,
    st_kz smallint,
    fl double precision,
    kg_nr character varying(6),
    kg character varying(50),
    pg character varying(50),
    pb character varying(50),
    fa character varying(50),
    gb_kz character varying(3),
    gb character varying(50),
    va_nr character varying(2),
    va character varying(50),
    bl character varying(50),
    st character varying(50),
    geom public.geometry(MultiPolygon,31287),
    kg_nr_int integer,
    bbox public.geometry
);


ALTER TABLE public.bev_vgd OWNER TO rmbt;

--
-- Name: bev_vgd_gid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.bev_vgd_gid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bev_vgd_gid_seq OWNER TO rmbt;

--
-- Name: bev_vgd_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.bev_vgd_gid_seq OWNED BY public.bev_vgd.gid;


--
-- Name: cell_location; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.cell_location (
    uid bigint NOT NULL,
    test_id bigint,
    "time" timestamp with time zone,
    primary_scrambling_code integer,
    time_ns bigint,
    open_test_uuid uuid,
    area_code bigint,
    location_id bigint
);


ALTER TABLE public.cell_location OWNER TO rmbt;

--
-- Name: COLUMN cell_location.open_test_uuid; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.cell_location.open_test_uuid IS 'open uuid of the test';


--
-- Name: cell_location_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.cell_location_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cell_location_uid_seq OWNER TO rmbt;

--
-- Name: cell_location_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.cell_location_uid_seq OWNED BY public.cell_location.uid;


--
-- Name: clc18; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.clc18 (
    objectid integer NOT NULL,
    code_18 character varying(3),
    remark character varying(20),
    area_ha double precision,
    id character varying(18),
    shape public.geometry(MultiPolygon,3035)
);


ALTER TABLE public.clc18 OWNER TO rmbt;

--
-- Name: clc18_legend; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.clc18_legend (
    grid_code integer,
    clc_code integer,
    label1 character varying,
    label2 character varying,
    label3 character varying,
    rgb character varying
);


ALTER TABLE public.clc18_legend OWNER TO postgres;

--
-- Name: clc18_objectid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.clc18_objectid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clc18_objectid_seq OWNER TO rmbt;

--
-- Name: clc18_objectid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.clc18_objectid_seq OWNED BY public.clc18.objectid;


--
-- Name: clc_legend; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.clc_legend (
    grid_code integer,
    clc_code integer,
    label1 character varying,
    label2 character varying,
    label3 character varying,
    rgb character varying
);


ALTER TABLE public.clc_legend OWNER TO rmbt;

--
-- Name: client; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.client (
    uid bigint NOT NULL,
    uuid uuid NOT NULL,
    client_type_id integer,
    "time" timestamp with time zone,
    sync_group_id integer,
    sync_code character varying(12),
    terms_and_conditions_accepted boolean DEFAULT false NOT NULL,
    sync_code_timestamp timestamp with time zone,
    blacklisted boolean DEFAULT false NOT NULL,
    terms_and_conditions_accepted_version integer,
    last_seen timestamp with time zone,
    terms_and_conditions_accepted_timestamp timestamp with time zone
);


ALTER TABLE public.client OWNER TO rmbt;

--
-- Name: client_type; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.client_type (
    uid integer NOT NULL,
    name character varying(200)
);


ALTER TABLE public.client_type OWNER TO rmbt;

--
-- Name: client_type_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.client_type_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.client_type_uid_seq OWNER TO rmbt;

--
-- Name: client_type_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.client_type_uid_seq OWNED BY public.client_type.uid;


--
-- Name: client_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.client_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.client_uid_seq OWNER TO rmbt;

--
-- Name: client_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.client_uid_seq OWNED BY public.client.uid;


--
-- Name: cov_bb_fixed; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.cov_bb_fixed AS
 SELECT row_number() OVER () AS uid,
    l000100v3 AS raster,
    infrastrukturanbieterin AS operator,
    technik AS technology,
    (download)::real AS dl_max_mbit,
    (upload)::real AS ul_max_mbit,
    to_char(bearbeitung_bbb, 'YYYY-MM-DD'::text) AS date
   FROM public.bb_atlas_festnetz_2025q4;


ALTER VIEW public.cov_bb_fixed OWNER TO postgres;

--
-- Name: cov_mno; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.cov_mno (
    uid integer NOT NULL,
    operator character varying(50),
    reference character varying(50),
    license character varying(50),
    rfc_date character varying(50),
    raster character varying(50),
    dl_normal bigint,
    ul_normal bigint,
    dl_max bigint,
    ul_max bigint
);


ALTER TABLE public.cov_mno OWNER TO rmbt;

--
-- Name: cov_mno_fn; Type: MATERIALIZED VIEW; Schema: public; Owner: postgres
--

CREATE MATERIALIZED VIEW public.cov_mno_fn AS
 SELECT cov_bb_fixed.operator,
    'BBfixed'::character varying AS reference,
    'CCBY4.0 BMLRT'::character varying AS license,
    substr(cov_bb_fixed.date, 0, 11) AS rfc_date,
    cov_bb_fixed.raster,
    NULL::bigint AS dl_normal,
    NULL::bigint AS ul_normal,
    ((cov_bb_fixed.dl_max_mbit * (1000000)::double precision))::bigint AS dl_max,
    ((cov_bb_fixed.ul_max_mbit * (1000000)::double precision))::bigint AS ul_max,
    cov_bb_fixed.technology
   FROM public.cov_bb_fixed
UNION
 SELECT cov_mno.operator,
    cov_mno.reference,
    cov_mno.license,
    cov_mno.rfc_date,
    cov_mno.raster,
    cov_mno.dl_normal,
    cov_mno.ul_normal,
    cov_mno.dl_max,
    cov_mno.ul_max,
    'mobile'::character varying AS technology
   FROM public.cov_mno
  WITH NO DATA;


ALTER MATERIALIZED VIEW public.cov_mno_fn OWNER TO postgres;

--
-- Name: cov_mno_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.cov_mno_uid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cov_mno_uid_seq OWNER TO rmbt;

--
-- Name: cov_mno_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.cov_mno_uid_seq OWNED BY public.cov_mno.uid;


--
-- Name: cov_visible_name; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.cov_visible_name (
    uid integer NOT NULL,
    operator character varying(200),
    visible_name character varying(50)
);


ALTER TABLE public.cov_visible_name OWNER TO rmbt;

--
-- Name: cov_visible_name_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.cov_visible_name_uid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cov_visible_name_uid_seq OWNER TO rmbt;

--
-- Name: cov_visible_name_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.cov_visible_name_uid_seq OWNED BY public.cov_visible_name.uid;


--
-- Name: dhm; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.dhm (
    rid integer NOT NULL,
    rast public.raster
);


ALTER TABLE public.dhm OWNER TO rmbt;

--
-- Name: dhm2_rid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.dhm2_rid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dhm2_rid_seq OWNER TO rmbt;

--
-- Name: dhm2_rid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.dhm2_rid_seq OWNED BY public.dhm.rid;


--
-- Name: dsr; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.dsr (
    gid integer NOT NULL,
    id numeric,
    name character varying(40),
    geom public.geometry(MultiPolygon,31287)
);


ALTER TABLE public.dsr OWNER TO rmbt;

--
-- Name: dsr_gid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.dsr_gid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.dsr_gid_seq OWNER TO rmbt;

--
-- Name: dsr_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.dsr_gid_seq OWNED BY public.dsr.gid;


--
-- Name: dtm10m; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.dtm10m (
    rid integer NOT NULL,
    rast public.raster
);


ALTER TABLE public.dtm10m OWNER TO postgres;

--
-- Name: fences; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fences (
    uid integer NOT NULL,
    open_test_uuid uuid NOT NULL,
    fence_id integer NOT NULL,
    technology_id integer,
    technology character varying(50),
    offset_ms integer NOT NULL,
    duration_ms double precision NOT NULL,
    radius integer,
    geom4326 public.geometry(Point,4326),
    avg_ping_ms double precision,
    fence_time timestamp with time zone NOT NULL,
    signal double precision,
    accuracy double precision,
    provider character varying(50),
    altitude double precision,
    bearing double precision,
    speed double precision
);


ALTER TABLE public.fences OWNER TO postgres;

--
-- Name: COLUMN fences.fence_time; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.fences.fence_time IS 'Timestamp of fence (derived from measurement time and offset)';


--
-- Name: COLUMN fences.altitude; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.fences.altitude IS 'altitude in meter';


--
-- Name: COLUMN fences.bearing; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.fences.bearing IS 'bearing in degrees from north';


--
-- Name: COLUMN fences.speed; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.fences.speed IS 'speed in meter per second';


--
-- Name: fences_uid_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.fences_uid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.fences_uid_seq OWNER TO postgres;

--
-- Name: fences_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.fences_uid_seq OWNED BY public.fences.uid;


--
-- Name: geo_location; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.geo_location (
    uid bigint NOT NULL,
    geo_location_uuid uuid DEFAULT gen_random_uuid(),
    open_test_uuid uuid NOT NULL,
    test_id bigint,
    time_ns bigint NOT NULL,
    "time" timestamp with time zone,
    accuracy double precision,
    altitude double precision,
    bearing double precision,
    speed double precision,
    provider character varying(20),
    geo_lat double precision,
    geo_long double precision,
    location public.geometry NOT NULL,
    mock_location boolean,
    geom4326 public.geometry(Point,4326),
    geom3857 public.geometry(Point,3857),
    CONSTRAINT enforce_geotype_location CHECK ((public.geometrytype(location) = 'POINT'::text)),
    CONSTRAINT enforce_srid_location CHECK ((public.st_srid(location) = 900913)),
    CONSTRAINT geo_location_location_check CHECK ((public.st_ndims(location) = 2))
);


ALTER TABLE public.geo_location OWNER TO rmbt;

--
-- Name: geo_location_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.geo_location_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.geo_location_uid_seq OWNER TO rmbt;

--
-- Name: geo_location_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.geo_location_uid_seq OWNED BY public.geo_location.uid;


--
-- Name: link4net; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.link4net (
    gid integer NOT NULL,
    fid numeric,
    link_id numeric,
    name1 character varying(254),
    name2 character varying(254),
    from_node numeric,
    to_node numeric,
    speedcar_t bigint,
    speedcar_b bigint,
    speedtru_t bigint,
    speedtru_b bigint,
    vmax_car_t bigint,
    vmax_car_b bigint,
    vmax_tru_t bigint,
    vmax_tru_b bigint,
    access_tow bigint,
    access_bkw bigint,
    length numeric,
    frc bigint,
    cap_tow numeric,
    cap_bkw numeric,
    lanes_tow numeric,
    lanes_bkw numeric,
    formofway bigint,
    brunnel bigint,
    maxheight numeric,
    maxwidth numeric,
    maxpress numeric,
    abuttercar bigint,
    abuttertru bigint,
    urban bigint,
    width numeric,
    int_level numeric,
    toll bigint,
    baustatus bigint,
    subnet_id bigint,
    oneway_car bigint,
    oneway_bk bigint,
    oneway_bus bigint,
    edge_id numeric,
    edgecat character varying(3),
    regcode character varying(31),
    sustainer character varying(19),
    dbcon bigint,
    geom public.geometry(MultiLineString,4326)
);


ALTER TABLE public.link4net OWNER TO rmbt;

--
-- Name: link4net_gid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.link4net_gid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.link4net_gid_seq OWNER TO rmbt;

--
-- Name: link4net_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.link4net_gid_seq OWNED BY public.link4net.gid;


--
-- Name: linknet; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.linknet (
    gid integer NOT NULL,
    link_id bigint,
    name1 character varying(254),
    name2 character varying(254),
    from_node bigint,
    to_node bigint,
    speedcar_t smallint,
    speedcar_b smallint,
    speedtru_t smallint,
    speedtru_b smallint,
    vmax_car_t smallint,
    vmax_car_b smallint,
    vmax_tru_t smallint,
    vmax_tru_b smallint,
    access_tow integer,
    access_bkw integer,
    length double precision,
    frc smallint,
    cap_tow bigint,
    cap_bkw bigint,
    lanes_tow double precision,
    lanes_bkw double precision,
    formofway smallint,
    brunnel smallint,
    maxheight double precision,
    maxwidth double precision,
    maxpress double precision,
    abuttercar smallint,
    abuttertru smallint,
    urban integer,
    width double precision,
    int_level double precision,
    toll smallint,
    baustatus smallint,
    subnet_id integer,
    oneway_car smallint,
    oneway_bk smallint,
    oneway_bus smallint,
    edge_id numeric,
    edgecat character varying(3),
    regcode character varying(31),
    sustainer character varying(19),
    dbcon smallint,
    geom public.geometry(MultiLineString,4326),
    bbox public.geometry
);


ALTER TABLE public.linknet OWNER TO rmbt;

--
-- Name: linknet_gid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.linknet_gid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.linknet_gid_seq OWNER TO rmbt;

--
-- Name: linknet_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.linknet_gid_seq OWNED BY public.linknet.gid;


--
-- Name: linknet_names; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.linknet_names (
    link_id integer NOT NULL,
    link_name character varying
);


ALTER TABLE public.linknet_names OWNER TO rmbt;

--
-- Name: mcc2country; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.mcc2country (
    mcc character varying(3) NOT NULL,
    country character varying(2) NOT NULL
);


ALTER TABLE public.mcc2country OWNER TO rmbt;

--
-- Name: mccmnc2name; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.mccmnc2name (
    uid integer NOT NULL,
    mccmnc character varying(7) NOT NULL,
    valid_from date DEFAULT '0001-01-01'::date,
    valid_to date DEFAULT '9999-12-31'::date,
    country character varying(2),
    name character varying(200) NOT NULL,
    shortname character varying(100),
    use_for_sim boolean DEFAULT true,
    use_for_network boolean DEFAULT true,
    mcc_mnc_network_mapping character varying(10),
    comment character varying(200),
    mapped_uid integer
);


ALTER TABLE public.mccmnc2name OWNER TO rmbt;

--
-- Name: mccmnc2name_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.mccmnc2name_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mccmnc2name_uid_seq OWNER TO rmbt;

--
-- Name: mccmnc2name_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.mccmnc2name_uid_seq OWNED BY public.mccmnc2name.uid;


--
-- Name: mccmnc2provider; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.mccmnc2provider (
    uid integer NOT NULL,
    mcc_mnc_sim character varying(10),
    provider_id integer NOT NULL,
    mcc_mnc_network character varying(10),
    valid_from date,
    valid_to date
);


ALTER TABLE public.mccmnc2provider OWNER TO rmbt;

--
-- Name: mccmnc2provider_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.mccmnc2provider_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.mccmnc2provider_uid_seq OWNER TO rmbt;

--
-- Name: mccmnc2provider_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.mccmnc2provider_uid_seq OWNED BY public.mccmnc2provider.uid;


--
-- Name: ne_10m_admin_0_countries; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.ne_10m_admin_0_countries (
    gid integer NOT NULL,
    scalerank smallint,
    featurecla character varying(30),
    labelrank double precision,
    sovereignt character varying(32),
    sov_a3 character varying(3),
    adm0_dif double precision,
    level double precision,
    type character varying(17),
    admin character varying(36),
    adm0_a3 character varying(3),
    geou_dif double precision,
    geounit character varying(36),
    gu_a3 character varying(3),
    su_dif double precision,
    subunit character varying(36),
    su_a3 character varying(3),
    brk_diff double precision,
    name character varying(36),
    name_long character varying(36),
    brk_a3 character varying(3),
    brk_name character varying(36),
    brk_group character varying(30),
    abbrev character varying(13),
    postal character varying(4),
    formal_en character varying(52),
    formal_fr character varying(35),
    name_ciawf character varying(45),
    note_adm0 character varying(22),
    note_brk character varying(164),
    name_sort character varying(36),
    name_alt character varying(38),
    mapcolor7 double precision,
    mapcolor8 double precision,
    mapcolor9 double precision,
    mapcolor13 double precision,
    pop_est double precision,
    pop_rank double precision,
    gdp_md_est double precision,
    pop_year double precision,
    lastcensus double precision,
    gdp_year double precision,
    economy character varying(26),
    income_grp character varying(23),
    wikipedia double precision,
    fips_10_ character varying(3),
    iso_a2 character varying(5),
    iso_a3 character varying(3),
    iso_a3_eh character varying(3),
    iso_n3 character varying(3),
    un_a3 character varying(4),
    wb_a2 character varying(3),
    wb_a3 character varying(3),
    woe_id double precision,
    woe_id_eh double precision,
    woe_note character varying(190),
    adm0_a3_is character varying(3),
    adm0_a3_us character varying(3),
    adm0_a3_un double precision,
    adm0_a3_wb double precision,
    continent character varying(23),
    region_un character varying(23),
    subregion character varying(25),
    region_wb character varying(26),
    name_len double precision,
    long_len double precision,
    abbrev_len double precision,
    tiny double precision,
    homepart double precision,
    min_zoom double precision,
    min_label double precision,
    max_label double precision,
    geom public.geometry(MultiPolygon,900913),
    geom4326 public.geometry(MultiPolygon,4326)
);


ALTER TABLE public.ne_10m_admin_0_countries OWNER TO rmbt;

--
-- Name: ne_10m_admin_0_countries_gid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.ne_10m_admin_0_countries_gid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ne_10m_admin_0_countries_gid_seq OWNER TO rmbt;

--
-- Name: ne_10m_admin_0_countries_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.ne_10m_admin_0_countries_gid_seq OWNED BY public.ne_10m_admin_0_countries.gid;


--
-- Name: network_type; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.network_type (
    uid integer NOT NULL,
    name character varying(200) NOT NULL,
    group_name character varying NOT NULL,
    aggregate character varying[],
    type character varying NOT NULL,
    technology_order integer DEFAULT 0 NOT NULL,
    min_speed_download_kbps integer,
    max_speed_download_kbps integer,
    min_speed_upload_kbps integer,
    max_speed_upload_kbps integer
);


ALTER TABLE public.network_type OWNER TO rmbt;

--
-- Name: network_type_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.network_type_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.network_type_uid_seq OWNER TO rmbt;

--
-- Name: network_type_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.network_type_uid_seq OWNED BY public.network_type.uid;


--
-- Name: news; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.news (
    uid integer NOT NULL,
    "time" timestamp with time zone NOT NULL,
    title_en text,
    title_de text,
    text_en text,
    text_de text,
    active boolean DEFAULT false NOT NULL,
    force boolean DEFAULT false NOT NULL,
    plattform text,
    max_software_version_code integer,
    min_software_version_code integer,
    uuid uuid,
    start_time timestamp with time zone DEFAULT now() NOT NULL,
    end_time timestamp with time zone
);


ALTER TABLE public.news OWNER TO rmbt;

--
-- Name: news_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.news_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.news_uid_seq OWNER TO rmbt;

--
-- Name: news_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.news_uid_seq OWNED BY public.news.uid;


--
-- Name: news_view; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.news_view AS
 SELECT uid,
    title_en,
    title_de,
    text_en,
    text_de,
    plattform,
    active,
    force,
    max_software_version_code,
    min_software_version_code,
    uuid,
    start_time,
    end_time,
    "time",
    public.getnewsstatus(active, start_time, end_time) AS status
   FROM public.news n;


ALTER VIEW public.news_view OWNER TO postgres;

--
-- Name: next_link_uid_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.next_link_uid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.next_link_uid_seq OWNER TO postgres;

--
-- Name: ping; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.ping (
    uid bigint NOT NULL,
    test_id bigint,
    value bigint,
    value_server bigint,
    time_ns bigint,
    open_test_uuid uuid
);


ALTER TABLE public.ping OWNER TO rmbt;

--
-- Name: COLUMN ping.open_test_uuid; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.ping.open_test_uuid IS 'open uuid of the test';


--
-- Name: ping_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.ping_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ping_uid_seq OWNER TO rmbt;

--
-- Name: ping_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.ping_uid_seq OWNED BY public.ping.uid;


--
-- Name: provider; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.provider (
    uid integer NOT NULL,
    name character varying(200),
    mcc_mnc character varying(10),
    shortname character varying(100),
    map_filter boolean NOT NULL
);


ALTER TABLE public.provider OWNER TO rmbt;

--
-- Name: provider_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.provider_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.provider_uid_seq OWNER TO rmbt;

--
-- Name: provider_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.provider_uid_seq OWNED BY public.provider.uid;


--
-- Name: qoe_classification; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.qoe_classification (
    uid integer NOT NULL,
    category character varying(30) NOT NULL,
    dl_4 double precision NOT NULL,
    dl_3 double precision NOT NULL,
    dl_2 double precision NOT NULL,
    ul_4 double precision NOT NULL,
    ul_3 double precision NOT NULL,
    ul_2 double precision NOT NULL,
    ping_4 double precision NOT NULL,
    ping_3 double precision NOT NULL,
    ping_2 double precision NOT NULL
);


ALTER TABLE public.qoe_classification OWNER TO rmbt;

--
-- Name: qoe_classification_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.qoe_classification_uid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.qoe_classification_uid_seq OWNER TO rmbt;

--
-- Name: qoe_classification_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.qoe_classification_uid_seq OWNED BY public.qoe_classification.uid;


--
-- Name: qos_test_desc; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.qos_test_desc (
    uid integer NOT NULL,
    desc_key text,
    value text,
    lang text
);


ALTER TABLE public.qos_test_desc OWNER TO rmbt;

--
-- Name: qos_test_desc_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.qos_test_desc_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.qos_test_desc_uid_seq OWNER TO rmbt;

--
-- Name: qos_test_desc_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.qos_test_desc_uid_seq OWNED BY public.qos_test_desc.uid;


--
-- Name: qos_test_objective; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.qos_test_objective (
    uid integer NOT NULL,
    test public.qostest NOT NULL,
    test_class integer,
    test_server integer,
    concurrency_group integer DEFAULT 0 NOT NULL,
    test_desc text,
    test_summary text,
    param json DEFAULT '{}'::json NOT NULL,
    results json
);


ALTER TABLE public.qos_test_objective OWNER TO rmbt;

--
-- Name: qos_test_objective_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.qos_test_objective_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.qos_test_objective_uid_seq OWNER TO rmbt;

--
-- Name: qos_test_objective_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.qos_test_objective_uid_seq OWNED BY public.qos_test_objective.uid;


--
-- Name: qos_test_result; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.qos_test_result (
    uid integer NOT NULL,
    test_uid bigint,
    qos_test_uid bigint,
    success_count integer DEFAULT 0 NOT NULL,
    failure_count integer DEFAULT 0 NOT NULL,
    implausible boolean DEFAULT false,
    deleted boolean DEFAULT false,
    result json
);


ALTER TABLE public.qos_test_result OWNER TO rmbt;

--
-- Name: qos_test_result_b; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.qos_test_result_b (
    uid integer NOT NULL,
    test_uid bigint,
    qos_test_uid bigint,
    success_count integer DEFAULT 0 NOT NULL,
    failure_count integer DEFAULT 0 NOT NULL,
    implausible boolean DEFAULT false,
    deleted boolean DEFAULT false,
    result jsonb
);


ALTER TABLE public.qos_test_result_b OWNER TO rmbt;

--
-- Name: qos_test_result_b_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.qos_test_result_b_uid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.qos_test_result_b_uid_seq OWNER TO rmbt;

--
-- Name: qos_test_result_b_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.qos_test_result_b_uid_seq OWNED BY public.qos_test_result_b.uid;


--
-- Name: qos_test_result_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.qos_test_result_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.qos_test_result_uid_seq OWNER TO rmbt;

--
-- Name: qos_test_result_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.qos_test_result_uid_seq OWNED BY public.qos_test_result.uid;


--
-- Name: qos_test_type_desc; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.qos_test_type_desc (
    uid integer NOT NULL,
    test public.qostest,
    test_desc text,
    test_name text
);


ALTER TABLE public.qos_test_type_desc OWNER TO rmbt;

--
-- Name: qos_test_type_desc_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.qos_test_type_desc_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.qos_test_type_desc_uid_seq OWNER TO rmbt;

--
-- Name: qos_test_type_desc_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.qos_test_type_desc_uid_seq OWNED BY public.qos_test_type_desc.uid;


--
-- Name: radio_cell; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.radio_cell (
    uid integer NOT NULL,
    uuid uuid NOT NULL,
    open_test_uuid uuid,
    technology character varying(10),
    mnc integer,
    mcc integer,
    location_id bigint,
    primary_scrambling_code integer,
    registered boolean,
    channel_number integer,
    active boolean,
    primary_data_subscription character varying(30),
    cell_state character varying(15),
    area_code bigint
);


ALTER TABLE public.radio_cell OWNER TO rmbt;

--
-- Name: COLUMN radio_cell.registered; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.radio_cell.registered IS 'do not use, obsolete';


--
-- Name: COLUMN radio_cell.cell_state; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.radio_cell.cell_state IS 'Connection status of cell: "primary","secondary","none"';


--
-- Name: radio_cell_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.radio_cell_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.radio_cell_uid_seq OWNER TO rmbt;

--
-- Name: radio_cell_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.radio_cell_uid_seq OWNED BY public.radio_cell.uid;


--
-- Name: radio_signal; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.radio_signal (
    uid integer NOT NULL,
    radio_signal_uuid uuid DEFAULT gen_random_uuid(),
    open_test_uuid uuid NOT NULL,
    cell_uuid uuid NOT NULL,
    time_ns bigint,
    time_ns_last bigint,
    "time" timestamp with time zone,
    signal_strength integer,
    lte_rsrp integer,
    lte_rsrq integer,
    lte_rssnr integer,
    lte_cqi integer,
    bit_error_rate integer,
    timing_advance integer,
    wifi_link_speed integer,
    network_type_id integer
);


ALTER TABLE public.radio_signal OWNER TO rmbt;

--
-- Name: radio_signal_location; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.radio_signal_location (
    uid bigint NOT NULL,
    last_signal_uuid uuid,
    last_radio_signal_uuid uuid,
    last_geo_location_uuid uuid NOT NULL,
    open_test_uuid uuid NOT NULL,
    interpolated_location public.geometry NOT NULL,
    "time" timestamp with time zone NOT NULL,
    next_geo_location_uuid uuid,
    CONSTRAINT location_not_null_for_uuid CHECK (((last_geo_location_uuid IS NOT NULL) AND (interpolated_location IS NOT NULL))),
    CONSTRAINT xor_signals_not_null CHECK ((((last_signal_uuid IS NOT NULL) AND (last_radio_signal_uuid IS NULL)) OR ((last_signal_uuid IS NULL) AND (last_radio_signal_uuid IS NOT NULL))))
);


ALTER TABLE public.radio_signal_location OWNER TO rmbt;

--
-- Name: COLUMN radio_signal_location."time"; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.radio_signal_location."time" IS 'equals test.time + time_ns';


--
-- Name: radio_signal_location_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.radio_signal_location_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.radio_signal_location_uid_seq OWNER TO rmbt;

--
-- Name: radio_signal_location_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.radio_signal_location_uid_seq OWNED BY public.radio_signal_location.uid;


--
-- Name: radio_signal_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.radio_signal_uid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.radio_signal_uid_seq OWNER TO rmbt;

--
-- Name: radio_signal_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.radio_signal_uid_seq OWNED BY public.radio_signal.uid;


--
-- Name: settings; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.settings (
    uid integer NOT NULL,
    key character varying NOT NULL,
    lang character(2),
    value character varying NOT NULL
);


ALTER TABLE public.settings OWNER TO rmbt;

--
-- Name: settings_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.settings_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.settings_uid_seq OWNER TO rmbt;

--
-- Name: settings_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.settings_uid_seq OWNED BY public.settings.uid;


--
-- Name: signal; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.signal (
    uid bigint NOT NULL,
    signal_uuid uuid DEFAULT gen_random_uuid(),
    test_id bigint,
    open_test_uuid uuid NOT NULL,
    "time" timestamp with time zone,
    time_ns bigint,
    signal_strength integer,
    network_type_id integer,
    wifi_link_speed integer,
    gsm_bit_error_rate integer,
    wifi_rssi integer,
    lte_rsrp integer,
    lte_rsrq integer,
    lte_rssnr integer,
    lte_cqi integer
);


ALTER TABLE public.signal OWNER TO rmbt;

--
-- Name: signal_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.signal_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.signal_uid_seq OWNER TO rmbt;

--
-- Name: signal_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.signal_uid_seq OWNED BY public.signal.uid;


--
-- Name: speed; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.speed (
    open_test_uuid uuid NOT NULL,
    items jsonb,
    uid bigint
);


ALTER TABLE public.speed OWNER TO rmbt;

--
-- Name: TABLE speed; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON TABLE public.speed IS 'speed items of all tests';


--
-- Name: COLUMN speed.open_test_uuid; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.speed.open_test_uuid IS 'uuid of the test';


--
-- Name: COLUMN speed.items; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.speed.items IS 'speed items of the test';


--
-- Name: speed_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.speed_uid_seq
    START WITH 60000000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.speed_uid_seq OWNER TO rmbt;

--
-- Name: speed_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.speed_uid_seq OWNED BY public.speed.uid;


--
-- Name: statistik_austria_gem; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.statistik_austria_gem (
    gid integer NOT NULL,
    id character varying(254),
    name character varying(254),
    geom public.geometry(MultiPolygon,31287),
    bbox public.geometry
);


ALTER TABLE public.statistik_austria_gem OWNER TO rmbt;

--
-- Name: statistik_austria_gem_gid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.statistik_austria_gem_gid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.statistik_austria_gem_gid_seq OWNER TO rmbt;

--
-- Name: statistik_austria_gem_gid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.statistik_austria_gem_gid_seq OWNED BY public.statistik_austria_gem.gid;


--
-- Name: status_obsolete; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.status_obsolete (
    uid integer NOT NULL,
    client_uuid uuid NOT NULL,
    "time" timestamp with time zone,
    plattform character varying(50),
    model character varying(50),
    product character varying(50),
    device character varying(50),
    software_version_code character varying(50),
    api_level character varying(10),
    ip character varying(50),
    age bigint,
    lat double precision,
    long double precision,
    accuracy double precision,
    altitude double precision,
    speed double precision,
    provider character varying(50),
    signalnetworktypeid double precision,
    signalwifirssi double precision,
    signalltersrp double precision,
    signalltersrq double precision,
    signalrssi double precision,
    signalltecqi double precision,
    signaltime bigint
);


ALTER TABLE public.status_obsolete OWNER TO rmbt;

--
-- Name: status_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.status_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.status_uid_seq OWNER TO rmbt;

--
-- Name: status_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.status_uid_seq OWNED BY public.status_obsolete.uid;


--
-- Name: sync_group; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.sync_group (
    uid integer NOT NULL,
    tstamp timestamp with time zone NOT NULL
);


ALTER TABLE public.sync_group OWNER TO rmbt;

--
-- Name: sync_group_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.sync_group_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sync_group_uid_seq OWNER TO rmbt;

--
-- Name: sync_group_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.sync_group_uid_seq OWNED BY public.sync_group.uid;


--
-- Name: test; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.test (
    uid bigint NOT NULL,
    uuid uuid,
    client_id bigint,
    client_version character varying(50),
    client_name character varying,
    client_language character varying(10),
    token character varying(500),
    server_id integer,
    port integer,
    use_ssl boolean DEFAULT false NOT NULL,
    "time" timestamp with time zone,
    speed_upload integer,
    speed_download integer,
    ping_shortest bigint,
    encryption character varying(50),
    client_public_ip character varying(100),
    plattform character varying(200),
    os_version character varying(100),
    api_level character varying(10),
    device character varying(200),
    model character varying(200),
    product character varying(200),
    phone_type integer,
    data_state integer,
    network_country character varying(10),
    network_operator character varying(10),
    network_operator_name character varying(200),
    network_sim_country character varying(10),
    network_sim_operator character varying(10),
    network_sim_operator_name character varying(200),
    wifi_ssid character varying(200),
    wifi_bssid character varying(200),
    wifi_network_id character varying(200),
    duration integer,
    num_threads integer,
    status character varying(100),
    timezone character varying(200),
    bytes_download bigint,
    bytes_upload bigint,
    nsec_download bigint,
    nsec_upload bigint,
    server_ip character varying(100),
    client_software_version character varying(100),
    geo_lat double precision,
    geo_long double precision,
    network_type integer,
    location public.geometry,
    signal_strength integer,
    software_revision character varying(200),
    client_test_counter bigint,
    nat_type character varying(200),
    client_previous_test_status character varying(200),
    public_ip_asn bigint,
    speed_upload_log double precision,
    speed_download_log double precision,
    total_bytes_download bigint,
    total_bytes_upload bigint,
    wifi_link_speed integer,
    public_ip_rdns character varying(200),
    public_ip_as_name character varying(200),
    test_slot integer,
    provider_id integer,
    network_is_roaming boolean,
    ping_shortest_log double precision,
    run_ndt boolean,
    num_threads_requested integer,
    client_public_ip_anonymized character varying(100),
    zip_code integer,
    geo_provider character varying(200),
    geo_accuracy double precision,
    deleted boolean DEFAULT false NOT NULL,
    comment text,
    open_uuid uuid,
    client_time timestamp with time zone,
    zip_code_geo integer,
    mobile_provider_id integer,
    roaming_type integer,
    open_test_uuid uuid,
    country_asn character(2),
    country_location character(2),
    test_if_bytes_download bigint,
    test_if_bytes_upload bigint,
    implausible boolean DEFAULT false NOT NULL,
    testdl_if_bytes_download bigint,
    testdl_if_bytes_upload bigint,
    testul_if_bytes_download bigint,
    testul_if_bytes_upload bigint,
    country_geoip character(2),
    location_max_distance integer,
    location_max_distance_gps integer,
    network_group_name character varying(200),
    network_group_type character varying(200),
    time_dl_ns bigint,
    time_ul_ns bigint,
    num_threads_ul integer,
    "timestamp" timestamp without time zone DEFAULT now(),
    source_ip character varying(50),
    lte_rsrp integer,
    lte_rsrq integer,
    mobile_network_id integer,
    mobile_sim_id integer,
    dist_prev double precision,
    speed_prev double precision,
    tag character varying(512),
    ping_median bigint,
    ping_median_log double precision,
    source_ip_anonymized character varying(50),
    client_ip_local character varying(50),
    client_ip_local_anonymized character varying(50),
    client_ip_local_type character varying(50),
    hidden_code character varying(8),
    origin uuid,
    developer_code character varying(8),
    dual_sim boolean,
    gkz_obsolete integer,
    android_permissions json,
    dual_sim_detection_method character varying(50),
    pinned boolean DEFAULT true NOT NULL,
    similar_test_uid bigint,
    user_server_selection boolean,
    radio_band smallint,
    sim_count smallint,
    time_qos_ns bigint,
    test_nsec_qos bigint,
    channel_number integer,
    gkz_bev_obsolete integer,
    gkz_sa_obsolete integer,
    kg_nr_bev integer,
    land_cover_obsolete integer,
    link_distance_obsolete integer,
    link_id_obsolete integer,
    settlement_type_obsolete integer,
    link_name_obsolete character varying,
    frc_obsolete smallint,
    edge_id_obsolete numeric,
    geo_location_uuid uuid,
    last_client_status character varying(50),
    last_qos_status character varying(50),
    test_error_cause character varying,
    last_sequence_number integer,
    submission_retry_count integer,
    measurement_type_flag character varying(50),
    geom3857 public.geometry(Point,3857),
    geom4326 public.geometry(Point,4326),
    temperature double precision,
    coverage boolean,
    referrer character varying(2048),
    cell_area_code bigint,
    cell_location_id bigint,
    fences_count integer,
    mobile_provider_id2 integer,
    nat_type_v4 character varying(100),
    nat_type_v6 character varying(100),
    apn character varying(100),
    termination_cause character varying(100),
    CONSTRAINT enforce_dims_location CHECK ((public.st_ndims(location) = 2)),
    CONSTRAINT enforce_geotype_location CHECK (((public.geometrytype(location) = 'POINT'::text) OR (location IS NULL))),
    CONSTRAINT enforce_srid_location CHECK ((public.st_srid(location) = 900913)),
    CONSTRAINT test_speed_download_noneg CHECK ((speed_download >= 0)),
    CONSTRAINT test_speed_upload_noneg CHECK ((speed_upload >= 0))
);


ALTER TABLE public.test OWNER TO rmbt;

--
-- Name: COLUMN test.server_id; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.test.server_id IS 'id of test server used';


--
-- Name: COLUMN test.coverage; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.test.coverage IS 'True if measurement is a coverage verification test';


--
-- Name: COLUMN test.referrer; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.test.referrer IS 'referrer for iframe tests, eg. "https://www.rtr.at/abcde/x.hml"';


--
-- Name: COLUMN test.fences_count; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.test.fences_count IS 'number of fences; NULL = no fences';


--
-- Name: COLUMN test.termination_cause; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.test.termination_cause IS 'termination cause reported by the client, e.g. "ended by network change"';


--
-- Name: test10mdtm_rid_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.test10mdtm_rid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test10mdtm_rid_seq OWNER TO postgres;

--
-- Name: test10mdtm_rid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.test10mdtm_rid_seq OWNED BY public.dtm10m.rid;


--
-- Name: test_location; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.test_location (
    uid bigint NOT NULL,
    open_test_uuid uuid NOT NULL,
    geo_location_uuid uuid NOT NULL,
    location public.geometry NOT NULL,
    geo_long double precision,
    geo_lat double precision,
    geo_accuracy double precision,
    geo_provider character varying,
    kg_nr_bev integer,
    gkz_bev integer,
    gkz_sa integer,
    land_cover integer,
    settlement_type integer,
    link_id integer,
    link_name character varying,
    link_distance integer,
    frc smallint,
    edge_id numeric,
    country_location character(2),
    dtm_level integer,
    geom3857 public.geometry(Point,3857),
    geom4326 public.geometry(Point,4326),
    atraster100 character varying(16),
    atraster250 character varying(18),
    CONSTRAINT enforce_dims_location2 CHECK ((public.st_ndims(location) = 2)),
    CONSTRAINT enforce_geotype_location2 CHECK ((public.geometrytype(location) = 'POINT'::text)),
    CONSTRAINT settlement_type_check2 CHECK (((settlement_type > 0) AND (settlement_type < 4)))
);


ALTER TABLE public.test_location OWNER TO rmbt;

--
-- Name: COLUMN test_location.atraster100; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.test_location.atraster100 IS 'Austrian 100m grid ID';


--
-- Name: COLUMN test_location.atraster250; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.test_location.atraster250 IS 'Austrian 250m grid ID';


--
-- Name: test_location_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.test_location_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_location_uid_seq OWNER TO rmbt;

--
-- Name: test_location_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.test_location_uid_seq OWNED BY public.test_location.uid;


--
-- Name: test_loopmode; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.test_loopmode (
    uid integer NOT NULL,
    test_uuid uuid,
    client_uuid uuid,
    max_movement integer,
    max_delay integer,
    max_tests integer,
    test_counter integer,
    loop_uuid uuid,
    cert_mode boolean
);


ALTER TABLE public.test_loopmode OWNER TO rmbt;

--
-- Name: test_loopmode_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.test_loopmode_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_loopmode_uid_seq OWNER TO rmbt;

--
-- Name: test_loopmode_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.test_loopmode_uid_seq OWNED BY public.test_loopmode.uid;


--
-- Name: test_ndt; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.test_ndt (
    uid integer NOT NULL,
    test_id bigint,
    s2cspd double precision,
    c2sspd double precision,
    avgrtt double precision,
    main text,
    stat text,
    diag text,
    time_ns bigint,
    time_end_ns bigint,
    open_test_uuid uuid
);


ALTER TABLE public.test_ndt OWNER TO rmbt;

--
-- Name: test_ndt_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.test_ndt_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_ndt_uid_seq OWNER TO rmbt;

--
-- Name: test_ndt_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.test_ndt_uid_seq OWNED BY public.test_ndt.uid;


--
-- Name: test_server; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.test_server (
    uid integer NOT NULL,
    name character varying(200),
    web_address character varying(500),
    port integer,
    port_ssl integer,
    city character varying,
    country character varying,
    geo_lat double precision,
    geo_long double precision,
    location public.geometry(Point,900913),
    web_address_ipv4 character varying(200),
    web_address_ipv6 character varying(200),
    server_type character varying(10),
    priority integer DEFAULT 0 NOT NULL,
    weight integer DEFAULT 1 NOT NULL,
    active boolean DEFAULT true NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying,
    selectable boolean DEFAULT false NOT NULL,
    countries character varying[] DEFAULT '{dev}'::character varying[] NOT NULL,
    node character varying,
    archived boolean DEFAULT false NOT NULL,
    coverage boolean,
    CONSTRAINT enforce_dims_location CHECK ((public.st_ndims(location) = 2)),
    CONSTRAINT enforce_geotype_location CHECK (((public.geometrytype(location) = 'POINT'::text) OR (location IS NULL))),
    CONSTRAINT enforce_srid_location CHECK ((public.st_srid(location) = 900913))
);


ALTER TABLE public.test_server OWNER TO rmbt;

--
-- Name: COLUMN test_server.coverage; Type: COMMENT; Schema: public; Owner: rmbt
--

COMMENT ON COLUMN public.test_server.coverage IS 'True if server is for coverage verification tests';


--
-- Name: test_server_quality; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.test_server_quality (
    uid bigint NOT NULL,
    server_uuid uuid NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    protocol integer NOT NULL,
    reachable boolean NOT NULL,
    latency_ms double precision
);


ALTER TABLE public.test_server_quality OWNER TO postgres;

--
-- Name: test_server_qos_view; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.test_server_qos_view AS
 WITH latest_entries AS (
         SELECT DISTINCT ON (test_server_quality.server_uuid, test_server_quality.protocol) test_server_quality.server_uuid,
            test_server_quality.protocol,
            test_server_quality.reachable,
            test_server_quality.latency_ms
           FROM public.test_server_quality
          ORDER BY test_server_quality.server_uuid, test_server_quality.protocol, test_server_quality."timestamp" DESC
        ), stats_24h AS (
         SELECT test_server_quality.server_uuid,
            test_server_quality.protocol,
            max(test_server_quality.latency_ms) AS max_latency_ms,
            min(test_server_quality.latency_ms) AS min_latency_ms,
            round(((100.0 * (count(*) FILTER (WHERE test_server_quality.reachable))::numeric) / (NULLIF(count(*), 0))::numeric), 2) AS reachability_pct,
            count(*) AS measurement_count
           FROM public.test_server_quality
          WHERE (test_server_quality."timestamp" > (now() - '24:00:00'::interval))
          GROUP BY test_server_quality.server_uuid, test_server_quality.protocol
        )
 SELECT ts.name,
    latest.protocol,
    latest.reachable,
    latest.latency_ms,
    stats.max_latency_ms,
    stats.min_latency_ms,
    stats.reachability_pct,
    stats.measurement_count
   FROM ((latest_entries latest
     JOIN public.test_server ts ON ((ts.uuid = latest.server_uuid)))
     LEFT JOIN stats_24h stats ON (((stats.server_uuid = latest.server_uuid) AND (stats.protocol = latest.protocol))))
  ORDER BY latest.reachable DESC, latest.latency_ms;


ALTER VIEW public.test_server_qos_view OWNER TO postgres;

--
-- Name: test_server_quality_uid_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.test_server_quality_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_server_quality_uid_seq OWNER TO postgres;

--
-- Name: test_server_quality_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.test_server_quality_uid_seq OWNED BY public.test_server_quality.uid;


--
-- Name: test_server_types; Type: TABLE; Schema: public; Owner: rmbt
--

CREATE TABLE public.test_server_types (
    test_server_uid bigint NOT NULL,
    server_type character varying(60) NOT NULL,
    uid integer NOT NULL,
    port integer,
    port_ssl integer,
    encrypted boolean DEFAULT false NOT NULL
);


ALTER TABLE public.test_server_types OWNER TO rmbt;

--
-- Name: test_server_types_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.test_server_types_uid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_server_types_uid_seq OWNER TO rmbt;

--
-- Name: test_server_types_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.test_server_types_uid_seq OWNED BY public.test_server_types.uid;


--
-- Name: test_server_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.test_server_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_server_uid_seq OWNER TO rmbt;

--
-- Name: test_server_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.test_server_uid_seq OWNED BY public.test_server.uid;


--
-- Name: test_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.test_uid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.test_uid_seq OWNER TO rmbt;

--
-- Name: test_uid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: rmbt
--

ALTER SEQUENCE public.test_uid_seq OWNED BY public.test.uid;


--
-- Name: tl2_uid_seq; Type: SEQUENCE; Schema: public; Owner: rmbt
--

CREATE SEQUENCE public.tl2_uid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tl2_uid_seq OWNER TO rmbt;

--
-- Name: v_dl_bandwidth_per_minute; Type: VIEW; Schema: public; Owner: rmbt
--

CREATE VIEW public.v_dl_bandwidth_per_minute AS
 SELECT date_trunc('minute'::text, "time") AS time_minute,
    count(*) AS test_count,
    (sum(speed_download) / 1000) AS bandwidth_dl_mbps
   FROM public.test
  WHERE ((status)::text = 'FINISHED'::text)
  GROUP BY (date_trunc('minute'::text, "time"))
  ORDER BY (date_trunc('minute'::text, "time")) DESC;


ALTER VIEW public.v_dl_bandwidth_per_minute OWNER TO rmbt;

--
-- Name: v_get_replication_delay; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_get_replication_delay AS
 SELECT pid,
    usesysid,
    usename,
    application_name,
    client_addr,
    client_hostname,
    client_port,
    backend_start,
    backend_xmin,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag,
    sync_priority,
    sync_state
   FROM public.get_replication_delay() get_replication_delay(pid, usesysid, usename, application_name, client_addr, client_hostname, client_port, backend_start, backend_xmin, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, write_lag, flush_lag, replay_lag, sync_priority, sync_state, reply_time);


ALTER VIEW public.v_get_replication_delay OWNER TO postgres;

--
-- Name: v_radio_signal_location; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_radio_signal_location AS
 SELECT radio_signal_location.uid,
    radio_signal_location.last_signal_uuid,
    radio_signal_location.last_radio_signal_uuid,
    radio_signal_location.last_geo_location_uuid,
    radio_signal_location.open_test_uuid,
    radio_signal_location.interpolated_location,
    geo_location.accuracy AS geo_accuracy,
    radio_signal_location."time",
    COALESCE((radio_signal.lte_rsrp + 10), radio_signal.signal_strength, (signal.lte_rsrp + 10), signal.signal_strength) AS merged_signal,
    COALESCE(radio_signal.network_type_id, signal.network_type_id) AS network_type,
    test.deleted,
    test.implausible,
    test.status
   FROM ((((public.radio_signal_location
     LEFT JOIN public.radio_signal ON ((radio_signal_location.last_radio_signal_uuid = radio_signal.radio_signal_uuid)))
     LEFT JOIN public.signal ON ((radio_signal_location.last_signal_uuid = signal.signal_uuid)))
     JOIN public.geo_location ON ((radio_signal_location.last_geo_location_uuid = geo_location.geo_location_uuid)))
     JOIN public.test ON ((radio_signal.open_test_uuid = test.open_test_uuid)));


ALTER VIEW public.v_radio_signal_location OWNER TO postgres;

--
-- Name: v_test_metrics; Type: VIEW; Schema: public; Owner: rmbt
--

CREATE VIEW public.v_test_metrics AS
 SELECT ((100 * count(network_type)) / GREATEST(count(*), (1)::bigint)) AS network_type_perc,
    ((100 * count(public_ip_asn)) / GREATEST(count(*), (1)::bigint)) AS autonomous_system_perc,
    ((100 * count(geo_location_uuid)) / GREATEST(count(*), (1)::bigint)) AS geo_location_perc
   FROM public.test
  WHERE ("time" > (now() - '00:30:00'::interval));


ALTER VIEW public.v_test_metrics OWNER TO rmbt;

--
-- Name: xt_test_obsolete; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.xt_test_obsolete (
    uuid uuid,
    client_id bigint,
    client_version character varying(10),
    client_name character varying,
    client_language character varying(10),
    token character varying(500),
    server_id integer,
    port integer,
    use_ssl boolean,
    "time" timestamp with time zone,
    speed_upload integer,
    speed_download integer,
    ping_shortest bigint,
    encryption character varying(50),
    client_public_ip character varying(100),
    plattform character varying(200),
    os_version character varying(100),
    api_level character varying(10),
    device character varying(200),
    model character varying(200),
    product character varying(200),
    phone_type integer,
    data_state integer,
    network_country character varying(10),
    network_operator character varying(10),
    network_operator_name character varying(200),
    network_sim_country character varying(10),
    network_sim_operator character varying(10),
    network_sim_operator_name character varying(200),
    wifi_ssid character varying(200),
    wifi_bssid character varying(200),
    wifi_network_id character varying(200),
    duration integer,
    num_threads integer,
    status character varying(100),
    timezone character varying(200),
    bytes_download bigint,
    bytes_upload bigint,
    nsec_download bigint,
    nsec_upload bigint,
    server_ip character varying(100),
    client_software_version character varying(100),
    geo_lat double precision,
    geo_long double precision,
    network_type integer,
    location public.geometry,
    signal_strength integer,
    software_revision character varying(200),
    client_test_counter bigint,
    nat_type character varying(200),
    client_previous_test_status character varying(200),
    public_ip_asn bigint,
    speed_upload_log double precision,
    speed_download_log double precision,
    total_bytes_download bigint,
    total_bytes_upload bigint,
    wifi_link_speed integer,
    public_ip_rdns character varying(200),
    public_ip_as_name character varying(200),
    test_slot integer,
    provider_id integer,
    network_is_roaming boolean,
    ping_shortest_log double precision,
    run_ndt boolean,
    num_threads_requested integer,
    client_public_ip_anonymized character varying(100),
    zip_code integer,
    geo_provider character varying(200),
    geo_accuracy double precision,
    deleted boolean,
    comment text,
    open_uuid uuid,
    client_time timestamp with time zone,
    zip_code_geo integer,
    mobile_provider_id integer,
    roaming_type integer,
    open_test_uuid uuid,
    country_asn character(2),
    country_location character(2),
    test_if_bytes_download bigint,
    test_if_bytes_upload bigint,
    implausible boolean,
    testdl_if_bytes_download bigint,
    testdl_if_bytes_upload bigint,
    testul_if_bytes_download bigint,
    testul_if_bytes_upload bigint,
    country_geoip character(2),
    location_max_distance integer,
    location_max_distance_gps integer,
    network_group_name character varying(200),
    network_group_type character varying(200),
    time_dl_ns bigint,
    time_ul_ns bigint,
    num_threads_ul integer,
    "timestamp" timestamp without time zone,
    source_ip character varying(50),
    lte_rsrp integer,
    lte_rsrq integer,
    mobile_network_id integer,
    mobile_sim_id integer,
    dist_prev double precision,
    speed_prev double precision,
    tag character varying(512),
    ping_median bigint,
    ping_median_log double precision,
    source_ip_anonymized character varying(50),
    client_ip_local character varying(50),
    client_ip_local_anonymized character varying(50),
    client_ip_local_type character varying(50),
    hidden_code character varying(8),
    origin uuid,
    developer_code character varying(8),
    dual_sim boolean,
    gkz_obsolete integer,
    android_permissions json,
    dual_sim_detection_method character varying(50),
    pinned boolean,
    similar_test_uid bigint,
    user_server_selection boolean,
    radio_band smallint,
    sim_count smallint,
    time_qos_ns bigint,
    test_nsec_qos bigint,
    channel_number integer,
    gkz_bev_obsolete integer,
    gkz_sa_obsolete integer,
    kg_nr_bev integer,
    land_cover_obsolete integer,
    cell_area_code integer,
    cell_location_id integer,
    link_distance_obsolete integer,
    link_id_obsolete integer,
    settlement_type_obsolete integer,
    link_name_obsolete character varying,
    frc_obsolete smallint,
    edge_id_obsolete numeric,
    geo_location_uuid uuid,
    last_client_status character varying(50),
    last_qos_status character varying(50),
    test_error_cause character varying,
    last_sequence_number integer,
    submission_retry_count integer,
    measurement_type_flag character varying(50)
);


ALTER TABLE public.xt_test_obsolete OWNER TO postgres;

--
-- Name: admin_0_countries gid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.admin_0_countries ALTER COLUMN gid SET DEFAULT nextval('public.admin_0_countries_gid_seq'::regclass);


--
-- Name: as2provider uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.as2provider ALTER COLUMN uid SET DEFAULT nextval('public.as2provider_uid_seq'::regclass);


--
-- Name: atraster gid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.atraster ALTER COLUMN gid SET DEFAULT nextval('public.atraster_gid_seq'::regclass);


--
-- Name: atraster100 gid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.atraster100 ALTER COLUMN gid SET DEFAULT nextval('public.atraster100_gid_seq'::regclass);


--
-- Name: atraster250 gid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.atraster250 ALTER COLUMN gid SET DEFAULT nextval('public.atraster250_gid_seq'::regclass);


--
-- Name: bev_vgd gid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.bev_vgd ALTER COLUMN gid SET DEFAULT nextval('public.bev_vgd_gid_seq'::regclass);


--
-- Name: cell_location uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.cell_location ALTER COLUMN uid SET DEFAULT nextval('public.cell_location_uid_seq'::regclass);


--
-- Name: clc18 objectid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.clc18 ALTER COLUMN objectid SET DEFAULT nextval('public.clc18_objectid_seq'::regclass);


--
-- Name: client uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.client ALTER COLUMN uid SET DEFAULT nextval('public.client_uid_seq'::regclass);


--
-- Name: client_type uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.client_type ALTER COLUMN uid SET DEFAULT nextval('public.client_type_uid_seq'::regclass);


--
-- Name: cov_mno uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.cov_mno ALTER COLUMN uid SET DEFAULT nextval('public.cov_mno_uid_seq'::regclass);


--
-- Name: cov_visible_name uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.cov_visible_name ALTER COLUMN uid SET DEFAULT nextval('public.cov_visible_name_uid_seq'::regclass);


--
-- Name: device_map uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.device_map ALTER COLUMN uid SET DEFAULT nextval('public.android_device_map_uid_seq'::regclass);


--
-- Name: dhm rid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.dhm ALTER COLUMN rid SET DEFAULT nextval('public.dhm2_rid_seq'::regclass);


--
-- Name: dsr gid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.dsr ALTER COLUMN gid SET DEFAULT nextval('public.dsr_gid_seq'::regclass);


--
-- Name: dtm10m rid; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dtm10m ALTER COLUMN rid SET DEFAULT nextval('public.test10mdtm_rid_seq'::regclass);


--
-- Name: fences uid; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fences ALTER COLUMN uid SET DEFAULT nextval('public.fences_uid_seq'::regclass);


--
-- Name: geo_location uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.geo_location ALTER COLUMN uid SET DEFAULT nextval('public.geo_location_uid_seq'::regclass);


--
-- Name: link4net gid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.link4net ALTER COLUMN gid SET DEFAULT nextval('public.link4net_gid_seq'::regclass);


--
-- Name: linknet gid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.linknet ALTER COLUMN gid SET DEFAULT nextval('public.linknet_gid_seq'::regclass);


--
-- Name: mccmnc2name uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.mccmnc2name ALTER COLUMN uid SET DEFAULT nextval('public.mccmnc2name_uid_seq'::regclass);


--
-- Name: mccmnc2provider uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.mccmnc2provider ALTER COLUMN uid SET DEFAULT nextval('public.mccmnc2provider_uid_seq'::regclass);


--
-- Name: ne_10m_admin_0_countries gid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.ne_10m_admin_0_countries ALTER COLUMN gid SET DEFAULT nextval('public.ne_10m_admin_0_countries_gid_seq'::regclass);


--
-- Name: network_type uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.network_type ALTER COLUMN uid SET DEFAULT nextval('public.network_type_uid_seq'::regclass);


--
-- Name: news uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.news ALTER COLUMN uid SET DEFAULT nextval('public.news_uid_seq'::regclass);


--
-- Name: ping uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.ping ALTER COLUMN uid SET DEFAULT nextval('public.ping_uid_seq'::regclass);


--
-- Name: provider uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.provider ALTER COLUMN uid SET DEFAULT nextval('public.provider_uid_seq'::regclass);


--
-- Name: qoe_classification uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qoe_classification ALTER COLUMN uid SET DEFAULT nextval('public.qoe_classification_uid_seq'::regclass);


--
-- Name: qos_test_desc uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_desc ALTER COLUMN uid SET DEFAULT nextval('public.qos_test_desc_uid_seq'::regclass);


--
-- Name: qos_test_objective uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_objective ALTER COLUMN uid SET DEFAULT nextval('public.qos_test_objective_uid_seq'::regclass);


--
-- Name: qos_test_result uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_result ALTER COLUMN uid SET DEFAULT nextval('public.qos_test_result_uid_seq'::regclass);


--
-- Name: qos_test_result_b uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_result_b ALTER COLUMN uid SET DEFAULT nextval('public.qos_test_result_b_uid_seq'::regclass);


--
-- Name: qos_test_type_desc uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_type_desc ALTER COLUMN uid SET DEFAULT nextval('public.qos_test_type_desc_uid_seq'::regclass);


--
-- Name: radio_cell uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_cell ALTER COLUMN uid SET DEFAULT nextval('public.radio_cell_uid_seq'::regclass);


--
-- Name: radio_signal uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal ALTER COLUMN uid SET DEFAULT nextval('public.radio_signal_uid_seq'::regclass);


--
-- Name: radio_signal_location uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal_location ALTER COLUMN uid SET DEFAULT nextval('public.radio_signal_location_uid_seq'::regclass);


--
-- Name: settings uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.settings ALTER COLUMN uid SET DEFAULT nextval('public.settings_uid_seq'::regclass);


--
-- Name: signal uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.signal ALTER COLUMN uid SET DEFAULT nextval('public.signal_uid_seq'::regclass);


--
-- Name: speed uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.speed ALTER COLUMN uid SET DEFAULT nextval('public.speed_uid_seq'::regclass);


--
-- Name: statistik_austria_gem gid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.statistik_austria_gem ALTER COLUMN gid SET DEFAULT nextval('public.statistik_austria_gem_gid_seq'::regclass);


--
-- Name: status_obsolete uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.status_obsolete ALTER COLUMN uid SET DEFAULT nextval('public.status_uid_seq'::regclass);


--
-- Name: sync_group uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.sync_group ALTER COLUMN uid SET DEFAULT nextval('public.sync_group_uid_seq'::regclass);


--
-- Name: test uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test ALTER COLUMN uid SET DEFAULT nextval('public.test_uid_seq'::regclass);


--
-- Name: test_location uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_location ALTER COLUMN uid SET DEFAULT nextval('public.test_location_uid_seq'::regclass);


--
-- Name: test_loopmode uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_loopmode ALTER COLUMN uid SET DEFAULT nextval('public.test_loopmode_uid_seq'::regclass);


--
-- Name: test_ndt uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_ndt ALTER COLUMN uid SET DEFAULT nextval('public.test_ndt_uid_seq'::regclass);


--
-- Name: test_server uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_server ALTER COLUMN uid SET DEFAULT nextval('public.test_server_uid_seq'::regclass);


--
-- Name: test_server_quality uid; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.test_server_quality ALTER COLUMN uid SET DEFAULT nextval('public.test_server_quality_uid_seq'::regclass);


--
-- Name: test_server_types uid; Type: DEFAULT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_server_types ALTER COLUMN uid SET DEFAULT nextval('public.test_server_types_uid_seq'::regclass);


--
-- Name: _SCHEMA_VERSION _SCHEMA_VERSION_pk; Type: CONSTRAINT; Schema: public; Owner: rmbt_control
--

ALTER TABLE ONLY public."_SCHEMA_VERSION"
    ADD CONSTRAINT "_SCHEMA_VERSION_pk" PRIMARY KEY (installed_rank);


--
-- Name: admin_0_countries admin_0_countries_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.admin_0_countries
    ADD CONSTRAINT admin_0_countries_pkey PRIMARY KEY (gid);


--
-- Name: device_map android_device_map_codename_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.device_map
    ADD CONSTRAINT android_device_map_codename_key UNIQUE (codename);


--
-- Name: device_map android_device_map_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.device_map
    ADD CONSTRAINT android_device_map_pkey PRIMARY KEY (uid);


--
-- Name: as2provider as2provider_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.as2provider
    ADD CONSTRAINT as2provider_pkey PRIMARY KEY (uid);


--
-- Name: atraster100 atraster100_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.atraster100
    ADD CONSTRAINT atraster100_pkey PRIMARY KEY (gid);


--
-- Name: atraster250 atraster250_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.atraster250
    ADD CONSTRAINT atraster250_pkey PRIMARY KEY (gid);


--
-- Name: atraster atraster_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.atraster
    ADD CONSTRAINT atraster_pkey PRIMARY KEY (gid);


--
-- Name: bev_vgd bev_vgd_kg_nr_int; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.bev_vgd
    ADD CONSTRAINT bev_vgd_kg_nr_int UNIQUE (kg_nr_int);


--
-- Name: bev_vgd bev_vgd_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.bev_vgd
    ADD CONSTRAINT bev_vgd_pkey PRIMARY KEY (gid);


--
-- Name: cell_location cell_location_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.cell_location
    ADD CONSTRAINT cell_location_pkey PRIMARY KEY (uid);


--
-- Name: clc18 clc18_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.clc18
    ADD CONSTRAINT clc18_pkey PRIMARY KEY (objectid);


--
-- Name: client client_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT client_pkey PRIMARY KEY (uid);


--
-- Name: client client_sync_code; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT client_sync_code UNIQUE (sync_code);


--
-- Name: client_type client_type_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.client_type
    ADD CONSTRAINT client_type_pkey PRIMARY KEY (uid);


--
-- Name: client client_uuid_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT client_uuid_key UNIQUE (uuid);


--
-- Name: cov_mno cov_mno_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.cov_mno
    ADD CONSTRAINT cov_mno_pkey PRIMARY KEY (uid);


--
-- Name: cov_visible_name cov_visible_name_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.cov_visible_name
    ADD CONSTRAINT cov_visible_name_pkey PRIMARY KEY (uid);


--
-- Name: device_map device_map_fullname_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.device_map
    ADD CONSTRAINT device_map_fullname_key UNIQUE (fullname);


--
-- Name: dhm dhm2_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.dhm
    ADD CONSTRAINT dhm2_pkey PRIMARY KEY (rid);


--
-- Name: dsr dsr_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.dsr
    ADD CONSTRAINT dsr_pkey PRIMARY KEY (gid);


--
-- Name: fences fences_open_test_uuid_fence_id_idx; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fences
    ADD CONSTRAINT fences_open_test_uuid_fence_id_idx UNIQUE (open_test_uuid, fence_id);


--
-- Name: fences fences_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fences
    ADD CONSTRAINT fences_pkey PRIMARY KEY (uid);


--
-- Name: geo_location geo_location_geo_location_uuid_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.geo_location
    ADD CONSTRAINT geo_location_geo_location_uuid_key UNIQUE (geo_location_uuid);


--
-- Name: link4net link4net_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.link4net
    ADD CONSTRAINT link4net_pkey PRIMARY KEY (gid);


--
-- Name: linknet_names linknet_names_pk; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.linknet_names
    ADD CONSTRAINT linknet_names_pk PRIMARY KEY (link_id);


--
-- Name: linknet linknet_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.linknet
    ADD CONSTRAINT linknet_pkey PRIMARY KEY (gid);


--
-- Name: geo_location location_uid_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.geo_location
    ADD CONSTRAINT location_uid_pkey PRIMARY KEY (uid);


--
-- Name: mcc2country mcc2country_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.mcc2country
    ADD CONSTRAINT mcc2country_pkey PRIMARY KEY (mcc);


--
-- Name: mccmnc2name mccmnc2name_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.mccmnc2name
    ADD CONSTRAINT mccmnc2name_pkey PRIMARY KEY (uid);


--
-- Name: mccmnc2provider mccmnc2provider_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.mccmnc2provider
    ADD CONSTRAINT mccmnc2provider_pkey PRIMARY KEY (uid);


--
-- Name: ne_10m_admin_0_countries ne_10m_admin_0_countries_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.ne_10m_admin_0_countries
    ADD CONSTRAINT ne_10m_admin_0_countries_pkey PRIMARY KEY (gid);


--
-- Name: network_type network_type_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.network_type
    ADD CONSTRAINT network_type_pkey PRIMARY KEY (uid);


--
-- Name: ping ping_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.ping
    ADD CONSTRAINT ping_pkey PRIMARY KEY (uid);


--
-- Name: provider provider_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.provider
    ADD CONSTRAINT provider_pkey PRIMARY KEY (uid);


--
-- Name: qoe_classification qoe_classification_pk; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qoe_classification
    ADD CONSTRAINT qoe_classification_pk PRIMARY KEY (uid);


--
-- Name: qos_test_desc qos_test_desc_desc_key_lang_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_desc
    ADD CONSTRAINT qos_test_desc_desc_key_lang_key UNIQUE (desc_key, lang);


--
-- Name: qos_test_desc qos_test_desc_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_desc
    ADD CONSTRAINT qos_test_desc_pkey PRIMARY KEY (uid);


--
-- Name: qos_test_objective qos_test_objective_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_objective
    ADD CONSTRAINT qos_test_objective_pkey PRIMARY KEY (uid);


--
-- Name: qos_test_result qos_test_result_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_result
    ADD CONSTRAINT qos_test_result_pkey PRIMARY KEY (uid);


--
-- Name: qos_test_result_b qos_test_resultb_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_result_b
    ADD CONSTRAINT qos_test_resultb_pkey PRIMARY KEY (uid);


--
-- Name: qos_test_type_desc qos_test_type_desc_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_type_desc
    ADD CONSTRAINT qos_test_type_desc_pkey PRIMARY KEY (uid);


--
-- Name: qos_test_type_desc qos_test_type_desc_test_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_type_desc
    ADD CONSTRAINT qos_test_type_desc_test_key UNIQUE (test);


--
-- Name: radio_cell radio_cell_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_cell
    ADD CONSTRAINT radio_cell_pkey PRIMARY KEY (uid);


--
-- Name: radio_signal_location radio_signal_location_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal_location
    ADD CONSTRAINT radio_signal_location_pkey PRIMARY KEY (uid);


--
-- Name: radio_signal radio_signal_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal
    ADD CONSTRAINT radio_signal_pkey PRIMARY KEY (uid);


--
-- Name: radio_signal radio_signal_signal_uuid_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal
    ADD CONSTRAINT radio_signal_signal_uuid_key UNIQUE (radio_signal_uuid);


--
-- Name: signal radio_signal_uid_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.signal
    ADD CONSTRAINT radio_signal_uid_pkey PRIMARY KEY (uid);


--
-- Name: settings settings_key_lang_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_key_lang_key UNIQUE (key, lang);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (uid);


--
-- Name: test settlement_type_check; Type: CHECK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE public.test
    ADD CONSTRAINT settlement_type_check CHECK (((settlement_type_obsolete > 0) AND (settlement_type_obsolete < 4))) NOT VALID;


--
-- Name: signal signal_signal_uuid_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.signal
    ADD CONSTRAINT signal_signal_uuid_key UNIQUE (signal_uuid);


--
-- Name: speed speed_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.speed
    ADD CONSTRAINT speed_pkey PRIMARY KEY (open_test_uuid);


--
-- Name: speed speed_uid_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.speed
    ADD CONSTRAINT speed_uid_key UNIQUE (uid);


--
-- Name: statistik_austria_gem statistik_austria_gem_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.statistik_austria_gem
    ADD CONSTRAINT statistik_austria_gem_pkey PRIMARY KEY (gid);


--
-- Name: status_obsolete status_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.status_obsolete
    ADD CONSTRAINT status_pkey PRIMARY KEY (uid);


--
-- Name: sync_group sync_group_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.sync_group
    ADD CONSTRAINT sync_group_pkey PRIMARY KEY (uid);


--
-- Name: dtm10m test10mdtm_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.dtm10m
    ADD CONSTRAINT test10mdtm_pkey PRIMARY KEY (rid);


--
-- Name: test_location test_location_open_test_uuid_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_location
    ADD CONSTRAINT test_location_open_test_uuid_key UNIQUE (open_test_uuid);


--
-- Name: test_location test_location_uid_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_location
    ADD CONSTRAINT test_location_uid_pkey PRIMARY KEY (uid);


--
-- Name: test_loopmode test_loopmode_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_loopmode
    ADD CONSTRAINT test_loopmode_pkey PRIMARY KEY (uid);


--
-- Name: test_loopmode test_loopmode_test_uuid_fkey_unique; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_loopmode
    ADD CONSTRAINT test_loopmode_test_uuid_fkey_unique UNIQUE (test_uuid);


--
-- Name: test_ndt test_ndt_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_ndt
    ADD CONSTRAINT test_ndt_pkey PRIMARY KEY (uid);


--
-- Name: test_ndt test_ndt_test_id_unique; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_ndt
    ADD CONSTRAINT test_ndt_test_id_unique UNIQUE (test_id);


--
-- Name: test test_open_test_uuid_unique; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test
    ADD CONSTRAINT test_open_test_uuid_unique UNIQUE (open_test_uuid);


--
-- Name: test test_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test
    ADD CONSTRAINT test_pkey PRIMARY KEY (uid);


--
-- Name: test_server test_server_pkey; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_server
    ADD CONSTRAINT test_server_pkey PRIMARY KEY (uid);


--
-- Name: test_server_quality test_server_quality_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.test_server_quality
    ADD CONSTRAINT test_server_quality_pkey PRIMARY KEY (uid);


--
-- Name: test_server test_server_uuid_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_server
    ADD CONSTRAINT test_server_uuid_key UNIQUE (uuid);


--
-- Name: test test_uuid_key; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test
    ADD CONSTRAINT test_uuid_key UNIQUE (uuid);


--
-- Name: news uid; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.news
    ADD CONSTRAINT uid PRIMARY KEY (uid);


--
-- Name: radio_signal_location unique_radio_signal_and_geo; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal_location
    ADD CONSTRAINT unique_radio_signal_and_geo UNIQUE (last_radio_signal_uuid, last_geo_location_uuid);


--
-- Name: radio_signal_location unique_signal_and_geo; Type: CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal_location
    ADD CONSTRAINT unique_signal_and_geo UNIQUE (last_signal_uuid, last_geo_location_uuid);


--
-- Name: _SCHEMA_VERSION_s_idx; Type: INDEX; Schema: public; Owner: rmbt_control
--

CREATE INDEX "_SCHEMA_VERSION_s_idx" ON public."_SCHEMA_VERSION" USING btree (success);


--
-- Name: admin_0_countries_geom_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX admin_0_countries_geom_idx ON public.admin_0_countries USING gist (geom);


--
-- Name: as2provider_provider_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX as2provider_provider_id_idx ON public.as2provider USING btree (provider_id);


--
-- Name: atraster100_geom_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX atraster100_geom_idx ON public.atraster100 USING gist (geom);


--
-- Name: atraster100_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX atraster100_id_idx ON public.atraster USING btree (id);


--
-- Name: atraster250_geom_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX atraster250_geom_idx ON public.atraster250 USING gist (geom);


--
-- Name: atraster250_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX atraster250_id_idx ON public.atraster USING btree (id);


--
-- Name: atraster_geom_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX atraster_geom_idx ON public.atraster USING gist (geom);


--
-- Name: atraster_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX atraster_id_idx ON public.atraster USING btree (id);


--
-- Name: bev_vgd_bbox_gix; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX bev_vgd_bbox_gix ON public.bev_vgd USING gist (bbox);


--
-- Name: bev_vgd_geom_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX bev_vgd_geom_idx ON public.bev_vgd USING gist (geom);


--
-- Name: bev_vgd_gkz_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX bev_vgd_gkz_idx ON public.bev_vgd USING btree (gkz);


--
-- Name: bev_vgd_kg_nr_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX bev_vgd_kg_nr_idx ON public.bev_vgd USING btree (kg_nr);


--
-- Name: bev_vgd_kg_nr_int_gix; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX bev_vgd_kg_nr_int_gix ON public.bev_vgd USING btree (kg_nr_int);


--
-- Name: cell_location_test_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX cell_location_test_id_idx ON public.cell_location USING btree (test_id);


--
-- Name: cell_location_test_id_time_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX cell_location_test_id_time_idx ON public.cell_location USING btree (test_id, "time");


--
-- Name: clc18_legend_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX clc18_legend_idx ON public.clc18_legend USING btree (clc_code);


--
-- Name: clc18_shape_geom_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX clc18_shape_geom_idx ON public.clc18 USING gist (shape);


--
-- Name: clc_legend_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX clc_legend_idx ON public.clc_legend USING btree (clc_code);


--
-- Name: client_client_type_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX client_client_type_id_idx ON public.client USING btree (client_type_id);


--
-- Name: client_sync_group_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX client_sync_group_id_idx ON public.client USING btree (sync_group_id);


--
-- Name: cov_mno_operator_reference_license_raster_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX cov_mno_operator_reference_license_raster_idx ON public.cov_mno USING btree (operator, reference, license, raster);


--
-- Name: cov_mno_raster_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX cov_mno_raster_idx ON public.cov_mno USING btree (raster);


--
-- Name: cov_visible_name_visible_name_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX cov_visible_name_visible_name_idx ON public.cov_visible_name USING btree (visible_name);


--
-- Name: dhm2_st_convexhull_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX dhm2_st_convexhull_idx ON public.dhm USING gist (public.st_convexhull(rast));


--
-- Name: download_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX download_idx ON public.test USING btree (bytes_download, network_type);


--
-- Name: dsr_geom_gix; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX dsr_geom_gix ON public.dsr USING gist (geom);


--
-- Name: fences_open_test_uuid_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX fences_open_test_uuid_idx ON public.fences USING btree (open_test_uuid);


--
-- Name: fki_qos_test_result_qos_test_uid_fkey; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX fki_qos_test_result_qos_test_uid_fkey ON public.qos_test_result USING btree (qos_test_uid);


--
-- Name: fki_qos_test_result_qos_testb_uid_fkey; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX fki_qos_test_result_qos_testb_uid_fkey ON public.qos_test_result_b USING btree (qos_test_uid);


--
-- Name: fki_qos_test_result_test_uid; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX fki_qos_test_result_test_uid ON public.qos_test_result USING btree (test_uid);


--
-- Name: fki_qos_test_result_testb_uid; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX fki_qos_test_result_testb_uid ON public.qos_test_result_b USING btree (test_uid);


--
-- Name: geo_location_open_test_uuid_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX geo_location_open_test_uuid_idx ON public.geo_location USING btree (open_test_uuid);


--
-- Name: geo_location_test_id_key; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX geo_location_test_id_key ON public.geo_location USING btree (test_id);


--
-- Name: geo_location_test_id_provider; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX geo_location_test_id_provider ON public.geo_location USING btree (test_id, provider);


--
-- Name: geo_location_test_id_provider_time_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX geo_location_test_id_provider_time_idx ON public.geo_location USING btree (test_id, provider, "time");


--
-- Name: geo_location_test_id_time_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX geo_location_test_id_time_idx ON public.geo_location USING btree (test_id, "time");


--
-- Name: geom4326_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX geom4326_idx ON public.fences USING gist (geom4326);


--
-- Name: idx_cov_mno_fn_raster; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cov_mno_fn_raster ON public.cov_mno_fn USING btree (raster);


--
-- Name: idx_loopmode_loopuuid_testcounter; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX idx_loopmode_loopuuid_testcounter ON public.test_loopmode USING btree (loop_uuid, test_counter DESC NULLS LAST);


--
-- Name: idx_the_geom_4326_atraster100; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX idx_the_geom_4326_atraster100 ON public.atraster100 USING gist (public.st_transform(geom, 4326));


--
-- Name: idx_the_geom_4326_atraster250; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX idx_the_geom_4326_atraster250 ON public.atraster250 USING gist (public.st_transform(geom, 4326));


--
-- Name: ix_test_purge; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX ix_test_purge ON public.test USING btree (uid) WHERE ((client_public_ip IS NOT NULL) OR (public_ip_rdns IS NOT NULL) OR (source_ip IS NOT NULL) OR (client_ip_local IS NOT NULL) OR (wifi_bssid IS NOT NULL) OR (wifi_ssid IS NOT NULL));


--
-- Name: ix_test_server_quality_server_uuid; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_test_server_quality_server_uuid ON public.test_server_quality USING btree (server_uuid);


--
-- Name: ix_test_server_quality_timestamp; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_test_server_quality_timestamp ON public.test_server_quality USING btree ("timestamp");


--
-- Name: link4net_gix; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX link4net_gix ON public.link4net USING gist (geom);


--
-- Name: link4net_link_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX link4net_link_id_idx ON public.link4net USING btree (link_id);


--
-- Name: linknet_bbox_gix; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX linknet_bbox_gix ON public.linknet USING gist (bbox);


--
-- Name: linknet_gix; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX linknet_gix ON public.linknet USING gist (geom);


--
-- Name: linknet_names_link_id_uindex; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE UNIQUE INDEX linknet_names_link_id_uindex ON public.linknet_names USING btree (link_id);


--
-- Name: linknet_names_link_name_index; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX linknet_names_link_name_index ON public.linknet_names USING btree (link_name);


--
-- Name: location_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX location_idx ON public.test USING gist (location);


--
-- Name: mcc2country_mcc; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX mcc2country_mcc ON public.mcc2country USING btree (mcc);


--
-- Name: mccmnc2name_mccmnc; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX mccmnc2name_mccmnc ON public.mccmnc2name USING btree (mccmnc);


--
-- Name: mccmnc2provider_mcc_mnc_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX mccmnc2provider_mcc_mnc_idx ON public.mccmnc2provider USING btree (mcc_mnc_sim, mcc_mnc_network);


--
-- Name: mccmnc2provider_provider_id; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX mccmnc2provider_provider_id ON public.mccmnc2provider USING btree (provider_id);


--
-- Name: ne_10m_admin_0_countries_iso_a2_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX ne_10m_admin_0_countries_iso_a2_idx ON public.ne_10m_admin_0_countries USING btree (iso_a2);


--
-- Name: ne_10m_admin_0_countries_iso_geom3426_gist; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX ne_10m_admin_0_countries_iso_geom3426_gist ON public.ne_10m_admin_0_countries USING gist (geom4326);


--
-- Name: ne_10m_admin_0_countries_iso_geom_gist; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX ne_10m_admin_0_countries_iso_geom_gist ON public.ne_10m_admin_0_countries USING gist (geom);


--
-- Name: network_type_group_name_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX network_type_group_name_idx ON public.network_type USING btree (group_name);


--
-- Name: network_type_type_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX network_type_type_idx ON public.network_type USING btree (type);


--
-- Name: news_time_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX news_time_idx ON public.news USING btree ("time");


--
-- Name: open_test_uuid_cell_location_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX open_test_uuid_cell_location_idx ON public.cell_location USING btree (open_test_uuid);


--
-- Name: open_test_uuid_ping_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX open_test_uuid_ping_idx ON public.ping USING btree (open_test_uuid);


--
-- Name: open_test_uuid_signal2_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX open_test_uuid_signal2_idx ON public.signal USING btree (open_test_uuid);


--
-- Name: open_test_uuid_signal_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX open_test_uuid_signal_idx ON public.signal USING btree (open_test_uuid);


--
-- Name: ping_test_id_key; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX ping_test_id_key ON public.ping USING btree (test_id);


--
-- Name: provider_mcc_mnc_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX provider_mcc_mnc_idx ON public.provider USING btree (mcc_mnc);


--
-- Name: qos_test_desc_desc_key_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX qos_test_desc_desc_key_idx ON public.qos_test_desc USING btree (desc_key);


--
-- Name: radio_cell_open_uuid_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX radio_cell_open_uuid_idx ON public.radio_cell USING btree (open_test_uuid);


--
-- Name: radio_cell_uuid_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE UNIQUE INDEX radio_cell_uuid_idx ON public.radio_cell USING btree (uuid);


--
-- Name: radio_signal_location_interpolated_location_gix; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX radio_signal_location_interpolated_location_gix ON public.radio_signal_location USING gist (interpolated_location);


--
-- Name: radio_signal_location_open_test_uuid_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX radio_signal_location_open_test_uuid_idx ON public.radio_signal_location USING hash (open_test_uuid);


--
-- Name: radio_signal_location_time_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX radio_signal_location_time_idx ON public.radio_signal_location USING btree ("time");


--
-- Name: radio_signal_open_uuid_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX radio_signal_open_uuid_idx ON public.radio_signal USING btree (open_test_uuid);


--
-- Name: settings_key_lang_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX settings_key_lang_idx ON public.settings USING btree (key, lang);


--
-- Name: statistik_austria_gem_bbox_gix; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX statistik_austria_gem_bbox_gix ON public.statistik_austria_gem USING gist (bbox);


--
-- Name: statistik_austria_gem_geom_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX statistik_austria_gem_geom_idx ON public.statistik_austria_gem USING gist (geom);


--
-- Name: test10mdtm_st_convexhull_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX test10mdtm_st_convexhull_idx ON public.dtm10m USING gist (public.st_convexhull(rast));


--
-- Name: test_client_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_client_id_idx ON public.test USING btree (client_id);


--
-- Name: test_deleted_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_deleted_idx ON public.test USING btree (deleted);


--
-- Name: test_developer_code_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_developer_code_idx ON public.test USING btree (developer_code);


--
-- Name: test_device_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_device_idx ON public.test USING btree (device);


--
-- Name: test_geo_accuracy_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_geo_accuracy_idx ON public.test USING btree (geo_accuracy);


--
-- Name: test_gkz_bev_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_gkz_bev_idx ON public.test USING btree (gkz_bev_obsolete);


--
-- Name: test_gkz_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_gkz_idx ON public.test USING btree (gkz_obsolete);


--
-- Name: test_gkz_sa_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_gkz_sa_idx ON public.test USING btree (gkz_sa_obsolete);


--
-- Name: test_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_idx ON public.test USING btree (((network_type <> ALL (ARRAY[0, 99]))));


--
-- Name: test_kg_nr_bev_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_kg_nr_bev_idx ON public.test USING btree (kg_nr_bev);


--
-- Name: test_land_cover_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_land_cover_idx ON public.test USING btree (land_cover_obsolete);


--
-- Name: test_location_geo_accuracy_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_geo_accuracy_idx ON public.test_location USING btree (geo_accuracy);


--
-- Name: test_location_geom4326_geography_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_geom4326_geography_idx ON public.test_location USING gist (public.geography(geom4326));


--
-- Name: test_location_geom4326_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_geom4326_idx ON public.test_location USING gist (geom4326);


--
-- Name: test_location_gkz_bev_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_gkz_bev_idx ON public.test_location USING btree (gkz_bev);


--
-- Name: test_location_gkz_sa_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_gkz_sa_idx ON public.test_location USING btree (gkz_sa);


--
-- Name: test_location_kg_nv_bev_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_kg_nv_bev_idx ON public.test_location USING btree (kg_nr_bev);


--
-- Name: test_location_land_cover_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_land_cover_idx ON public.test_location USING btree (land_cover);


--
-- Name: test_location_link_name_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_link_name_idx ON public.test_location USING btree (link_name);


--
-- Name: test_location_location_gix; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_location_gix ON public.test_location USING gist (location);


--
-- Name: test_location_open_test_uuid_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_open_test_uuid_idx ON public.test_location USING btree (open_test_uuid);


--
-- Name: test_location_settlement_type_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_location_settlement_type_idx ON public.test_location USING btree (settlement_type);


--
-- Name: test_mobile_network_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_mobile_network_id_idx ON public.test USING btree (mobile_network_id);


--
-- Name: test_mobile_provider_id2_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_mobile_provider_id2_idx ON public.test USING btree (mobile_provider_id2);


--
-- Name: test_mobile_provider_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_mobile_provider_id_idx ON public.test USING btree (mobile_provider_id);


--
-- Name: test_ndt_test_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_ndt_test_id_idx ON public.test_ndt USING btree (test_id);


--
-- Name: test_network_operator_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_network_operator_idx ON public.test USING btree (network_operator);


--
-- Name: test_network_type_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_network_type_idx ON public.test USING btree (network_type);


--
-- Name: test_open_test_uuid_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_open_test_uuid_idx ON public.test USING btree (open_test_uuid);


--
-- Name: test_open_uuid_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_open_uuid_idx ON public.test USING btree (open_uuid);


--
-- Name: test_ping_median_log_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_ping_median_log_idx ON public.test USING btree (ping_median_log);


--
-- Name: test_ping_shortest_log_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_ping_shortest_log_idx ON public.test USING btree (ping_shortest_log);


--
-- Name: test_pinned_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_pinned_idx ON public.test USING btree (pinned);


--
-- Name: test_pinned_implausible_deleted_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_pinned_implausible_deleted_idx ON public.test USING btree (pinned, implausible, deleted);


--
-- Name: test_provider_id_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_provider_id_idx ON public.test USING btree (provider_id);


--
-- Name: test_similar_test_uid_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_similar_test_uid_idx ON public.test USING btree (similar_test_uid);


--
-- Name: test_speed_download_log_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_speed_download_log_idx ON public.test USING btree (speed_download_log);


--
-- Name: test_speed_upload_log_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_speed_upload_log_idx ON public.test USING btree (speed_upload_log);


--
-- Name: test_status_finished2_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_status_finished2_idx ON public.test USING btree ((((NOT deleted) AND (NOT implausible) AND ((status)::text = 'FINISHED'::text))), network_type);


--
-- Name: test_status_finished_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_status_finished_idx ON public.test USING btree ((((deleted = false) AND ((status)::text = 'FINISHED'::text))), network_type);


--
-- Name: test_status_finished_not_deleted_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_status_finished_not_deleted_idx ON public.test USING btree ((((deleted = false) AND ((status)::text = 'FINISHED'::text))));


--
-- Name: test_status_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_status_idx ON public.test USING btree (status);


--
-- Name: test_test_slot_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_test_slot_idx ON public.test USING btree (test_slot);


--
-- Name: test_time_export; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_time_export ON public.test USING btree (date_part('month'::text, timezone('UTC'::text, "time")), date_part('year'::text, timezone('UTC'::text, "time")));


--
-- Name: test_time_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_time_idx ON public.test USING btree ("time");


--
-- Name: test_zip_code_idx; Type: INDEX; Schema: public; Owner: rmbt
--

CREATE INDEX test_zip_code_idx ON public.test USING btree (zip_code);


--
-- Name: cell_location trigger_cell_location; Type: TRIGGER; Schema: public; Owner: rmbt
--

CREATE TRIGGER trigger_cell_location BEFORE INSERT ON public.cell_location FOR EACH ROW EXECUTE FUNCTION public.trigger_radio_cell();


--
-- Name: geo_location trigger_geo_location; Type: TRIGGER; Schema: public; Owner: rmbt
--

CREATE TRIGGER trigger_geo_location BEFORE INSERT ON public.geo_location FOR EACH ROW EXECUTE FUNCTION public.trigger_geo_location();


--
-- Name: qos_test_result trigger_qos_test_result; Type: TRIGGER; Schema: public; Owner: rmbt
--

CREATE TRIGGER trigger_qos_test_result BEFORE INSERT OR UPDATE ON public.qos_test_result FOR EACH ROW EXECUTE FUNCTION public.trigger_qos_test_result();


--
-- Name: radio_cell trigger_radio_cell; Type: TRIGGER; Schema: public; Owner: rmbt
--

CREATE TRIGGER trigger_radio_cell BEFORE INSERT ON public.radio_cell FOR EACH ROW EXECUTE FUNCTION public.trigger_radio_cell();


--
-- Name: test trigger_test; Type: TRIGGER; Schema: public; Owner: rmbt
--

CREATE TRIGGER trigger_test BEFORE INSERT OR UPDATE ON public.test FOR EACH ROW EXECUTE FUNCTION public.trigger_test();


--
-- Name: test_location trigger_test_location2; Type: TRIGGER; Schema: public; Owner: rmbt
--

CREATE TRIGGER trigger_test_location2 BEFORE INSERT OR UPDATE ON public.test_location FOR EACH ROW EXECUTE FUNCTION public.trigger_test_location();


--
-- Name: as2provider as2provider_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.as2provider
    ADD CONSTRAINT as2provider_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.provider(uid);


--
-- Name: cell_location cell_location_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.cell_location
    ADD CONSTRAINT cell_location_test_id_fkey FOREIGN KEY (test_id) REFERENCES public.test(uid) ON DELETE CASCADE;


--
-- Name: client client_client_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT client_client_type_id_fkey FOREIGN KEY (client_type_id) REFERENCES public.client_type(uid);


--
-- Name: client client_sync_group_id; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT client_sync_group_id FOREIGN KEY (sync_group_id) REFERENCES public.sync_group(uid);


--
-- Name: fences fences_open_test_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fences
    ADD CONSTRAINT fences_open_test_uuid_fkey FOREIGN KEY (open_test_uuid) REFERENCES public.test(open_test_uuid) ON DELETE CASCADE;


--
-- Name: geo_location geo_location_open_test_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.geo_location
    ADD CONSTRAINT geo_location_open_test_uuid_fkey FOREIGN KEY (open_test_uuid) REFERENCES public.test(open_test_uuid) ON DELETE CASCADE;


--
-- Name: mccmnc2provider mccmnc2provider_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.mccmnc2provider
    ADD CONSTRAINT mccmnc2provider_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.provider(uid);


--
-- Name: ping ping_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.ping
    ADD CONSTRAINT ping_test_id_fkey FOREIGN KEY (test_id) REFERENCES public.test(uid) ON DELETE CASCADE;


--
-- Name: qos_test_result qos_test_result_qos_test_uid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_result
    ADD CONSTRAINT qos_test_result_qos_test_uid_fkey FOREIGN KEY (qos_test_uid) REFERENCES public.qos_test_objective(uid) ON DELETE CASCADE;


--
-- Name: qos_test_result qos_test_result_test_uid; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_result
    ADD CONSTRAINT qos_test_result_test_uid FOREIGN KEY (test_uid) REFERENCES public.test(uid) ON DELETE CASCADE;


--
-- Name: qos_test_result_b qos_test_result_test_uid; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_result_b
    ADD CONSTRAINT qos_test_result_test_uid FOREIGN KEY (test_uid) REFERENCES public.test(uid) ON DELETE CASCADE;


--
-- Name: qos_test_result_b qos_test_resultb_qos_test_uid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.qos_test_result_b
    ADD CONSTRAINT qos_test_resultb_qos_test_uid_fkey FOREIGN KEY (qos_test_uid) REFERENCES public.qos_test_objective(uid) ON DELETE CASCADE;


--
-- Name: radio_signal_location radio_signal_location_open_test_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal_location
    ADD CONSTRAINT radio_signal_location_open_test_uuid_fkey FOREIGN KEY (open_test_uuid) REFERENCES public.test(open_test_uuid) ON DELETE CASCADE;


--
-- Name: radio_signal_location radio_signal_location_radio_geo_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal_location
    ADD CONSTRAINT radio_signal_location_radio_geo_location_id_fkey FOREIGN KEY (last_geo_location_uuid) REFERENCES public.geo_location(geo_location_uuid) ON DELETE CASCADE;


--
-- Name: radio_signal_location radio_signal_location_radio_signal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal_location
    ADD CONSTRAINT radio_signal_location_radio_signal_id_fkey FOREIGN KEY (last_radio_signal_uuid) REFERENCES public.radio_signal(radio_signal_uuid) ON DELETE CASCADE;


--
-- Name: radio_signal_location radio_signal_location_signal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal_location
    ADD CONSTRAINT radio_signal_location_signal_id_fkey FOREIGN KEY (last_signal_uuid) REFERENCES public.signal(signal_uuid) ON DELETE CASCADE;


--
-- Name: radio_signal radio_signal_open_test_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.radio_signal
    ADD CONSTRAINT radio_signal_open_test_uuid_fkey FOREIGN KEY (open_test_uuid) REFERENCES public.test(open_test_uuid) ON DELETE CASCADE;


--
-- Name: signal signal_open_test_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.signal
    ADD CONSTRAINT signal_open_test_uuid_fkey FOREIGN KEY (open_test_uuid) REFERENCES public.test(open_test_uuid) ON DELETE CASCADE;


--
-- Name: test test_client_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test
    ADD CONSTRAINT test_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.client(uid) ON DELETE CASCADE;


--
-- Name: test_location test_location_open_test_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_location
    ADD CONSTRAINT test_location_open_test_uuid_fkey FOREIGN KEY (open_test_uuid) REFERENCES public.test(open_test_uuid) ON DELETE CASCADE;


--
-- Name: test_loopmode test_loopmode_test_client_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_loopmode
    ADD CONSTRAINT test_loopmode_test_client_uuid_fkey FOREIGN KEY (client_uuid) REFERENCES public.client(uuid);


--
-- Name: test_loopmode test_loopmode_test_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_loopmode
    ADD CONSTRAINT test_loopmode_test_uuid_fkey FOREIGN KEY (test_uuid) REFERENCES public.test(uuid);


--
-- Name: test test_mobile_provider_id2_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test
    ADD CONSTRAINT test_mobile_provider_id2_fkey FOREIGN KEY (mobile_provider_id2) REFERENCES public.provider(uid);


--
-- Name: test test_mobile_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test
    ADD CONSTRAINT test_mobile_provider_id_fkey FOREIGN KEY (mobile_provider_id) REFERENCES public.provider(uid);


--
-- Name: test_ndt test_ndt_test_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test_ndt
    ADD CONSTRAINT test_ndt_test_id_fkey FOREIGN KEY (test_id) REFERENCES public.test(uid) ON DELETE CASCADE;


--
-- Name: test test_provider_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test
    ADD CONSTRAINT test_provider_fkey FOREIGN KEY (provider_id) REFERENCES public.provider(uid);


--
-- Name: test_server_quality test_server_quality_server_uuid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.test_server_quality
    ADD CONSTRAINT test_server_quality_server_uuid_fkey FOREIGN KEY (server_uuid) REFERENCES public.test_server(uuid);


--
-- Name: test test_test_server_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: rmbt
--

ALTER TABLE ONLY public.test
    ADD CONSTRAINT test_test_server_id_fkey FOREIGN KEY (server_id) REFERENCES public.test_server(uid);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- Name: FUNCTION trigger_test(); Type: ACL; Schema: public; Owner: rmbt
--

REVOKE ALL ON FUNCTION public.trigger_test() FROM PUBLIC;


--
-- Name: TABLE admin_0_countries; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.admin_0_countries TO rmbt_group_read_only;
GRANT SELECT ON TABLE public.admin_0_countries TO rmbt_control;
GRANT SELECT ON TABLE public.admin_0_countries TO rmbt_group_control;


--
-- Name: TABLE device_map; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.device_map TO rmbt_group_read_only;


--
-- Name: TABLE as2provider; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.as2provider TO rmbt_group_read_only;


--
-- Name: TABLE atraster; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.atraster TO rmbt_group_read_only;


--
-- Name: TABLE atraster100; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.atraster100 TO rmbt_group_read_only;


--
-- Name: TABLE atraster250; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.atraster250 TO rmbt_group_read_only;


--
-- Name: TABLE bb_atlas_festnetz_2025q4; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.bb_atlas_festnetz_2025q4 TO rmbt;


--
-- Name: TABLE bev_vgd; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.bev_vgd TO rmbt_group_read_only;


--
-- Name: TABLE cell_location; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.cell_location TO rmbt_group_read_only;
GRANT INSERT ON TABLE public.cell_location TO rmbt_group_control;


--
-- Name: SEQUENCE cell_location_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.cell_location_uid_seq TO rmbt_group_control;


--
-- Name: TABLE clc18; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.clc18 TO rmbt_group_read_only;


--
-- Name: TABLE clc18_legend; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.clc18_legend TO rmbt;
GRANT SELECT ON TABLE public.clc18_legend TO rmbt_group_read_only;


--
-- Name: TABLE clc_legend; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.clc_legend TO rmbt_group_read_only;


--
-- Name: TABLE client; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.client TO rmbt_group_read_only;
GRANT INSERT,UPDATE ON TABLE public.client TO rmbt_group_control;


--
-- Name: TABLE client_type; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.client_type TO rmbt_group_read_only;


--
-- Name: SEQUENCE client_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.client_uid_seq TO rmbt_group_control;


--
-- Name: TABLE cov_mno_fn; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.cov_mno_fn TO rmbt;


--
-- Name: TABLE cov_visible_name; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.cov_visible_name TO rmbt_group_read_only;


--
-- Name: TABLE dhm; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.dhm TO rmbt_group_read_only;


--
-- Name: TABLE dsr; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.dsr TO rmbt_group_read_only;


--
-- Name: TABLE fences; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.fences TO rmbt;
GRANT SELECT,INSERT,UPDATE ON TABLE public.fences TO rmbt_group_control;
GRANT SELECT ON TABLE public.fences TO rmbt_group_read_only;


--
-- Name: SEQUENCE fences_uid_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.fences_uid_seq TO rmbt;
GRANT SELECT,UPDATE ON SEQUENCE public.fences_uid_seq TO rmbt_group_control;
GRANT SELECT ON SEQUENCE public.fences_uid_seq TO rmbt_group_read_only;


--
-- Name: TABLE geo_location; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.geo_location TO rmbt_group_read_only;
GRANT ALL ON TABLE public.geo_location TO rmbt_group_control;


--
-- Name: SEQUENCE geo_location_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT,USAGE ON SEQUENCE public.geo_location_uid_seq TO rmbt_group_control;
GRANT SELECT ON SEQUENCE public.geo_location_uid_seq TO rmbt_group_read_only;


--
-- Name: TABLE link4net; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.link4net TO rmbt_group_read_only;


--
-- Name: TABLE linknet; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.linknet TO rmbt_group_read_only;


--
-- Name: TABLE linknet_names; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.linknet_names TO rmbt_group_read_only;


--
-- Name: TABLE mcc2country; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.mcc2country TO rmbt_group_read_only;


--
-- Name: TABLE mccmnc2name; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.mccmnc2name TO rmbt_group_read_only;
GRANT SELECT ON TABLE public.mccmnc2name TO rmbt_group_control;


--
-- Name: TABLE mccmnc2provider; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.mccmnc2provider TO rmbt_group_read_only;


--
-- Name: TABLE ne_10m_admin_0_countries; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.ne_10m_admin_0_countries TO rmbt_group_read_only;


--
-- Name: TABLE network_type; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.network_type TO rmbt_group_read_only;


--
-- Name: TABLE news; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.news TO rmbt_group_read_only;


--
-- Name: TABLE ping; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.ping TO rmbt_group_read_only;
GRANT INSERT ON TABLE public.ping TO rmbt_group_control;


--
-- Name: SEQUENCE ping_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.ping_uid_seq TO rmbt_group_control;


--
-- Name: TABLE provider; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.provider TO rmbt_group_read_only;


--
-- Name: TABLE qoe_classification; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.qoe_classification TO rmbt_group_read_only;
GRANT SELECT ON TABLE public.qoe_classification TO rmbt_group_control;


--
-- Name: TABLE qos_test_desc; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.qos_test_desc TO rmbt_group_read_only;


--
-- Name: TABLE qos_test_objective; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.qos_test_objective TO rmbt_group_read_only;
GRANT SELECT ON TABLE public.qos_test_objective TO rmbt_control;


--
-- Name: TABLE qos_test_result; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.qos_test_result TO rmbt_group_read_only;
GRANT INSERT,UPDATE ON TABLE public.qos_test_result TO rmbt_group_control;


--
-- Name: TABLE qos_test_result_b; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.qos_test_result_b TO rmbt_group_read_only;
GRANT INSERT,UPDATE ON TABLE public.qos_test_result_b TO rmbt_group_control;


--
-- Name: SEQUENCE qos_test_result_b_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.qos_test_result_b_uid_seq TO rmbt_group_control;


--
-- Name: SEQUENCE qos_test_result_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.qos_test_result_uid_seq TO rmbt_group_control;


--
-- Name: TABLE qos_test_type_desc; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.qos_test_type_desc TO rmbt_group_read_only;
GRANT SELECT ON TABLE public.qos_test_type_desc TO rmbt_control;


--
-- Name: TABLE radio_cell; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.radio_cell TO rmbt_group_read_only;
GRANT INSERT ON TABLE public.radio_cell TO rmbt_group_control;


--
-- Name: SEQUENCE radio_cell_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.radio_cell_uid_seq TO rmbt_group_control;


--
-- Name: TABLE radio_signal; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.radio_signal TO rmbt_group_read_only;
GRANT ALL ON TABLE public.radio_signal TO rmbt_group_control;


--
-- Name: TABLE radio_signal_location; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.radio_signal_location TO rmbt_group_read_only;
GRANT ALL ON TABLE public.radio_signal_location TO rmbt_group_control;


--
-- Name: SEQUENCE radio_signal_location_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT ALL ON SEQUENCE public.radio_signal_location_uid_seq TO rmbt_group_control;


--
-- Name: SEQUENCE radio_signal_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT,USAGE ON SEQUENCE public.radio_signal_uid_seq TO rmbt_group_control;


--
-- Name: TABLE settings; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.settings TO rmbt_group_read_only;


--
-- Name: TABLE signal; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.signal TO rmbt_group_read_only;
GRANT ALL ON TABLE public.signal TO rmbt_group_control;


--
-- Name: SEQUENCE signal_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT,USAGE ON SEQUENCE public.signal_uid_seq TO rmbt_group_control;


--
-- Name: TABLE speed; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.speed TO rmbt_group_read_only;
GRANT INSERT,UPDATE ON TABLE public.speed TO rmbt_group_control;


--
-- Name: SEQUENCE speed_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.speed_uid_seq TO rmbt_group_control;


--
-- Name: TABLE statistik_austria_gem; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.statistik_austria_gem TO rmbt_group_read_only;


--
-- Name: TABLE status_obsolete; Type: ACL; Schema: public; Owner: rmbt
--

GRANT INSERT,UPDATE ON TABLE public.status_obsolete TO rmbt_group_control;
GRANT SELECT ON TABLE public.status_obsolete TO rmbt_group_read_only;


--
-- Name: SEQUENCE status_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT UPDATE ON SEQUENCE public.status_uid_seq TO rmbt_group_control;


--
-- Name: TABLE sync_group; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.sync_group TO rmbt_group_read_only;
GRANT INSERT,DELETE ON TABLE public.sync_group TO rmbt_group_control;


--
-- Name: SEQUENCE sync_group_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.sync_group_uid_seq TO rmbt_group_control;


--
-- Name: TABLE test; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.test TO rmbt_group_read_only;
GRANT INSERT,UPDATE ON TABLE public.test TO rmbt_group_control;


--
-- Name: TABLE test_location; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.test_location TO rmbt_group_read_only;
GRANT ALL ON TABLE public.test_location TO rmbt_group_control;


--
-- Name: SEQUENCE test_location_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT,USAGE ON SEQUENCE public.test_location_uid_seq TO rmbt_group_control;
GRANT SELECT ON SEQUENCE public.test_location_uid_seq TO rmbt_group_read_only;


--
-- Name: TABLE test_loopmode; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.test_loopmode TO rmbt_group_read_only;
GRANT INSERT,UPDATE ON TABLE public.test_loopmode TO rmbt_group_control;


--
-- Name: SEQUENCE test_loopmode_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.test_loopmode_uid_seq TO rmbt_group_control;


--
-- Name: TABLE test_ndt; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.test_ndt TO rmbt_group_read_only;
GRANT INSERT,UPDATE ON TABLE public.test_ndt TO rmbt_group_control;


--
-- Name: SEQUENCE test_ndt_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.test_ndt_uid_seq TO rmbt_group_control;


--
-- Name: TABLE test_server; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.test_server TO rmbt_group_read_only;


--
-- Name: TABLE test_server_quality; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,UPDATE ON TABLE public.test_server_quality TO rmbt_control;


--
-- Name: TABLE test_server_qos_view; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.test_server_qos_view TO rmbt_control;


--
-- Name: SEQUENCE test_server_quality_uid_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,USAGE ON SEQUENCE public.test_server_quality_uid_seq TO rmbt_control;


--
-- Name: TABLE test_server_types; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.test_server_types TO rmbt_control;
GRANT SELECT ON TABLE public.test_server_types TO rmbt_group_control;
GRANT SELECT ON TABLE public.test_server_types TO rmbt_group_read_only;


--
-- Name: SEQUENCE test_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT USAGE ON SEQUENCE public.test_uid_seq TO rmbt_group_control;


--
-- Name: SEQUENCE tl2_uid_seq; Type: ACL; Schema: public; Owner: rmbt
--

GRANT ALL ON SEQUENCE public.tl2_uid_seq TO rmbt_group_control;


--
-- Name: TABLE v_dl_bandwidth_per_minute; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.v_dl_bandwidth_per_minute TO rmbt_group_read_only;


--
-- Name: TABLE v_get_replication_delay; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.v_get_replication_delay TO nagios;


--
-- Name: TABLE v_radio_signal_location; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.v_radio_signal_location TO rmbt_group_read_only;
GRANT SELECT ON TABLE public.v_radio_signal_location TO rmbt;


--
-- Name: TABLE v_test_metrics; Type: ACL; Schema: public; Owner: rmbt
--

GRANT SELECT ON TABLE public.v_test_metrics TO rmbt_group_read_only;
GRANT SELECT ON TABLE public.v_test_metrics TO nagios;


--
-- PostgreSQL database dump complete
--

\unrestrict Pvfl7gTzgcJ6fWbaftaYmDfPrcVzRIcLwbji9VAKPV4Z6ccizk9fGcRLfMP1vfp

