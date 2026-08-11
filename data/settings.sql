--
-- PostgreSQL database dump
--

\restrict AUaWNeR1ifHUcmiSFzlMgq5UEsjeUosRukZ8qiYKVfsI2qOhDGp659aH47Fwg8C

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
-- Data for Name: settings; Type: TABLE DATA; Schema: public; Owner: rmbt
--

COPY public.settings (uid, key, lang, value) FROM stdin;
3	url_open_data_prefix	\N	https://example.com/en/Opentest?
7	url_open_data_prefix	de	https://example.com/de/Opentest?
12	geo_accuracy_limit_map	\N	2000
13	geo_accuracy_limit_detail	\N	10000
21	system_UUID	\N	d56def98-22d3-452c-af58-1719b8486e59
22	system_name	en	Open-RMBT
23	system_name	de	Open-RMBT
19	control_ipv4_only	\N	c01v4.example.com
20	control_ipv6_only	\N	c01v6.example.com
25	port_map_server	\N	443
26	ssl_map_server	\N	TRUE
39	tc_url_ios	de	https://example.com/de/tc_ios.html
15	url_ipv4_check	\N	https://c01v4.example.com/RMBTControlServer/ip
17	url_ipv6_check	\N	https://c01v6.example.com/RMBTControlServer/ip
40	tc_url_ios	\N	https://example.com/en/tc_ios.html
24	url_map_server	\N	https://m-cloud.example.com/RMBTMapServer
27	host_map_server	\N	m-cloud.example.com
31	url_share	\N	https://example.com/share/
37	tc_url_android_v4	de	https://example.com/de/tc_android.html
32	tc_url_android	de	https://example.com/de/tc_android.html
33	tc_url_android	\N	https://example.com/en/tc_android.html
34	tc_version_android	\N	123
38	tc_url_android_v4	\N	https://example.com/en/tc_android.html
42	tc_url	\N	https://example.com/en/tc.html
41	tc_version_ios	\N	123
43	tc_url	de	https://example.com/de/tc.html
44	tc_version	\N	123
45	tc_url_desktop	de	https://example.com/de/tc_desktop.html
47	tc_version_desktop	\N	123
46	tc_url_desktop	\N	https://example.com/en/tc_desktop.html
48	url_statistic_server	\N	https://app-cloud.example.com/RMBTStatisticServer
11	rmbt_duration	\N	7
49	url_web_statistic_server	\N	https://m-cloud.example.com/RMBTStatisticServer
50	url_web_open_data_server	\N	https://data.example.com/RMBTStatisticServer
51	url_web_recent_server	\N	https://m-cloud.example.com/cache/recent
52	url_web_basemap_tiles	\N	https://mapsneu.wien.gv.at/basemap/{type}/normal/google3857/{z}/{y}/{x}.png
53	url_web_osm_tiles	\N	https://cache.example.com/tile/osm/{z}/{x}/{y}.png
54	max_coverage_measurement_seconds	\N	3600
55	max_coverage_session_seconds	\N	14400
10	rmbt_num_threads	\N	3
56	rmbt_duration_seconds	\N	7
57	rmbt_min_pings	\N	10
9	url_statistics	de	https://example.com/de/statistics#noMMenu
8	url_statistics	\N	https://example.com/en/statistics#noMMenu
58	classification_thresholds	\N	{"download_kbit":{"2":5001,"3":10000,"4":100000},"upload_kbit":{"2":10000,"3":20000,"4":30000},"ping_ms":{"2":75,"3":25,"4":10},"signal_mobile":{"2":-101,"3":-85,"4":-75},"signal_mobile_rsrp":{"2":-111,"3":-95,"4":-85},"signal_wifi":{"2":-76,"3":-61,"4":-51}}
\.


--
-- Name: settings_uid_seq; Type: SEQUENCE SET; Schema: public; Owner: rmbt
--

SELECT pg_catalog.setval('public.settings_uid_seq', 59, true);


--
-- PostgreSQL database dump complete
--

\unrestrict AUaWNeR1ifHUcmiSFzlMgq5UEsjeUosRukZ8qiYKVfsI2qOhDGp659aH47Fwg8C

