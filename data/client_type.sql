--
-- PostgreSQL database dump
--

\restrict GjA5TLJuANE98GUdnbKT4qSVC7bQy00t4PBECNLVa3NHmYg0rM0UlFMfoXyOQSU

-- Dumped from database version 16.14 (Debian 16.14-1.pgdg13+1)
-- Dumped by pg_dump version 16.14 (Debian 16.14-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: client_type; Type: TABLE DATA; Schema: public; Owner: rmbt
--

COPY public.client_type (uid, name) FROM stdin;
1	DESKTOP
2	MOBILE
\.


--
-- Name: client_type_uid_seq; Type: SEQUENCE SET; Schema: public; Owner: rmbt
--

SELECT pg_catalog.setval('public.client_type_uid_seq', 3, true);


--
-- PostgreSQL database dump complete
--

\unrestrict GjA5TLJuANE98GUdnbKT4qSVC7bQy00t4PBECNLVa3NHmYg0rM0UlFMfoXyOQSU

