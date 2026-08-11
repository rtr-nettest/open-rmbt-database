--
-- PostgreSQL database dump
--

\restrict bggeLauEAcL8DHFZvP15hi1VPrmH1FNOgcI7IkrXMCCNcfcD8MhDCyk3pufNhhJ

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
-- Data for Name: qoe_classification; Type: TABLE DATA; Schema: public; Owner: rmbt
--

COPY public.qoe_classification (uid, category, dl_4, dl_3, dl_2, ul_4, ul_3, ul_2, ping_4, ping_3, ping_2) FROM stdin;
1	video_conferencing	20000	6000	3000	20000	6000	3000	25000000	50000000	100000000
3	gaming	8000	4000	2000	8000	4000	2000	10000000	10000001	50000000
2	video_uhd	30000	15000	5000	6000	3000	1000	40000000	80000000	160000000
\.


--
-- Name: qoe_classification_uid_seq; Type: SEQUENCE SET; Schema: public; Owner: rmbt
--

SELECT pg_catalog.setval('public.qoe_classification_uid_seq', 2, true);


--
-- PostgreSQL database dump complete
--

\unrestrict bggeLauEAcL8DHFZvP15hi1VPrmH1FNOgcI7IkrXMCCNcfcD8MhDCyk3pufNhhJ

