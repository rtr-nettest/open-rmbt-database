--
-- PostgreSQL database dump
--

\restrict m8GDB5gVmhfbIxWpxXHNIeq6sCUxAKauWfkcZEtzMuj8F2mc6GM6bBDe8ldl18V

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
-- Data for Name: test_server; Type: TABLE DATA; Schema: public; Owner: rmbt
--

COPY public.test_server (uid, name, web_address, port, port_ssl, city, country, geo_lat, geo_long, location, web_address_ipv4, web_address_ipv6, server_type, priority, weight, active, uuid, key, selectable, countries, node, archived, coverage) FROM stdin;
1	OpenRMBT-Server	\N	\N	443	Vienna	AT	48.269755	16.410913	010100002031BF0D00DD5C867A26E03B41B6FC3597AA775741	mv4.example.com	mv6.example.com	RMBThttp	100	40	t	05500059-d190-4bbf-85e7-0a40c11c719a	topsharedsecret	t	{any}	VIE	f	\N
\.


--
-- Name: test_server_uid_seq; Type: SEQUENCE SET; Schema: public; Owner: rmbt
--

SELECT pg_catalog.setval('public.test_server_uid_seq', 1, true);


--
-- PostgreSQL database dump complete
--

\unrestrict m8GDB5gVmhfbIxWpxXHNIeq6sCUxAKauWfkcZEtzMuj8F2mc6GM6bBDe8ldl18V

