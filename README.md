# Проект 2
Опишите здесь поэтапно ход решения задачи. Вы можете ориентироваться на тот план выполнения проекта, который мы предлагаем в инструкции на платформе.

## Создание справочника стоимости доставки

1. Создаем таблицу public.shipping_country_rates с полями
	- id (первичный ключ)
	- country
	- base_rate
Ни одно поле не может быть null, иначе запись не имеет смысла

```sql
DROP TABLE IF EXISTS public.shipping_country_rates;
CREATE TABLE public.shipping_country_rates(
	id SERIAL NOT NULL,
	country TEXT NOT NULL,
	base_rate NUMERIC(14,3) NOT NULL,
	PRIMARY KEY (id)
);
```

2. Заполняем пустую таблицу данными из `shipping.shipping_country` и `shipping.shipping_country_base_rate`

```sql
INSERT INTO public.shipping_country_rates (country, base_rate)
SELECT
	DISTINCT 
	shipping_country, 
	shipping_country_base_rate
FROM public.shipping s;
```
## Создание справочника тарифов вендора по договору

1. Создаем таблицу public.shipping_agreement с полями
	- agreementid (первичный ключ)
	- agreement_number
	- agreement_rate
Ни одно поле не может быть null, иначе запись не имеет смысла

```sql
DROP TABLE IF EXISTS public.shipping_agreement;
CREATE TABLE public.shipping_agreement(
	agreementid int8  NOT NULL,
	agreement_number TEXT  NOT NULL,
	agreement_rate numeric(14,3)  NOT NULL,
	agreement_commission numeric(14,3)  NOT NULL,
	PRIMARY KEY (agreementid)
);
```

2. Данные для справочника хранятся в `shipping.vendor_agreement_description` строкой с разделением `:`. Разделяем строку и записываем данные


```sql
INSERT INTO public.shipping_agreement
SELECT 
	DISTINCT
	(regexp_split_to_array(vendor_agreement_description, ':'))[1]::BIGINT,
	(regexp_split_to_array(vendor_agreement_description, ':'))[2],
	(regexp_split_to_array(vendor_agreement_description, ':'))[3]::NUMERIC(14,3),
	(regexp_split_to_array(vendor_agreement_description, ':'))[4]::NUMERIC(14,3)
FROM public.shipping s 
ORDER BY 1;
```

## Создание справочника с типами доставки 

1. Создаем таблицу `public.shipping_transfer` с полями
	- id (первичный ключ)
	- transfer_type
	- transfer_model
	- shipping_transfer_rate
Ни одно поле не может быть null, иначе запись не имеет смысла

```sql
DROP TABLE IF EXISTS public.shipping_transfer;
CREATE TABLE public.shipping_transfer(
	id serial NOT NULL,
	transfer_type TEXT NOT NULL,
	transfer_model TEXT NOT NULL,
	shipping_transfer_rate numeric(14,3) NOT NULL,
	PRIMARY KEY (id)
);
```

2. Данные для справочника хранятся в `shipping.shipping_transfer_description` строкой с разделением `:` и в `shipping.shipping_transfer_rate`. Разделяем строку и записываем данные


```sql
INSERT INTO public.shipping_transfer(transfer_type,transfer_model,shipping_transfer_rate)
SELECT 
	DISTINCT 
	(regexp_split_to_array(shipping_transfer_description, ':'))[1],
	(regexp_split_to_array(shipping_transfer_description, ':'))[2],
	shipping_transfer_rate
FROM public.shipping s
ORDER BY 1;
```

## Создание таблицы shipping_info для хранения связи между shippingId и даных из справочников

1. Создаем таблицу `public.shipping_info` с полями
	- shippingid
	- vendorid
	- payment_amount
	- shipping_plan_datetime
	- transfer_type_id (внешний ключ)
	- shipping_country_id (внешний ключ)
	- agreementid (внешний ключ)

```sql
DROP TABLE IF EXISTS public.shipping_info;
CREATE TABLE public.shipping_info(
	shippingid int8 NOT NULL,
	vendorid int8,
	payment_amount numeric(14,2),
	shipping_plan_datetime timestamp,
	transfer_type_id int8, 
	shipping_country_id int8,
	agreementid int8,
	FOREIGN KEY (transfer_type_id) REFERENCES public.shipping_transfer(id) ON UPDATE CASCADE,
	FOREIGN KEY (shipping_country_id) REFERENCES public.shipping_country_rates(id) ON UPDATE CASCADE,
	FOREIGN KEY (agreementid) REFERENCES public.shipping_agreement(agreementid) ON UPDATE CASCADE
);
```

2. Заполняем данными новую таблицу

```sql
INSERT INTO public.shipping_info(shippingid, vendorid, payment_amount, shipping_plan_datetime)
SELECT 
	DISTINCT 
	shippingid,
	vendorid,
	payment_amount,
	shipping_plan_datetime, 
	ship_tr.id, 
	ship_cr.id,
	agreementid
FROM public.shipping s
LEFT JOIN public.shipping_transfer ship_tr 
	ON (regexp_split_to_array(s.shipping_transfer_description, ':'))[1] = ship_tr.transfer_type 
	AND (regexp_split_to_array(s.shipping_transfer_description, ':'))[2] = ship_tr.transfer_model
LEFT JOIN public.shipping_country_rates ship_cr
	ON s.shipping_country= ship_cr.country
LEFT JOIN public.shipping_agreement ship_ag
	ON (regexp_split_to_array(vendor_agreement_description, ':'))[1]::bigint = ship_ag.agreementid 
ORDER BY shippingid);
```

## Создание таблицы с последним статусом о доставке

1. Создаем таблицу `public.shipping_status` с полями
	- shippingid
	- status
	- state
	- shipping_start_fact_datetime
	- shipping_end_fact_datetime

```sql
DROP TABLE IF EXISTS public.shipping_status;
CREATE TABLE public.shipping_status(
	shippingId int8 NOT NULL,
	status TEXT,
	state TEXT,
	shipping_start_fact_datetime timestamp,
	shipping_end_fact_datetime timestamp
);
```

2. Заполянем данными новую таблицу

```sql
-- получаем последний статус каждого shippingid
WITH ship_last_states AS(
SELECT 
	s.shippingid, 
	s.state,
	s.state_datetime,
	s.status,
	ROW_NUMBER() over(PARTITION BY s.shippingid ORDER BY s.state_datetime desc) AS state_order_desc
FROM public.shipping s
ORDER BY s.shippingid),

-- получаем дату старта доставки
ship_booked_state_datetime AS (
SELECT 
	DISTINCT
	s.shippingid,
	s.state_datetime 
FROM public.shipping s
WHERE s.state = 'booked'),

-- получаем дату окончания доставки
ship_recieved_state_datetime AS (
SELECT 
	DISTINCT 
	s.shippingid,
	s.state_datetime 
FROM public.shipping s
WHERE s.state = 'recieved')

-- заполняем таблицу
INSERT INTO public.shipping_status
SELECT 
	sls.shippingid, 
	state, 
	status,
	sbsd.state_datetime,
	srsd.state_datetime
FROM ship_last_states sls
LEFT JOIN ship_booked_state_datetime sbsd 
	ON sbsd.shippingid = ss.shippingid
LEFT JOIN ship_recieved_state_datetime srsd 
	ON srsd.shippingid = ss.shippingid
WHERE state_order_desc = 1
ORDER BY sls.shippingid;
```


## Создание представления на основе готовых событий

```sql
DROP VIEW IF EXISTS public.shipping_datamart;
CREATE VIEW public.shipping_datamart AS
SELECT 
	si.shippingid ,
	vendorid ,
	st.transfer_type,
	date_part('day',ss.shipping_end_fact_datetime - ss.shipping_start_fact_datetime) AS full_day_at_shipping,
	CASE 
		WHEN ss.shipping_end_fact_datetime > si.shipping_plan_datetime THEN TRUE
		ELSE FALSE
	END AS is_dalay,
	CASE 
		WHEN ss.status = 'finished' THEN TRUE
		ELSE FALSE
	END AS is_shipping_finish,
	CASE 
		WHEN ss.shipping_end_fact_datetime > shipping_plan_datetime 
			THEN date_part('day',shipping_end_fact_datetime - shipping_plan_datetime)
		ELSE 0
	END AS delay_day_at_shipping,
	si.payment_amount,
	payment_amount * (base_rate + agreement_rate + shipping_transfer_rate) AS vat,
	payment_amount * agreement_commission AS profit
FROM public.shipping_info si 
JOIN shipping_transfer st
	ON st.id = si.transfer_type_id  
JOIN shipping_status ss 
	ON ss.shippingid = si.shippingid 
JOIN shipping_agreement sa 
	ON sa.agreementid = si.agreementid 
JOIN shipping_country_rates scr 
	ON scr.id = si.shipping_country_id 
ORDER BY si.shippingid;
```
