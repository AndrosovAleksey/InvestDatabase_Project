-- select * from pg_catalog.pg_available_extensions pae;
-- postgres_fdw - для подключения к удаленному серверу, file_fdw - для файлов
-- create extension postgres_fdw;


-- 1. Создание таблиц в staging
-- 1. advert_source
create schema if not exists t2_stg;

DROP TABLE IF EXISTS t2_stg.staging_advert_source;
CREATE TABLE t2_stg.staging_advert_source (
    advert_source_id VARCHAR(256),
    advert_source_nm VARCHAR(256),
    monthly_payment_amt VARCHAR(256),
    start_month VARCHAR(256),
    end_month VARCHAR(256),
    create_dttm VARCHAR(256),
    delete_dttm VARCHAR(256),
    last_update VARCHAR(256)
);

-- 2. application
DROP TABLE IF EXISTS t2_stg.staging_application;
CREATE TABLE t2_stg.staging_application (
	application_hash_key varchar(32),
	customer_hash_key varchar(32),
	cust_x_app_hash_key varchar(32), -- формируем все ключи-хэши на этом слое
    application_id VARCHAR(256),
    product_type_cd VARCHAR(256),
    customer_id VARCHAR(256),
    advert_source_id VARCHAR(256),
    create_dttm VARCHAR(256),
    delete_dttm VARCHAR(256),
    last_update VARCHAR(256),
    hash_diff varchar(32) -- хэши для сравнения тоже
);

-- 3. cab_customer
DROP TABLE IF EXISTS t2_stg.staging_cab_customer;
CREATE TABLE t2_stg.staging_cab_customer (
	customer_hash_key varchar(32),
    customer_id VARCHAR(256),
    birth_dt VARCHAR(256),
    passport_num VARCHAR(256),
    phone_num VARCHAR(256),
    add_phone_num VARCHAR(256),
    email VARCHAR(256),
    reg_address_txt VARCHAR(256),
    fact_address_txt VARCHAR(256),
    first_nm VARCHAR(256),
    last_nm VARCHAR(256),
    middle_nm VARCHAR(256),
    create_dttm VARCHAR(256),
    delete_dttm VARCHAR(256),
    last_update VARCHAR(256),
    hash_diff varchar(32),
    hash_diff_con VARCHAR(32)
);

-- 4. crm_account
DROP TABLE IF EXISTS t2_stg.staging_crm_account;
CREATE TABLE t2_stg.staging_crm_account (
	account_hash_key varchar(32),
	application_hash_key varchar(32),
	acc_x_app_hash_key varchar(32),
    account_id VARCHAR(256),
    account_type_cd VARCHAR(256),
    account_create_dt VARCHAR(256),
    account_status_cd VARCHAR(256),
    application_id VARCHAR(256),
    create_dttm VARCHAR(256),
    delete_dttm VARCHAR(256),
    last_update VARCHAR(256),
    hash_diff varchar(32)
);

-- 5. crm_account_status
DROP TABLE IF EXISTS t2_stg.staging_crm_account_status;
CREATE TABLE t2_stg.staging_crm_account_status (
    account_status_cd VARCHAR(256),
    account_status_nm VARCHAR(256),
    last_update VARCHAR(256)
);

-- 6. crm_account_status_type
DROP TABLE IF EXISTS t2_stg.staging_crm_account_status_type;
CREATE TABLE t2_stg.staging_crm_account_status_type (
    account_type_cd VARCHAR(256),
    account_type_nm VARCHAR(256),
    last_update VARCHAR(256)
);

-- 7. crm_customer
DROP TABLE IF EXISTS t2_stg.staging_crm_customer;
CREATE TABLE t2_stg.staging_crm_customer (
	customer_hash_key varchar(32),
    crm_customer_id VARCHAR(256),
    customer_id VARCHAR(256),
    birth_dt VARCHAR(256),
    phone_num VARCHAR(256),
    email VARCHAR(256),
    first_nm VARCHAR(256),
    last_nm VARCHAR(256),
    create_dttm VARCHAR(256),
    delete_dttm VARCHAR(256),
    last_update VARCHAR(256),
    hash_diff varchar(32)
);

-- 8. crm_transaction
DROP TABLE IF EXISTS t2_stg.staging_crm_transaction;
CREATE TABLE t2_stg.staging_crm_transaction (
	transaction_hash_key varchar(32),
	orig_transaction_hash_key varchar(32),
	account_hash_key varchar(32),
	acc_x_trans_hash_key varchar(32),
	trans_x_orig_trans_hash_key varchar(32),
    transaction_id VARCHAR(256),
    orig_id VARCHAR(256),
    account_id VARCHAR(256),
    transaction_type_cd VARCHAR(256),
    transaction_amt VARCHAR(256),
    transaction_dttm VARCHAR(256),
    create_dttm VARCHAR(256),
    delete_dttm VARCHAR(256),
    last_update VARCHAR(256),
    hash_diff varchar(32)
);

-- 9. crm_transaction_type
DROP TABLE IF EXISTS t2_stg.staging_crm_transaction_type;
CREATE TABLE t2_stg.staging_crm_transaction_type (
    transaction_type_cd VARCHAR(256),
    transaction_type_nm VARCHAR(256),
    last_update VARCHAR(256)
);

-- 10. product_type
DROP TABLE IF EXISTS t2_stg.staging_product_type;
CREATE TABLE t2_stg.staging_product_type (
    product_type_cd VARCHAR(256),
    product_type_nm VARCHAR(256),
    last_update VARCHAR(256)
);

-- 11. service_request
DROP TABLE IF EXISTS t2_stg.staging_service_request;
CREATE TABLE t2_stg.staging_service_request (
	request_hash_key varchar(32),
	customer_hash_key varchar(32),
	cust_x_req_hash_key varchar(32),
    service_request_id VARCHAR(256),
    customer_id VARCHAR(256),
    service_request_type_cd VARCHAR(256),
    service_request_status_cd VARCHAR(256),
    tail_limit VARCHAR(256),
    create_dttm VARCHAR(256),
    delete_dttm VARCHAR(256),
    last_update VARCHAR(256),
    hash_diff varchar(32)
);

-- 12. service_request_status
DROP TABLE IF EXISTS t2_stg.staging_service_request_status;
CREATE TABLE t2_stg.staging_service_request_status (
    service_request_status_cd VARCHAR(256),
    service_request_status_nm VARCHAR(256),
    last_update VARCHAR(256)
);

-- 13. service_request_type
DROP TABLE IF EXISTS t2_stg.staging_service_request_type;
CREATE TABLE t2_stg.staging_service_request_type (
    service_request_type_cd VARCHAR(256),
    service_request_type_nm VARCHAR(256),
    last_update VARCHAR(256)
);

-- 2. Создание таблицы load_registry

drop table if exists t2_stg.load_registry;

CREATE TABLE t2_stg.load_registry (
    table_name VARCHAR(64),
    load_dttm timestamp
);

-- 3. Загрузка справочников
CREATE OR REPLACE PROCEDURE t2_stg.load_ref_tables()
as $$
DECLARE
    entity TEXT;
    target_schema TEXT := 't2_stg';
    source_schema TEXT := 't1_src';
--	last_load_dttm TIMESTAMP;
    ddl TEXT;
BEGIN
    FOR entity IN 
        SELECT entity_name 
        FROM t1_src.table_metadata 
        WHERE entity_name ILIKE '%type%' OR entity_name ILIKE '%status%'
    LOOP
		
		-- Поддержание историчности
--		EXECUTE format('
--		    SELECT COALESCE(MAX(load_dttm), ''1900-01-01''::timestamp)
--		    FROM t2_stg.load_registry
--		    WHERE table_name = %L
--		', entity)
--		into last_load_dttm;

        -- Очистка перед загрузкой
        EXECUTE format('DELETE FROM %I.staging_%I', target_schema, entity);

        -- Загрузка
        ddl := format('
            INSERT INTO %I.staging_%I 
            SELECT * FROM %I.source_%I;'
			,target_schema, entity
            ,source_schema, entity
--			,last_load_dttm
        );
        EXECUTE ddl;

		-- Обновление в таблице загрузок
--		execute format(
--			'insert into t2_stg.load_registry (
--				table_name,
--				load_dttm
--			)
--			values (
--				%L,
--				now()
--			);', entity
--		);

        RAISE NOTICE 'Наполнена таблица staging_%', entity;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
 

-- 4. Процедура загрузки в staging НЕ справочных таблиц таблиц

-- 4.1 Функция получения записи даты последней загрузки

CREATE OR REPLACE FUNCTION t2_stg.get_last_load(
    IN table_nm TEXT,
    OUT last_load_dttm TIMESTAMP
)
AS $$
BEGIN 
    -- Получаем время последней загрузки
    SELECT COALESCE(MAX(load_dttm), '1900-01-01'::TIMESTAMP)
    INTO last_load_dttm
    FROM t2_stg.load_registry
    WHERE table_name = table_nm;
    -- Возвращаем результат через OUT-параметры
    RETURN;
END;
$$ LANGUAGE plpgsql;



create or replace function t2_stg.record_load(current_dttm timestamp, table_nm text) 
returns void
as $$
begin 
	-- Обновляем реестр версий
    INSERT INTO t2_stg.load_registry (
        table_name,
        load_dttm
    )
    VALUES (
        table_nm,
        current_dttm
    );
end;
$$ language plpgsql;


-- 4.2 Процедуры
create or replace procedure t2_stg.load_staging_advert_source()
language plpgsql
as $$
declare 
	last_load_dttm timestamp;
	table_nm text := 't2_stg.staging_advert_source';
	rows_num int;
begin
	-- Историчность
	last_load_dttm = t2_stg.get_last_load(table_nm);

	truncate t2_stg.staging_advert_source;
	
	INSERT INTO t2_stg.staging_advert_source(
		advert_source_id, 
		advert_source_nm, 
		monthly_payment_amt, 
		start_month, 
		end_month, 
		create_dttm, 
		delete_dttm,
		last_update
	)
	SELECT
		advert_source_id, 
		advert_source_nm, 
		monthly_payment_amt, 
		start_month, 
		end_month, 
		create_dttm, 
		delete_dttm,
		last_update
	from t1_src.source_advert_source sas
	where 1!=1
		or sas.last_update::timestamp >= last_load_dttm
		or sas.delete_dttm::timestamp >= last_load_dttm;

	select (select count(*) from t2_stg.staging_advert_source)
	into rows_num;

	IF rows_num <> 0 THEN
	    PERFORM t2_stg.record_load(NOW()::timestamp, table_nm);
	END IF;

	RAISE NOTICE '%: загружено % записей', 
	table_nm, rows_num;
end;
$$;


create or replace procedure t2_stg.load_staging_application()
language plpgsql
as $$
declare 
	last_load_dttm timestamp;
	table_nm text := 't2_stg.staging_application';
	rows_num int;
begin
	-- Историчность
	last_load_dttm = t2_stg.get_last_load(table_nm);

	truncate t2_stg.staging_application;
	
	INSERT INTO t2_stg.staging_application (
		application_hash_key,
		customer_hash_key,
		cust_x_app_hash_key,
		application_id, 
		product_type_cd, 
		customer_id, 
		advert_source_id, 
		create_dttm, 
		delete_dttm,
		last_update,
    	hash_diff
	)
	SELECT
		upper(md5(upper(trim(coalesce(sa.application_id, ''))))) as application_hash_key,
		upper(md5(upper(trim(coalesce(sa.customer_id, ''))))) as customer_hash_key,
		upper(md5(upper(concat(
			trim(coalesce(sa.customer_id, '')), ':',
			trim(coalesce(sa.application_id, ''))
		)))) as cust_x_app_hash_key,
		sa.application_id, 
		sa.product_type_cd, 
		sa.customer_id, 
		sa.advert_source_id, 
		sa.create_dttm, 
		sa.delete_dttm,
		sa.last_update,
		upper(md5(upper(concat(
			trim(coalesce(spt.product_type_nm, '')), ':',
			trim(coalesce(sa.create_dttm, ''))
		)))) as hash_diff
	from 
		t1_src.source_application sa 
		left join t2_stg.staging_product_type spt using(product_type_cd)
	where 1!=1
		or sa.last_update::timestamp >= last_load_dttm
		or sa.delete_dttm::timestamp >= last_load_dttm;

	select (select count(*) from t2_stg.staging_application)
	into rows_num;

	IF rows_num <> 0 THEN
	    PERFORM t2_stg.record_load(NOW()::timestamp, table_nm);
	END IF;

	RAISE NOTICE '%: загружено % записей', 
	table_nm, rows_num;
	end;
$$;

create or replace procedure t2_stg.load_staging_cab_customer()
language plpgsql
as $$
declare 
	last_load_dttm timestamp;
	table_nm text := 't2_stg.staging_cab_customer';
	rows_num int;
begin
	-- Историчность
	last_load_dttm = t2_stg.get_last_load(table_nm);

	truncate t2_stg.staging_cab_customer;
	
	INSERT INTO t2_stg.staging_cab_customer (
		customer_hash_key,
		customer_id, 
		birth_dt, 
		passport_num, 
		phone_num, 
		add_phone_num, 
		email, 
		reg_address_txt, 
		fact_address_txt, 
		first_nm, 
		last_nm, 
		middle_nm, 
		create_dttm, 
		delete_dttm,
		last_update,
		hash_diff,
		hash_diff_con
	)
	SELECT
		upper(md5(upper(trim(coalesce(customer_id, ''))))) as customer_hash_key,
		customer_id, 
		birth_dt, 
		passport_num, 
		phone_num, 
		add_phone_num, 
		email, 
		reg_address_txt, 
		fact_address_txt, 
		first_nm, 
		last_nm, 
		middle_nm, 
		create_dttm, 
		delete_dttm,
		last_update,
		upper(md5(upper(concat(
			trim(coalesce(first_nm, '')), ':',
			trim(coalesce(last_nm, '')), ':',
			trim(coalesce(middle_nm, '')), ':',
			trim(coalesce(birth_dt, '')), ':',
			trim(coalesce(passport_num, '')), ':',
			trim(coalesce(create_dttm, ''))
		)))) as hash_diff,
		upper(md5(upper(concat(
			trim(coalesce(phone_num, '')), ':',
			trim(coalesce(add_phone_num, '')), ':',
			trim(coalesce(email, '')), ':',
			trim(coalesce(reg_address_txt, '')), ':',
			trim(coalesce(fact_address_txt, ''))
		)))) as hash_diff_c0n
	from t1_src.source_cab_customer scc
	where 1!=1
		or scc.last_update::timestamp >= last_load_dttm
		or scc.delete_dttm::timestamp >= last_load_dttm;

	select (select count(*) from t2_stg.staging_cab_customer)
	into rows_num;

	IF rows_num <> 0 THEN
	    PERFORM t2_stg.record_load(NOW()::timestamp, table_nm);
	END IF;

	RAISE NOTICE '%: загружено % записей', 
	table_nm, rows_num;
end;
$$;

create or replace procedure t2_stg.load_staging_crm_account()
language plpgsql
as $$
declare 
	last_load_dttm timestamp;
	table_nm text := 't2_stg.staging_crm_account';
	rows_num int;
begin
	-- Историчность
	last_load_dttm = t2_stg.get_last_load(table_nm);

	truncate t2_stg.staging_crm_account;
	
	INSERT INTO t2_stg.staging_crm_account (
		account_hash_key,
		application_hash_key,
		acc_x_app_hash_key,
		account_id, 
		account_type_cd, 
		account_create_dt, 
		account_status_cd, 
		application_id, 
		create_dttm, 
		delete_dttm,
		last_update,
		hash_diff
	)
	SELECT
		upper(md5(upper(trim(coalesce(sca.account_id, ''))))) as account_hash_key,
		upper(md5(upper(trim(coalesce(sca.application_id, ''))))) as application_hash_key,
		upper(md5(upper(concat(
			trim(coalesce(sca.account_id, '')), ':',
			trim(coalesce(sca.application_id, ''))
		)))) as acc_x_app_hash_key,
		sca.account_id, 
		sca.account_type_cd, 
		sca.account_create_dt, 
		sca.account_status_cd, 
		sca.application_id, 
		sca.create_dttm, 
		sca.delete_dttm,
		sca.last_update,
		upper(md5(upper(concat(
			trim(coalesce(sast.account_type_nm, '')), ':',
			trim(coalesce(sca.account_create_dt, '')), ':',
			trim(coalesce(sca.create_dttm, ''))
		)))) as hash_diff
	from 
		t1_src.source_crm_account sca
		left join t2_stg.staging_crm_account_status_type sast using(account_type_cd)
	where 1!=1
		or sca.last_update::timestamp >= last_load_dttm
		or sca.delete_dttm::timestamp >= last_load_dttm;

	select (select count(*) from t2_stg.staging_crm_account)
	into rows_num;

	IF rows_num <> 0 THEN
	    PERFORM t2_stg.record_load(NOW()::timestamp, table_nm);
	END IF;

	RAISE NOTICE '%: загружено % записей', 
	table_nm, rows_num;
end;
$$;

create or replace procedure t2_stg.load_staging_crm_customer()
language plpgsql
as $$
declare 
	last_load_dttm timestamp;
	table_nm text := 't2_stg.staging_crm_customer';
	rows_num int;
begin
	-- Историчность
	last_load_dttm = t2_stg.get_last_load(table_nm);

	truncate t2_stg.staging_crm_customer;
	
	INSERT INTO t2_stg.staging_crm_customer (
		customer_hash_key,
		crm_customer_id, 
		customer_id, birth_dt, 
		phone_num, 
		email, 
		first_nm, 
		last_nm, 
		create_dttm, 
		delete_dttm,
		last_update,
		hash_diff
	)
	SELECT
		upper(md5(upper(trim(coalesce(customer_id, ''))))) as customer_hash_key,
		crm_customer_id, 
		customer_id, 
		birth_dt, 
		phone_num, 
		email, 
		first_nm, 
		last_nm, 
		create_dttm, 
		delete_dttm,
		last_update,
		upper(md5(upper(concat(
			trim(coalesce(first_nm, '')), ':',
			trim(coalesce(last_nm, '')), ':',
			trim(coalesce(birth_dt, '')), ':',
			trim(coalesce(create_dttm, ''))
		)))) as hash_diff
	from t1_src.source_crm_customer scc
	where 1!=1
		or scc.last_update::timestamp >= last_load_dttm
		or scc.delete_dttm::timestamp >= last_load_dttm;

	select (select count(*) from t2_stg.staging_crm_customer)
	into rows_num;

	IF rows_num <> 0 THEN
	    PERFORM t2_stg.record_load(NOW()::timestamp, table_nm);
	END IF;

	RAISE NOTICE '%: загружено % записей', 
	table_nm, rows_num;
end;
$$;

create or replace procedure t2_stg.load_staging_crm_transaction()
language plpgsql
as $$
declare 
	last_load_dttm timestamp;
	table_nm text := 't2_stg.staging_crm_transaction';
	rows_num int;
begin
	-- Историчность
	last_load_dttm = t2_stg.get_last_load(table_nm);

	truncate t2_stg.staging_crm_transaction;
	
	INSERT INTO t2_stg.staging_crm_transaction (
		transaction_hash_key,
		orig_transaction_hash_key,
		account_hash_key,
		acc_x_trans_hash_key,
		trans_x_orig_trans_hash_key,
		transaction_id, 
		orig_id, 
		account_id, 
		transaction_type_cd, 
		transaction_amt, 
		transaction_dttm, 
		create_dttm, 
		delete_dttm,
		last_update,
		hash_diff
	)
	SELECT
		upper(md5(upper(trim(coalesce(sct.transaction_id, ''))))) as transaction_hash_key,
		upper(md5(upper(trim(coalesce(sct.orig_id, ''))))) as orig_transaction_hash_key,
		upper(md5(upper(trim(coalesce(sct.account_id, ''))))) as account_hash_key,
		upper(md5(upper(concat(
			trim(coalesce(sct.account_id, '')), ':',
			trim(coalesce(sct.transaction_id, ''))
		)))) as acc_x_trans_hash_key,
		upper(md5(upper(concat(
			trim(coalesce(sct.transaction_id, '')), ':',
			trim(coalesce(sct.orig_id, ''))
		)))) as trans_x_orig_trans_hash_key,
		sct.transaction_id, 
		sct.orig_id, 
		sct.account_id, 
		sct.transaction_type_cd, 
		sct.transaction_amt, 
		sct.transaction_dttm, 
		sct.create_dttm, 
		sct.delete_dttm,
		sct.last_update,
		upper(md5(upper(concat(
			trim(coalesce(sct.transaction_amt, '')), ':',
			trim(coalesce(sct.transaction_dttm, '')), ':',
			trim(coalesce(sctt.transaction_type_nm, '')), ':',
			trim(coalesce(sct.create_dttm, ''))
		)))) as hash_diff
	from 
		t1_src.source_crm_transaction sct
		left join t2_stg.staging_crm_transaction_type sctt using(transaction_type_cd)
	where 1!=1
		or sct.last_update::timestamp >= last_load_dttm
		or sct.delete_dttm::timestamp >= last_load_dttm;

	select (select count(*) from t2_stg.staging_crm_transaction)
	into rows_num;

	IF rows_num <> 0 THEN
	    PERFORM t2_stg.record_load(NOW()::timestamp, table_nm);
	END IF;

	RAISE NOTICE '%: загружено % записей', 
	table_nm, rows_num;
end;
$$;

create or replace procedure t2_stg.load_staging_service_request()
language plpgsql
as $$
declare 
	last_load_dttm timestamp;
	table_nm text := 't2_stg.staging_service_request';
	rows_num int;
begin
	-- Историчность
	last_load_dttm = t2_stg.get_last_load(table_nm);

	truncate t2_stg.staging_service_request;
	
	INSERT INTO t2_stg.staging_service_request (
		request_hash_key,
		customer_hash_key,
		cust_x_req_hash_key,
		service_request_id, 
		customer_id, 
		service_request_type_cd, 
		service_request_status_cd, 
		tail_limit, 
		create_dttm, 
		delete_dttm,
		hash_diff
	)
	SELECT
		upper(md5(upper(trim(coalesce(ssr.service_request_id, ''))))) as request_hash_key,
		upper(md5(upper(trim(coalesce(ssr.customer_id, ''))))) as customer_hash_key,
		upper(md5(upper(concat(
			trim(coalesce(ssr.customer_id, '')), ':',
			trim(coalesce(ssr.service_request_id, ''))
		)))) as cust_x_req_hash_key,
		ssr.service_request_id, 
		ssr.customer_id, 
		ssr.service_request_type_cd, 
		ssr.service_request_status_cd, 
		ssr.tail_limit, 
		ssr.create_dttm, 
		ssr.delete_dttm,
		upper(md5(upper(concat(
			trim(coalesce(ssr.tail_limit, '')), ':',
			trim(coalesce(ssrt.service_request_type_nm, '')), ':',
			trim(coalesce(ssr.create_dttm, ''))
		)))) as hash_diff
	from 
		t1_src.source_service_request ssr
		left join t2_stg.staging_service_request_type ssrt using(service_request_type_cd)
	where 1!=1
		or ssr.last_update::timestamp >= last_load_dttm
		or ssr.delete_dttm::timestamp >= last_load_dttm;

	select (select count(*) from t2_stg.staging_service_request)
	into rows_num;

	IF rows_num <> 0 THEN
	    PERFORM t2_stg.record_load(NOW()::timestamp, table_nm);
	END IF;

	RAISE NOTICE '%: загружено % записей', 
	table_nm, rows_num;
end;
$$;

call t2_stg.load_ref_tables();

call t2_stg.load_staging_advert_source();
call t2_stg.load_staging_application();
call t2_stg.load_staging_cab_customer();
call t2_stg.load_staging_crm_account();
call t2_stg.load_staging_crm_customer();
call t2_stg.load_staging_crm_transaction();
call t2_stg.load_staging_service_request();
