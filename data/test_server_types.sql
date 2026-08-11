--
-- PostgreSQL database dump
--

\restrict SFy0wGBL5WtJTzQYj3ERuwd5ej9bKRGut35tFV8pSSwDe58VnAoOV9ajRaT96bJ

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
-- Data for Name: test_server_types; Type: TABLE DATA; Schema: public; Owner: rmbt
--

COPY public.test_server_types (test_server_uid, server_type, uid, port, port_ssl, encrypted) FROM stdin;
1	RMBThttp	1	\N	443	t
\.


--
-- Name: test_server_types_uid_seq; Type: SEQUENCE SET; Schema: public; Owner: rmbt
--

SELECT pg_catalog.setval('public.test_server_types_uid_seq', 1, true);


--
-- PostgreSQL database dump complete
--

\unrestrict SFy0wGBL5WtJTzQYj3ERuwd5ej9bKRGut35tFV8pSSwDe58VnAoOV9ajRaT96bJ

