DROP TABLE IF EXISTS public.shipping_country_rates;
CREATE TABLE public.shipping_country_rates(
	id SERIAL NOT NULL,
	country TEXT NOT NULL,
	base_rate NUMERIC(14,3) NOT NULL,
	PRIMARY KEY (id)
);


INSERT INTO public.shipping_country_rates (country, base_rate)
SELECT
	DISTINCT 
	shipping_country, 
	shipping_country_base_rate
FROM public.shipping s;


DROP TABLE IF EXISTS public.shipping_agreement;
CREATE TABLE public.shipping_agreement(
	agreementid int8  NOT NULL,
	agreement_number TEXT  NOT NULL,
	agreement_rate numeric(14,3)  NOT NULL,
	agreement_commission numeric(14,3)  NOT NULL,
	PRIMARY KEY (agreementid)
);

INSERT INTO public.shipping_agreement
SELECT 
	DISTINCT
	(regexp_split_to_array(vendor_agreement_description, ':'))[1]::BIGINT,
	(regexp_split_to_array(vendor_agreement_description, ':'))[2],
	(regexp_split_to_array(vendor_agreement_description, ':'))[3]::NUMERIC(14,3),
	(regexp_split_to_array(vendor_agreement_description, ':'))[4]::NUMERIC(14,3)
FROM public.shipping s 
ORDER BY 1;


DROP TABLE IF EXISTS public.shipping_transfer;
CREATE TABLE public.shipping_transfer(
	id serial NOT NULL,
	transfer_type TEXT NOT NULL,
	transfer_model TEXT NOT NULL,
	shipping_transfer_rate numeric(14,3) NOT NULL,
	PRIMARY KEY (id)
);

INSERT INTO public.shipping_transfer(transfer_type,transfer_model,shipping_transfer_rate)
SELECT 
	DISTINCT 
	(regexp_split_to_array(shipping_transfer_description, ':'))[1],
	(regexp_split_to_array(shipping_transfer_description, ':'))[2],
	shipping_transfer_rate
FROM public.shipping s
ORDER BY 1;


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
ORDER BY shippingid)


DROP TABLE IF EXISTS public.shipping_status;
CREATE TABLE public.shipping_status(
	shippingId int8 NOT NULL,
	status TEXT,
	state TEXT,
	shipping_start_fact_datetime timestamp,
	shipping_end_fact_datetime timestamp
);


WITH ship_last_states AS(
SELECT 
	s.shippingid, 
	s.state,
	s.state_datetime,
	s.status,
	ROW_NUMBER() over(PARTITION BY s.shippingid ORDER BY s.state_datetime desc) AS state_order_desc
FROM public.shipping s
ORDER BY s.shippingid),

ship_booked_state_datetime AS (
SELECT 
	DISTINCT
	s.shippingid,
	s.state_datetime 
FROM public.shipping s
WHERE s.state = 'booked'),

ship_recieved_state_datetime AS (
SELECT 
	DISTINCT 
	s.shippingid,
	s.state_datetime 
FROM public.shipping s
WHERE s.state = 'recieved')

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
LEFT JOIN shipping_transfer st
	ON st.id = si.transfer_type_id  
LEFT JOIN shipping_status ss 
	ON ss.shippingid = si.shippingid 
LEFT JOIN shipping_agreement sa 
	ON sa.agreementid = si.agreementid 
LEFT JOIN shipping_country_rates scr 
	ON scr.id = si.shipping_country_id 
ORDER BY si.shippingid;

-- я почему-то подумала, что JOIN == LEFT JOIN, но на самом деле JOIN == INNER JOIN 

