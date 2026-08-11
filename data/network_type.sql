--
-- PostgreSQL database dump
--

\restrict KV2CrY0yLUhEuBBfYo6yMp7Rh4SCEiWyzP2MdJu5hCCTDlKyPiAz7742BXpSIB6

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
-- Data for Name: network_type; Type: TABLE DATA; Schema: public; Owner: rmbt
--

COPY public.network_type (uid, name, group_name, aggregate, type, technology_order, min_speed_download_kbps, max_speed_download_kbps, min_speed_upload_kbps, max_speed_upload_kbps) FROM stdin;
101	2G/3G	2G/3G	{2G,3G}	MOBILE	0	1	35000	1	5760
3	UMTS	3G	\N	MOBILE	30000	1	35000	1	5760
4	CDMA	2G	\N	MOBILE	2000	1	35000	1	5760
5	EVDO_0	2G	\N	MOBILE	3000	1	35000	1	5760
6	EVDO_A	2G	\N	MOBILE	4000	1	35000	1	5760
7	1xRTT	2G	\N	MOBILE	5000	1	35000	1	5760
8	HSDPA	3G	\N	MOBILE	31000	1	35000	1	5760
9	HSUPA	3G	\N	MOBILE	32000	1	35000	1	5760
10	HSPA	3G	\N	MOBILE	33000	1	35000	1	5760
11	IDEN	2G	\N	MOBILE	1000	1	35000	1	5760
12	EVDO_B	2G	\N	MOBILE	6000	1	35000	1	5760
14	EHRPD	2G	\N	MOBILE	7000	1	35000	1	5760
15	HSPA+	3G	\N	MOBILE	34000	1	35000	1	5760
104	2G/3G/4G	2G/3G/4G	{2G,3G,4G}	MOBILE	0	1	1000000	1	100000
102	3G/4G	3G/4G	{3G,4G}	MOBILE	0	1	1000000	1	100000
1	GSM	2G	\N	MOBILE	20000	1	300	1	300
2	EDGE	2G	\N	MOBILE	21000	1	300	1	300
107	Bluetooth	Bluetooth	\N	LAN	0	1	24000	1	24000
103	2G/4G	2G/4G	{2G,4G}	MOBILE	0	1	1000000	1	100000
16	GSM	2G	\N	MOBILE	20000	1	300	1	300
17	TD SCDMA	3G	\N	MOBILE	35000	1	35000	1	5760
18	IWLAN	4G	\N	MOBILE	42000	1	1000000	1	1000000
13	LTE	4G	\N	MOBILE	40000	1	1000000	1	300000
19	LTE CA	4G	\N	MOBILE	41000	1	1000000	1	300000
108	VPN	VPN	\N	LAN	0	1	100000000	1	100000000
106	Ethernet	Ethernet	\N	LAN	0	1	100000000	1	100000000
98	LAN	LAN	\N	LAN	0	1	100000000	1	100000000
20	NR	5G	\N	MOBILE	50000	1	10000000	1	2500000
41	NR NSA	5G	\N	MOBILE	50000	1	10000000	1	2500000
42	NR NSA	5G	\N	MOBILE	50000	1	10000000	1	2500000
99	WLAN	WLAN	\N	WLAN	0	1	10000000	1	10000000
97	CLI	CLI	\N	CLI	0	1	100000000	1	100000000
105	CELLULAR_ANY	MOBILE	\N	MOBILE	0	1	10000000	1	2500000
0	CELLULAR UNKNOWN	MOBILE	\N	MOBILE	0	1	10000000	1	2500000
40	LTE NR avail	4G	\N	MOBILE	41000	1	10000000	1	2500000
1000	NoNetwork	NoNetwork	\N	MOBILE	0	0	0	0	0
\.


--
-- Name: network_type_uid_seq; Type: SEQUENCE SET; Schema: public; Owner: rmbt
--

SELECT pg_catalog.setval('public.network_type_uid_seq', 16, true);


--
-- PostgreSQL database dump complete
--

\unrestrict KV2CrY0yLUhEuBBfYo6yMp7Rh4SCEiWyzP2MdJu5hCCTDlKyPiAz7742BXpSIB6

