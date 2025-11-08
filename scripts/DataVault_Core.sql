-- DLL
-- 1. Создание схемы и таблицы версий
CREATE SCHEMA IF NOT EXISTS t3_core;

drop table if exists t3_core.load_version_registry;
CREATE TABLE t3_core.load_version_registry (
    table_name TEXT,
    load_dttm timestamp,
    version_id INT NOT NULL DEFAULT 0,
    PRIMARY KEY (table_name, version_id)
);

-- 2. Функции для таблицы версий

create or replace
function t3_core.get_last_version_load(
    in table_nm TEXT,
    out last_load_dttm TIMESTAMP,
    out next_version INT
)
as $$
begin
	-- Получаем время последней загрузки
    select
	coalesce(MAX(load_dttm), '1900-01-01'::TIMESTAMP)
    into
	last_load_dttm
	from
	t3_core.load_version_registry
	where
	table_name = table_nm;

	-- Получаем следующую версию
    select
	coalesce(MAX(version_id), 0) + 1
    into
	next_version
	from
	t3_core.load_version_registry
	where
	table_name = table_nm;
	-- Если записей не было — начинаем с 1
    if next_version is null then
        next_version := 1;
	end if;
	-- Возвращаем результат через OUT-параметры
    return;
end;

$$ language plpgsql;



create or replace function t3_core.record_version_load(current_dttm timestamp, next_version int, table_nm text) 
returns void
as $$
begin 
	-- Обновляем реестр версий
    INSERT INTO t3_core.load_version_registry (
        table_name,
        load_dttm,
        version_id
    )
    VALUES (
        table_nm,
        current_dttm,
        next_version
    );
end;
$$ language plpgsql;

-- 3. Создаем таблицы
-- Хабы
drop table if exists t3_core.HUB_account;
CREATE TABLE t3_core.HUB_account (
    account_hash_key VARCHAR(32) PRIMARY KEY,
    account_id VARCHAR(256),
    load_dttm TIMESTAMP,
    src_cd VARCHAR(8)
);

drop table if exists t3_core.HUB_customer;
CREATE TABLE t3_core.HUB_customer (
    customer_hash_key VARCHAR(32) PRIMARY KEY,
    customer_id VARCHAR(256),
    crm_customer_id VARCHAR(256),
    load_dttm TIMESTAMP,
    src_cd VARCHAR(8)
);

drop table if exists t3_core.HUB_request;
CREATE TABLE t3_core.HUB_request (
    request_hash_key VARCHAR(32) PRIMARY KEY,
    service_request_id VARCHAR(256),
    load_dttm TIMESTAMP,
    src_cd VARCHAR(8)
);

drop table if exists t3_core.HUB_transaction;
CREATE TABLE t3_core.HUB_transaction (
    transaction_hash_key VARCHAR(32) PRIMARY KEY,
    transaction_id VARCHAR(256),
    load_dttm TIMESTAMP,
    src_cd VARCHAR(8)
);

drop table if exists t3_core.HUB_application;
CREATE TABLE t3_core.HUB_application (
    application_hash_key VARCHAR(32) PRIMARY KEY,
    application_id VARCHAR(256),
    load_dttm TIMESTAMP,
    src_cd VARCHAR(8)
);

-- Линки
drop table if exists t3_core.LINK_acc_x_app;
CREATE TABLE t3_core.LINK_acc_x_app (
    acc_x_app_hash_key VARCHAR(32) PRIMARY KEY,
    account_hash_key VARCHAR(32),
    application_hash_key VARCHAR(32),
    load_dttm TIMESTAMP,
    src_cd VARCHAR(8)
);


drop table if exists t3_core.LINK_cust_x_app;
CREATE TABLE t3_core.LINK_cust_x_app (
    cust_x_app_hash_key VARCHAR(32) PRIMARY KEY,
    customer_hash_key VARCHAR(32),
    application_hash_key VARCHAR(32),
    load_dttm TIMESTAMP,
    src_cd VARCHAR(8)
);



drop table if exists t3_core.LINK_cust_x_req;
CREATE TABLE t3_core.LINK_cust_x_req (
    cust_x_req_hash_key VARCHAR(32) PRIMARY KEY,
    request_hash_key VARCHAR(32),
    customer_hash_key VARCHAR(32),
    load_dttm TIMESTAMP,
    src_cd VARCHAR(8)
);


drop table if exists t3_core.LINK_acc_x_trans;
CREATE TABLE t3_core.LINK_acc_x_trans (
    acc_x_trans_hash_key VARCHAR(32) PRIMARY KEY,
    account_hash_key VARCHAR(32),
    transaction_hash_key VARCHAR(32),
    load_dttm TIMESTAMP,
    src_cd VARCHAR(8)
);

drop table if exists t3_core.LINK_trans_x_orig_trans;
CREATE TABLE t3_core.LINK_trans_x_orig_trans (
    trans_x_orig_trans_hash_key VARCHAR(32) PRIMARY KEY,
    transaction_hash_key VARCHAR(32),
    orig_transaction_hash_key VARCHAR(32),
    load_dttm TIMESTAMP,
    src_cd VARCHAR(8)
);

-- Сателлиты (HSAT — хаб-сателлиты, LSAT — линк-сателлиты)

-- HSAT: HUB_account
drop table if exists t3_core.HSAT_account;
CREATE TABLE t3_core.HSAT_account (
    account_hash_key VARCHAR(32),
    version_id BIGINT,
    hash_diff VARCHAR(32),
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    account_type_nm VARCHAR(256),
    account_create_dt DATE,
    create_dt DATE,
    delete_dt DATE,
    PRIMARY KEY (account_hash_key, version_id)
);

-- HSAT: HUB_account_status
drop table if exists t3_core.HSAT_account_status;
CREATE TABLE t3_core.HSAT_account_status (
    account_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    account_status_nm VARCHAR(256),
    PRIMARY KEY (account_hash_key, version_id)
);

-- HSAT: HUB_application
drop table if exists t3_core.HSAT_application;
CREATE TABLE t3_core.HSAT_application (
    application_hash_key VARCHAR(32),
    version_id BIGINT,
    hash_diff VARCHAR(32),
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    product_type_nm VARCHAR(256),
    create_dt DATE,
    delete_dt DATE,
    PRIMARY KEY (application_hash_key, version_id)
);

-- HSAT: HUB_customer
drop table if exists t3_core.HSAT_crm_customer;
CREATE TABLE t3_core.HSAT_crm_customer (
    customer_hash_key VARCHAR(32),
    version_id BIGINT,
    hash_diff VARCHAR(32),
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    first_nm VARCHAR(256),
    last_nm VARCHAR(256),
    birth_dt DATE,
    create_dt DATE,
    delete_dt DATE,
    PRIMARY KEY (customer_hash_key, version_id)
);

drop table if exists t3_core.HSAT_cab_customer;
CREATE TABLE t3_core.HSAT_cab_customer (
    customer_hash_key VARCHAR(32),
    version_id BIGINT,
    hash_diff VARCHAR(32),
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    first_nm VARCHAR(256),
    last_nm VARCHAR(256),
    middle_nm VARCHAR(256),
    birth_dt DATE,
    passport_num VARCHAR(256),
    create_dt DATE,
    delete_dt DATE,
    PRIMARY KEY (customer_hash_key, version_id)
);

drop table if exists t3_core.HSAT_crm_customer_contact;
CREATE TABLE t3_core.HSAT_crm_customer_contact (
    customer_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    phone_num TEXT,
    email VARCHAR(256),
    PRIMARY KEY (customer_hash_key, version_id)
);

drop table if exists t3_core.HSAT_cab_customer_contact;
CREATE TABLE t3_core.HSAT_cab_customer_contact (
    customer_hash_key VARCHAR(32),
    version_id BIGINT,
    hash_diff_con VARCHAR(32),
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    phone_num TEXT,
    add_phone_num TEXT,
    email VARCHAR(256),
    reg_address_txt VARCHAR(256),
    fact_address_txt VARCHAR(256),
    PRIMARY KEY (customer_hash_key, version_id)
);

drop table if exists t3_core.HSAT_request;
-- HSAT: HUB_request
CREATE TABLE t3_core.HSAT_request (
    request_hash_key VARCHAR(32),
    version_id BIGINT,
    hash_diff VARCHAR(32),
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    tail_limit INT4,
    service_request_type_nm VARCHAR(256),
    create_dt DATE,
    delete_dt DATE,
    PRIMARY KEY (request_hash_key, version_id)
);

drop table if exists t3_core.HSAT_request_status;
CREATE TABLE t3_core.HSAT_request_status (
    request_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    service_request_status_nm VARCHAR(256),
    PRIMARY KEY (request_hash_key, version_id)
);

-- HSAT: HUB_transaction
drop table if exists t3_core.HSAT_transaction;
CREATE TABLE t3_core.HSAT_transaction (
    transaction_hash_key VARCHAR(32),
    version_id BIGINT,
    hash_diff VARCHAR(32),
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    transaction_amt FLOAT,
    transaction_type_nm VARCHAR(256),
    transaction_dttm TIMESTAMP,
    create_dt DATE,
    delete_dt DATE,
    PRIMARY KEY (transaction_hash_key, version_id)
);


-- LSAT: LINK_acc_x_app
drop table if exists t3_core.LSAT_acc_x_app;
CREATE TABLE t3_core.LSAT_acc_x_app (
    acc_x_app_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    PRIMARY KEY (acc_x_app_hash_key, version_id)
);

-- LSAT: LINK_cust_x_app
drop table if exists t3_core.LSAT_cust_x_app;
CREATE TABLE t3_core.LSAT_cust_x_app (
    cust_x_app_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    PRIMARY KEY (cust_x_app_hash_key, version_id)
);


-- LSAT: LINK_cust_x_req
drop table if exists t3_core.LSAT_cust_x_req;
CREATE TABLE t3_core.LSAT_cust_x_req (
    cust_x_req_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    PRIMARY KEY (cust_x_req_hash_key, version_id)
);

-- LSAT: LINK_acc_x_trans
drop table if exists t3_core.LSAT_acc_x_trans;
CREATE TABLE t3_core.LSAT_acc_x_trans (
    acc_x_trans_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    PRIMARY KEY (acc_x_trans_hash_key, version_id)
);

-- LSAT: LINK_trans_x_orig_trans
drop table if exists t3_core.LSAT_trans_x_orig_trans;
CREATE TABLE t3_core.LSAT_trans_x_orig_trans (
    trans_x_orig_trans_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    PRIMARY KEY (trans_x_orig_trans_hash_key, version_id)
);



-- 4. ПРОЦЕДУРЫ

-- ЗАГРУЖАЕМ ХАБЫ
create or replace procedure t3_core.load_hub_account()
as $$
declare
--  next_version INT;
--	last_load_dttm TIMESTAMP;
	load_table_name TEXT := 't3_core.HUB_account';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
    -- 1. Историчность и версионность
	-- SELECT * INTO last_load_dttm, next_version
    -- FROM t3_core.get_last_version_load(load_table_name);

    -- 2. Создаём временную таблицу для новых данных, которые нужно добавить
    CREATE UNLOGGED TABLE staging_data AS
    SELECT 
		t.account_hash_key,
        t.account_id
    FROM (
    	SELECT distinct account_hash_key, account_id FROM t2_stg.staging_crm_account -- целевая таблица
    	UNION
    	SELECT distinct account_hash_key, account_id FROM t2_stg.staging_crm_transaction -- дамми из транзакций
	) t;


	-- 3. Есть ли записи для вставки?

	select (		
		select count(*) 
		from staging_data sd
		WHERE NOT EXISTS (
        	SELECT 1 FROM t3_core.HUB_account h
			WHERE h.account_hash_key = sd.account_hash_key
    		)
	) into rows_num;

	IF rows_num = 0 
		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', load_table_name;
		drop table staging_data;
    	RETURN;  -- Досрочный выход из процедуры
	END IF;
 

    -- 4. Вставляем только новые account_id
    INSERT INTO t3_core.HUB_account (
		account_hash_key, 
		account_id, 
		load_dttm, 
		src_cd)
    SELECT
        sd.account_hash_key,
        sd.account_id,
        current_dttm,
        'CRM'
    FROM staging_data sd
    WHERE NOT EXISTS (
        SELECT 1 FROM t3_core.HUB_account h
		WHERE h.account_hash_key = sd.account_hash_key
    );

	-- 5. Обновляем реестр версий
    -- PERFORM t3_core.record_version_load(current_dttm, next_version, load_table_name);


	drop table staging_data;
	RAISE NOTICE '%: загружено % записей в CORE слой', 
	load_table_name, rows_num;
END;
$$ language plpgsql;


create or replace procedure t3_core.load_hub_customer()
as $$
declare
--  next_version INT;
--	last_load_dttm TIMESTAMP;
	load_table_name TEXT := 't3_core.HUB_customer';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
    -- 1. Историчность и версионность
	-- SELECT * INTO last_load_dttm, next_version
    -- FROM t3_core.get_last_version_load(load_table_name);

    -- 2. Создаём временную таблицу для новых данных, которые нужно добавить
    CREATE UNLOGGED TABLE staging_data AS
    SELECT 
		t.customer_hash_key,
        t.customer_id
    FROM (
    	SELECT distinct customer_hash_key, customer_id FROM t2_stg.staging_cab_customer -- целевая таблица cab
    	UNION
    	SELECT distinct customer_hash_key, customer_id FROM t2_stg.staging_crm_customer -- целевая таблица crm
    	UNION
    	SELECT distinct customer_hash_key, customer_id FROM t2_stg.staging_application -- дамми из application
    	UNION
    	SELECT distinct customer_hash_key, customer_id FROM t2_stg.staging_service_request -- дамми из source_request
	) t;


	-- 3. Есть ли записи для вставки?

	select (		
		select count(*) 
		from staging_data sd
		WHERE NOT EXISTS (
        	SELECT 1 FROM t3_core.HUB_customer h
			WHERE h.customer_hash_key = sd.customer_hash_key
    		)
	) into rows_num;

	IF rows_num = 0 
		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', load_table_name;
		drop table staging_data;
    	RETURN;  -- Досрочный выход из процедуры
	END IF;
 

    -- 4. Вставляем только новые customer_id
    INSERT INTO t3_core.HUB_customer (
		customer_hash_key, 
		customer_id, 
		load_dttm, 
		src_cd)
    SELECT
        sd.customer_hash_key,
        sd.customer_id,
        current_dttm,
        'CAB'
    FROM staging_data sd
    WHERE NOT EXISTS (
        SELECT 1 FROM t3_core.HUB_customer h
		WHERE h.customer_hash_key = sd.customer_hash_key
    );

	-- 5. Обновляем реестр версий
    -- PERFORM t3_core.record_version_load(current_dttm, next_version, load_table_name);

	drop table staging_data;
	RAISE NOTICE '%: загружено % записей в CORE слой', 
	load_table_name, rows_num;
END;
$$ language plpgsql;


create or replace procedure t3_core.load_hub_request()
as $$
declare
--  next_version INT;
--	last_load_dttm TIMESTAMP;
	load_table_name TEXT := 't3_core.HUB_request';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
    -- 1. Историчность и версионность
	-- SELECT * INTO last_load_dttm, next_version
    -- FROM t3_core.get_last_version_load(load_table_name);

    -- 2. Создаём временную таблицу для новых данных, которые нужно добавить
    CREATE UNLOGGED TABLE staging_data AS
    SELECT 
		t.request_hash_key,
        t.service_request_id
    FROM (
    	SELECT distinct request_hash_key, service_request_id FROM t2_stg.staging_service_request -- целевая таблица
	) t;


	-- 3. Есть ли записи для вставки?

	select (		
		select count(*) 
		from staging_data sd
		WHERE NOT EXISTS (
        	SELECT 1 FROM t3_core.HUB_request h
			WHERE h.request_hash_key = sd.request_hash_key
    		)
	) into rows_num;

	IF rows_num = 0 
		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', load_table_name;
		drop table staging_data;
    	RETURN;  -- Досрочный выход из процедуры
	END IF;
 

    -- 4. Вставляем только новые request_id
    INSERT INTO t3_core.HUB_request (
		request_hash_key, 
		service_request_id, 
		load_dttm, 
		src_cd)
    SELECT
        sd.request_hash_key,
        sd.service_request_id,
        current_dttm,
        'CAB'
    FROM staging_data sd
    WHERE NOT EXISTS (
        SELECT 1 FROM t3_core.HUB_request h
		WHERE h.request_hash_key = sd.request_hash_key
    );

	-- 5. Обновляем реестр версий
    -- PERFORM t3_core.record_version_load(current_dttm, next_version, load_table_name);
	
	drop table staging_data;
	RAISE NOTICE '%: загружено % записей в CORE слой', 
	load_table_name, rows_num;
END;
$$ language plpgsql;


create or replace procedure t3_core.load_hub_transaction()
as $$
declare
--  next_version INT;
--	last_load_dttm TIMESTAMP;
	load_table_name TEXT := 't3_core.HUB_transaction';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
    -- 1. Историчность и версионность
	-- SELECT * INTO last_load_dttm, next_version
    -- FROM t3_core.get_last_version_load(load_table_name);

    -- 2. Создаём временную таблицу для новых данных, которые нужно добавить
    CREATE UNLOGGED TABLE staging_data AS
    SELECT 
		t.transaction_hash_key,
        t.transaction_id
    FROM (
    	SELECT distinct transaction_hash_key, transaction_id FROM t2_stg.staging_crm_transaction -- целевая таблица
		union
		SELECT distinct orig_transaction_hash_key, orig_id FROM t2_stg.staging_crm_transaction -- целевая таблица
	) t;


	-- 3. Есть ли записи для вставки?

	select (		
		select count(*) 
		from staging_data sd
		WHERE NOT EXISTS (
        	SELECT 1 FROM t3_core.HUB_transaction h
			WHERE h.transaction_hash_key = sd.transaction_hash_key
    		)
	) into rows_num;

	IF rows_num = 0 
		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', load_table_name;
		drop table staging_data;
    	RETURN;  -- Досрочный выход из процедуры
	END IF;
 

    -- 4. Вставляем только новые transaction_id
    INSERT INTO t3_core.HUB_transaction (
		transaction_hash_key, 
		transaction_id, 
		load_dttm, 
		src_cd)
    SELECT
        sd.transaction_hash_key,
        sd.transaction_id,
        current_dttm,
        'CRM'
    FROM staging_data sd
    WHERE NOT EXISTS (
        SELECT 1 FROM t3_core.HUB_transaction h
		WHERE h.transaction_hash_key = sd.transaction_hash_key
    );

	-- 5. Обновляем реестр версий
    -- PERFORM t3_core.record_version_load(current_dttm, next_version, load_table_name);

	drop table staging_data;
	RAISE NOTICE '%: загружено % записей в CORE слой', 
	load_table_name, rows_num;
END;
$$ language plpgsql;


create or replace procedure t3_core.load_hub_application()
as $$
declare
--  next_version INT;
--	last_load_dttm TIMESTAMP;
	load_table_name TEXT := 't3_core.HUB_application';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
    -- 1. Историчность и версионность
	-- SELECT * INTO last_load_dttm, next_version
    -- FROM t3_core.get_last_version_load(load_table_name);

    -- 2. Создаём временную таблицу для новых данных, которые нужно добавить
    CREATE UNLOGGED TABLE staging_data AS
    SELECT 
		t.application_hash_key,
        t.application_id
    FROM (
    	SELECT distinct application_hash_key, application_id FROM t2_stg.staging_application -- целевая таблица
		union
		SELECT distinct application_hash_key, application_id FROM t2_stg.staging_crm_account -- целевая таблица
	) t;


	-- 3. Есть ли записи для вставки?

	select (		
		select count(*) 
		from staging_data sd
		WHERE NOT EXISTS (
        	SELECT 1 FROM t3_core.HUB_application h
			WHERE h.application_hash_key = sd.application_hash_key
    		)
	) into rows_num;

	IF rows_num = 0 
		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', load_table_name;
		drop table staging_data;
    	RETURN;  -- Досрочный выход из процедуры
	END IF;
 

    -- 4. Вставляем только новые application_id
    INSERT INTO t3_core.HUB_application (
		application_hash_key, 
		application_id, 
		load_dttm, 
		src_cd)
    SELECT
        sd.application_hash_key,
        sd.application_id,
        current_dttm,
        'CRM'
    FROM staging_data sd
    WHERE NOT EXISTS (
        SELECT 1 FROM t3_core.HUB_application h
		WHERE h.application_hash_key = sd.application_hash_key
    );

	-- 5. Обновляем реестр версий
    -- PERFORM t3_core.record_version_load(current_dttm, next_version, load_table_name);

	drop table staging_data;
	RAISE NOTICE '%: загружено % записей в CORE слой', 
	load_table_name, rows_num;
END;
$$ language plpgsql;



call t3_core.load_hub_account();
call t3_core.load_hub_customer();
call t3_core.load_hub_request();
call t3_core.load_hub_transaction();
call t3_core.load_hub_application();


-- ЗАГРУЖАЕМ ЛИНКИ (и их хабы)

--ACCOUNT_X_APPLICATION
create or replace procedure t3_core.load_acc_x_app()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	link_table_name TEXT := 't3_core.LINK_acc_x_app'; 
	lsat_table_name TEXT := 't3_core.LSAT_acc_x_app'; -- историчность - в LSAT
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
--     1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(lsat_table_name);

    -- 2. Создаём временную таблицу для новых данных, которые нужно добавить
    CREATE UNLOGGED TABLE staging_data AS
    SELECT 
		t.acc_x_app_hash_key,
		t.account_hash_key,
		t.application_hash_key,
		t.delete_dttm
    FROM (
    	SELECT 
			distinct
			acc_x_app_hash_key,
			account_hash_key,
			application_hash_key,
			delete_dttm 
		FROM t2_stg.staging_crm_account
	) t;

	-- 3. Есть ли записи для вставки в LSAT?

	select (		
		select count(*) 
		from staging_data sd
    	left join (
			select *
			from t3_core.LSAT_acc_x_app 
			where effective_to_dttm = '2999-12-31'
		) lsat on sd.acc_x_app_hash_key = lsat.acc_x_app_hash_key
	where 
		lsat.acc_x_app_hash_key is null
		and NULLIF(TRIM(sd.delete_dttm), '') is null
	) into rows_num;

--	IF rows_num = 0 
--		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', link_table_name;
--		drop table staging_data;
--    	RETURN;  -- Досрочный выход из процедуры
--	END IF;
 

    -- 4. Вставляем только новые acc_x_app связи в LINK
    INSERT INTO t3_core.LINK_acc_x_app (
		acc_x_app_hash_key,
		account_hash_key,
		application_hash_key, 
		load_dttm, 
		src_cd
	)
    SELECT
		sd.acc_x_app_hash_key,
		sd.account_hash_key,
		sd.application_hash_key, 
        current_dttm,
        'CRM'
    FROM staging_data sd
	WHERE NOT EXISTS (
    	SELECT 1 FROM t3_core.LINK_acc_x_app l
		WHERE l.acc_x_app_hash_key = sd.acc_x_app_hash_key
	);

	-- 5. Тут же вставляем новые данные в LSAT
	insert into t3_core.LSAT_acc_x_app
	(
		acc_x_app_hash_key,
		version_id,
		effective_from_dttm,
		effective_to_dttm,
		src_cd
	)
    SELECT
		sd.acc_x_app_hash_key,
		next_version,
        current_dttm,
		'2999-12-31',
        'CRM'
    FROM 
		staging_data sd
    	left join (
			select *
			from t3_core.LSAT_acc_x_app 
			where effective_to_dttm = '2999-12-31'
		) lsat on sd.acc_x_app_hash_key = lsat.acc_x_app_hash_key
	where 
		lsat.acc_x_app_hash_key is null
		and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- и обновляем строчки для удаленных 
	update t3_core.LSAT_acc_x_app lsat
	set effective_to_dttm = current_dttm
	from staging_data sd
	where 
		sd.acc_x_app_hash_key = lsat.acc_x_app_hash_key
		and NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в LSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, lsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	lsat_table_name, rows_num;
END;
$$ language plpgsql;


--CUSTOMER_X_APPLICATION
create or replace procedure t3_core.load_cust_x_app()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	link_table_name TEXT := 't3_core.LINK_cust_x_app'; 
	lsat_table_name TEXT := 't3_core.LSAT_cust_x_app'; -- историчность - в LSAT
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
--     1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(lsat_table_name);

    -- 2. Создаём временную таблицу для новых данных, которые нужно добавить
    CREATE UNLOGGED TABLE staging_data AS
    SELECT 
		t.cust_x_app_hash_key,
		t.customer_hash_key,
		t.application_hash_key,
		t.delete_dttm
    FROM (
    	SELECT 
			distinct
			cust_x_app_hash_key,
			customer_hash_key,
			application_hash_key,
			delete_dttm 
		FROM t2_stg.staging_application
	) t;

	-- 3. Есть ли записи для вставки в LSAT?

	select (		
		select count(*) 
		from staging_data sd
    	left join (
			select *
			from t3_core.LSAT_cust_x_app 
			where effective_to_dttm = '2999-12-31'
		) lsat on sd.cust_x_app_hash_key = lsat.cust_x_app_hash_key
	where 
		lsat.cust_x_app_hash_key is null
		and NULLIF(TRIM(sd.delete_dttm), '') is null
	) into rows_num;

--	IF rows_num = 0 
--		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', link_table_name;
--		drop table staging_data;
--    	RETURN;  -- Досрочный выход из процедуры
--	END IF;
 

    -- 4. Вставляем только новые cust_x_app связи в LINK
    INSERT INTO t3_core.LINK_cust_x_app (
		cust_x_app_hash_key,
		customer_hash_key,
		application_hash_key, 
		load_dttm, 
		src_cd
	)
    SELECT
		sd.cust_x_app_hash_key,
		sd.customer_hash_key,
		sd.application_hash_key, 
        current_dttm,
        'CRM'
    FROM staging_data sd
	WHERE NOT EXISTS (
    	SELECT 1 FROM t3_core.LINK_cust_x_app l
		WHERE l.cust_x_app_hash_key = sd.cust_x_app_hash_key
	);

	-- 5. Тут же вставляем новые данные в LSAT
	insert into t3_core.LSAT_cust_x_app
	(
		cust_x_app_hash_key,
		version_id,
		effective_from_dttm,
		effective_to_dttm,
		src_cd
	)
    SELECT
		sd.cust_x_app_hash_key,
		next_version,
        current_dttm,
		'2999-12-31',
        'CRM'
    FROM 
		staging_data sd
    	left join (
			select *
			from t3_core.LSAT_cust_x_app 
			where effective_to_dttm = '2999-12-31'
		) lsat on sd.cust_x_app_hash_key = lsat.cust_x_app_hash_key
	where 
		lsat.cust_x_app_hash_key is null
		and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- и обновляем строчки для удаленных 
	update t3_core.LSAT_cust_x_app lsat
	set effective_to_dttm = current_dttm
	from staging_data sd
	where 
		sd.cust_x_app_hash_key = lsat.cust_x_app_hash_key
		and NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в LSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, lsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	lsat_table_name, rows_num;
END;
$$ language plpgsql;




--CUSTOMER_X_REQUEST
create or replace procedure t3_core.load_cust_x_req()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	link_table_name TEXT := 't3_core.LINK_cust_x_req'; 
	lsat_table_name TEXT := 't3_core.LSAT_cust_x_req'; -- историчность - в LSAT
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
--     1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(lsat_table_name);

    -- 2. Создаём временную таблицу для новых данных, которые нужно добавить
    CREATE UNLOGGED TABLE staging_data AS
    SELECT 
		t.cust_x_req_hash_key,
		t.customer_hash_key,
		t.request_hash_key,
		t.delete_dttm
    FROM (
    	SELECT 
			distinct
			cust_x_req_hash_key,
			customer_hash_key,
			request_hash_key,
			delete_dttm 
		FROM t2_stg.staging_service_request
	) t;

	-- 3. Есть ли записи для вставки в LSAT?

	select (		
		select count(*) 
		from staging_data sd
    	left join (
			select *
			from t3_core.LSAT_cust_x_req 
			where effective_to_dttm = '2999-12-31'
		) lsat on sd.cust_x_req_hash_key = lsat.cust_x_req_hash_key
	where 
		lsat.cust_x_req_hash_key is null
		and NULLIF(TRIM(sd.delete_dttm), '') is null
	) into rows_num;

--	IF rows_num = 0 
--		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', link_table_name;
--		drop table staging_data;
--    	RETURN;  -- Досрочный выход из процедуры
--	END IF;
 

    -- 4. Вставляем только новые cust_x_req связи в LINK
    INSERT INTO t3_core.LINK_cust_x_req (
		cust_x_req_hash_key,
		customer_hash_key,
		request_hash_key, 
		load_dttm, 
		src_cd
	)
    SELECT
		sd.cust_x_req_hash_key,
		sd.customer_hash_key,
		sd.request_hash_key, 
        current_dttm,
        'CRM'
    FROM staging_data sd
	WHERE NOT EXISTS (
    	SELECT 1 FROM t3_core.LINK_cust_x_req l
		WHERE l.cust_x_req_hash_key = sd.cust_x_req_hash_key
	);

	-- 5. Тут же вставляем новые данные в LSAT
	insert into t3_core.LSAT_cust_x_req
	(
		cust_x_req_hash_key,
		version_id,
		effective_from_dttm,
		effective_to_dttm,
		src_cd
	)
    SELECT
		sd.cust_x_req_hash_key,
		next_version,
        current_dttm,
		'2999-12-31',
        'CRM'
    FROM 
		staging_data sd
    	left join (
			select *
			from t3_core.LSAT_cust_x_req
			where effective_to_dttm = '2999-12-31'
		) lsat on sd.cust_x_req_hash_key = lsat.cust_x_req_hash_key
	where 
		lsat.cust_x_req_hash_key is null
		and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- и обновляем строчки для удаленных 
	update t3_core.LSAT_cust_x_req lsat
	set effective_to_dttm = current_dttm
	from staging_data sd
	where 
		sd.cust_x_req_hash_key = lsat.cust_x_req_hash_key
		and NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в LSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, lsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	lsat_table_name, rows_num;
END;
$$ language plpgsql;



--ACCOUNT_X_TRANSACTION
create or replace procedure t3_core.load_acc_x_trans()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	link_table_name TEXT := 't3_core.LINK_acc_x_trans'; 
	lsat_table_name TEXT := 't3_core.LSAT_acc_x_trans'; -- историчность - в LSAT
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
--     1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(lsat_table_name);

    -- 2. Создаём временную таблицу для новых данных, которые нужно добавить
    CREATE UNLOGGED TABLE staging_data AS
    SELECT 
		t.acc_x_trans_hash_key,
		t.account_hash_key,
		t.transaction_hash_key,
		t.delete_dttm
    FROM (
    	SELECT 
			distinct
			acc_x_trans_hash_key,
			account_hash_key,
			transaction_hash_key,
			delete_dttm 
		FROM t2_stg.staging_crm_transaction
	) t;

	-- 3. Есть ли записи для вставки в LSAT?

	select (		
		select count(*) 
		from staging_data sd
    	left join (
			select *
			from t3_core.LSAT_acc_x_trans 
			where effective_to_dttm = '2999-12-31'
		) lsat on sd.acc_x_trans_hash_key = lsat.acc_x_trans_hash_key
	where 
		lsat.acc_x_trans_hash_key is null
		and NULLIF(TRIM(sd.delete_dttm), '') is null
	) into rows_num;

--	IF rows_num = 0 
--		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', link_table_name;
--		drop table staging_data;
--    	RETURN;  -- Досрочный выход из процедуры
--	END IF;
 

    -- 4. Вставляем только новые acc_x_trans связи в LINK
    INSERT INTO t3_core.LINK_acc_x_trans (
		acc_x_trans_hash_key,
		account_hash_key,
		transaction_hash_key, 
		load_dttm, 
		src_cd
	)
    SELECT
		sd.acc_x_trans_hash_key,
		sd.account_hash_key,
		sd.transaction_hash_key, 
        current_dttm,
        'CRM'
    FROM staging_data sd
	WHERE NOT EXISTS (
    	SELECT 1 FROM t3_core.LINK_acc_x_trans l
		WHERE l.acc_x_trans_hash_key = sd.acc_x_trans_hash_key
	);

	-- 5. Тут же вставляем новые данные в LSAT
	insert into t3_core.LSAT_acc_x_trans
	(
		acc_x_trans_hash_key,
		version_id,
		effective_from_dttm,
		effective_to_dttm,
		src_cd
	)
    SELECT
		sd.acc_x_trans_hash_key,
		next_version,
        current_dttm,
		'2999-12-31',
        'CRM'
    FROM 
		staging_data sd
    	left join (
			select *
			from t3_core.LSAT_acc_x_trans 
			where effective_to_dttm = '2999-12-31'
		) lsat on sd.acc_x_trans_hash_key = lsat.acc_x_trans_hash_key
	where 
		lsat.acc_x_trans_hash_key is null
		and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- и обновляем строчки для удаленных 
	update t3_core.LSAT_acc_x_trans lsat
	set effective_to_dttm = current_dttm
	from staging_data sd
	where 
		sd.acc_x_trans_hash_key = lsat.acc_x_trans_hash_key
		and NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в LSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, lsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	lsat_table_name, rows_num;
END;
$$ language plpgsql;




-- TRANSACTION_X_TRANSACTION
create or replace procedure t3_core.load_trans_x_orig_trans()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	link_table_name TEXT := 't3_core.LINK_trans_x_orig_trans'; 
	lsat_table_name TEXT := 't3_core.LSAT_trans_x_orig_trans'; -- историчность - в LSAT
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
--     1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(lsat_table_name);

    -- 2. Создаём временную таблицу для новых данных, которые нужно добавить
    CREATE UNLOGGED TABLE staging_data AS
    SELECT 
		t.trans_x_orig_trans_hash_key,
		t.transaction_hash_key,
		t.orig_transaction_hash_key,
		t.delete_dttm
    FROM (
    	SELECT 
			distinct
			trans_x_orig_trans_hash_key,
			transaction_hash_key,
			orig_transaction_hash_key,
			delete_dttm 
		FROM t2_stg.staging_crm_transaction
	) t;

	-- 3. Есть ли записи для вставки в LSAT?

	select (		
		select count(*) 
		from staging_data sd
    	left join (
			select *
			from t3_core.LSAT_trans_x_orig_trans 
			where effective_to_dttm = '2999-12-31'
		) lsat on sd.trans_x_orig_trans_hash_key = lsat.trans_x_orig_trans_hash_key
	where 
		lsat.trans_x_orig_trans_hash_key is null
		and NULLIF(TRIM(sd.delete_dttm), '') is null
	) into rows_num;

--	IF rows_num = 0 
--		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', link_table_name;
--		drop table staging_data;
--    	RETURN;  -- Досрочный выход из процедуры
--	END IF;
 

    -- 4. Вставляем только новые trans_x_orig_trans связи в LINK
    INSERT INTO t3_core.LINK_trans_x_orig_trans (
		trans_x_orig_trans_hash_key,
		transaction_hash_key,
		orig_transaction_hash_key, 
		load_dttm, 
		src_cd
	)
    SELECT
		sd.trans_x_orig_trans_hash_key,
		sd.transaction_hash_key,
		sd.orig_transaction_hash_key, 
        current_dttm,
        'CRM'
    FROM staging_data sd
	WHERE NOT EXISTS (
    	SELECT 1 FROM t3_core.LINK_trans_x_orig_trans l
		WHERE l.trans_x_orig_trans_hash_key = sd.trans_x_orig_trans_hash_key
	);

	-- 5. Тут же вставляем новые данные в LSAT
	insert into t3_core.LSAT_trans_x_orig_trans
	(
		trans_x_orig_trans_hash_key,
		version_id,
		effective_from_dttm,
		effective_to_dttm,
		src_cd
	)
    SELECT
		sd.trans_x_orig_trans_hash_key,
		next_version,
        current_dttm,
		'2999-12-31',
        'CRM'
    FROM 
		staging_data sd
    	left join (
			select *
			from t3_core.LSAT_trans_x_orig_trans 
			where effective_to_dttm = '2999-12-31'
		) lsat on sd.trans_x_orig_trans_hash_key = lsat.trans_x_orig_trans_hash_key
	where 
		lsat.trans_x_orig_trans_hash_key is null
		and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- и обновляем строчки для удаленных 
	update t3_core.LSAT_trans_x_orig_trans lsat
	set effective_to_dttm = current_dttm
	from staging_data sd
	where 
		sd.trans_x_orig_trans_hash_key = lsat.trans_x_orig_trans_hash_key
		and NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в LSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, lsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	lsat_table_name, rows_num;
END;
$$ language plpgsql;




call t3_core.load_acc_x_app();
call t3_core.load_cust_x_app();
call t3_core.load_cust_x_req();
call t3_core.load_acc_x_trans();
call t3_core.load_trans_x_orig_trans();

select customer_hash_key, count(*) 
from t3_core.link_cust_x_app 
group by 1


-- ЗАГРУЖАЕМ САТЕЛЛИТЫ ХАБОВ (HSAT)

-- HSAT_ACCOUNT
create or replace procedure t3_core.load_hsat_account()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	hsat_table_name TEXT := 't3_core.HSAT_account';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
	-- 1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(hsat_table_name);

	-- 2. Создаем временную таблицу
	CREATE UNLOGGED TABLE staging_data AS
	select 
		sd.*,
		scast.account_type_nm,
		hsat.account_hash_key as hsat_account_hash_key,
		hsat.hash_diff as hsat_hash_diff
	from t2_stg.staging_crm_account sd
		left join t2_stg.staging_crm_account_status_type scast using(account_type_cd)
    	left join (
			select *
			from t3_core.HSAT_account
			where effective_to_dttm = '2999-12-31'
		) hsat on sd.account_hash_key = hsat.account_hash_key;

	-- 3. Есть ли записи для вставки в HSAT?
	select (
		select
			count(*)
		from staging_data sd
		where 
			(sd.hsat_account_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL
	) into rows_num;
	
 
	-- 4. Вставляем новые данные в HSAT_account
	insert into t3_core.HSAT_account
	(
		account_hash_key,
		version_id,
		hash_diff,
		effective_from_dttm,
		effective_to_dttm,
		src_cd,
		account_type_nm,
		account_create_dt,
		create_dt,
		delete_dt
	)
	SELECT
		sd.account_hash_key,
		next_version,
		sd.hash_diff,
        current_dttm,
		'2999-12-31',
        'CRM',
		sd.account_type_nm,
		sd.account_create_dt::date,
		sd.create_dttm::date,
		sd.delete_dttm::date

		from staging_data sd
		where 
			(sd.hsat_account_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- 5. Обновление историчности HSAT_account
	with tab1 as(
		select 
			sd.account_hash_key,
			sd.delete_dttm,
			hsat.version_id
		from t2_stg.staging_crm_account sd
	    	left join (
				select *
				from t3_core.HSAT_account
				where effective_to_dttm = '2999-12-31'
			) hsat on sd.account_hash_key = hsat.account_hash_key
		where 
			sd.hash_diff <> hsat.hash_diff
			or NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL
	)
	update t3_core.HSAT_account hsat
	set 
		effective_to_dttm = current_dttm,
		delete_dt = tab1.delete_dttm::date
	from tab1
	where 
		hsat.account_hash_key = tab1.account_hash_key and
		hsat.version_id = tab1.version_id;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в HSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, hsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	hsat_table_name, rows_num;
END;
$$ language plpgsql;



-- HSAT_ACCOUNT_STATUS
create or replace procedure t3_core.load_hsat_account_status()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	hsat_table_name TEXT := 't3_core.HSAT_account_status';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
	-- 1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(hsat_table_name);

	-- 2. Создаем временную таблицу
	CREATE UNLOGGED TABLE staging_data AS
	select 
		sd.account_hash_key,
		sd.delete_dttm,
		scas.account_status_nm,
		hsat.account_status_nm as hsat_account_status_nm,
		hsat.account_hash_key as hsat_account_hash_key
	from t2_stg.staging_crm_account sd
		left join t2_stg.staging_crm_account_status scas using(account_status_cd)
    	left join (
			select *
			from t3_core.HSAT_account_status
			where effective_to_dttm = '2999-12-31'
		) hsat on sd.account_hash_key = hsat.account_hash_key;

	-- 3. Есть ли записи для вставки в HSAT?
	select (
		select
			count(*)
		from staging_data sd
		where 
			(sd.hsat_account_hash_key is null
			or sd.account_status_nm <> sd.hsat_account_status_nm)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL
	) into rows_num;
	
 
	-- 4. Вставляем новые данные в HSAT_account_status
	insert into t3_core.HSAT_account_status
	(
		account_hash_key,
		version_id,
		effective_from_dttm,
		effective_to_dttm,
		src_cd,
		account_status_nm
	)
	SELECT
		sd.account_hash_key,
		next_version,
        current_dttm,
		'2999-12-31',
        'CRM',
		sd.account_status_nm

		from staging_data sd
		where 
			(sd.hsat_account_hash_key is null
			or sd.account_status_nm <> sd.hsat_account_status_nm)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- 5. Обновление историчности HSAT_account_status
	with tab1 as(
		select 
			sd.account_hash_key,
			sd.delete_dttm,
			hsat.version_id
		from t2_stg.staging_crm_account sd
			left join t2_stg.staging_crm_account_status scas using(account_status_cd)
	    	left join (
				select *
				from t3_core.HSAT_account_status
				where effective_to_dttm = '2999-12-31'
			) hsat on sd.account_hash_key = hsat.account_hash_key
		where 
			scas.account_status_nm <> hsat.account_status_nm
			or NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL
	)
	update t3_core.HSAT_account_status hsat
	set 
		effective_to_dttm = current_dttm
	from tab1
	where 
		hsat.account_hash_key = tab1.account_hash_key and
		hsat.version_id = tab1.version_id;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в HSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, hsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	hsat_table_name, rows_num;
END;
$$ language plpgsql;



-- HSAT_CAB_CUSTOMER
create or replace procedure t3_core.load_hsat_cab_customer()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	hsat_table_name TEXT := 't3_core.HSAT_cab_customer';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
	-- 1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(hsat_table_name);

	-- 2. Создаем временную таблицу
	CREATE UNLOGGED TABLE staging_data AS
	select 
		sd.*,
		hsat.customer_hash_key as hsat_customer_hash_key,
		hsat.hash_diff as hsat_hash_diff
	from t2_stg.staging_cab_customer sd
    	left join (
			select *
			from t3_core.HSAT_cab_customer
			where effective_to_dttm = '2999-12-31'
		) hsat on sd.customer_hash_key = hsat.customer_hash_key;

	-- 3. Есть ли записи для вставки в HSAT?
	select (
		select
			count(*)
		from staging_data sd
		where 
			(sd.hsat_customer_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL
	) into rows_num;
	
	-- 4. Вставляем новые данные в HSAT_cab_customer
	insert into t3_core.hsat_cab_customer
	(
		customer_hash_key,
		version_id,
		hash_diff,
		effective_from_dttm,
		effective_to_dttm,
		src_cd,
		first_nm,
		last_nm,
		middle_nm,
		birth_dt,
		passport_num,
		create_dt,
		delete_dt
	)

	SELECT
		sd.customer_hash_key,
		next_version,
		sd.hash_diff,
        current_dttm,
		'2999-12-31',
        'CAB',
		sd.first_nm,
		sd.last_nm,
		sd.middle_nm,
		sd.birth_dt::date,
		sd.passport_num,
		sd.create_dttm::date,
		sd.delete_dttm::date

		from staging_data sd
		where 
			(sd.hsat_customer_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;

	
	-- 5. Обновление историчности HSAT_cab_customer
	with tab1 as(
		select 
			sd.customer_hash_key,
			sd.delete_dttm,
			hsat.version_id
		from t2_stg.staging_cab_customer sd
	    	left join (
				select *
				from t3_core.HSAT_cab_customer
				where effective_to_dttm = '2999-12-31'
			) hsat on sd.customer_hash_key = hsat.customer_hash_key
		where 
			sd.hash_diff <> hsat.hash_diff
			or NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL
	)
	update t3_core.HSAT_cab_customer hsat
	set 
		effective_to_dttm = current_dttm,
		delete_dt = tab1.delete_dttm::date
	from tab1
	where 
		hsat.customer_hash_key = tab1.customer_hash_key and
		hsat.version_id = tab1.version_id;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в HSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, hsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	hsat_table_name, rows_num;
END;
$$ language plpgsql;


-- HSAT_CAB_CUSTOMER_CONTACT
create or replace procedure t3_core.load_hsat_cab_customer_contact()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	hsat_table_name TEXT := 't3_core.HSAT_cab_customer_contact';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
	-- 1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(hsat_table_name);

	-- 2. Создаем временную таблицу
	CREATE UNLOGGED TABLE staging_data AS
	select 
		sd.*,
		hsat.customer_hash_key as hsat_customer_hash_key,
		hsat.hash_diff_con as hsat_hash_diff_con
	from t2_stg.staging_cab_customer sd
    	left join (
			select *
			from t3_core.HSAT_cab_customer_contact
			where effective_to_dttm = '2999-12-31'
		) hsat on sd.customer_hash_key = hsat.customer_hash_key;

	-- 3. Есть ли записи для вставки в HSAT?
	select (
		select
			count(*)
		from staging_data sd
		where 
			(sd.hsat_customer_hash_key is null
			or sd.hash_diff_con <> sd.hsat_hash_diff_con)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL
	) into rows_num;
	
	-- 4. Вставляем новые данные в HSAT_cab_customer_contact
insert into
	t3_core.hsat_cab_customer_contact
	(
		customer_hash_key,
		version_id,
		hash_diff_con,
		effective_from_dttm,
		effective_to_dttm,
		src_cd,
		phone_num,
		add_phone_num,
		email,
		reg_address_txt,
		fact_address_txt
	)

	SELECT
		sd.customer_hash_key,
		next_version,
		sd.hash_diff_con,
        current_dttm,
		'2999-12-31',
        'CAB',
		sd.phone_num,
		sd.add_phone_num,
		sd.email,
		sd.reg_address_txt,
		sd.fact_address_txt

		from staging_data sd
		where 
			(sd.hsat_customer_hash_key is null
			or sd.hash_diff_con <> sd.hsat_hash_diff_con)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;

	
	-- 5. Обновление историчности HSAT_cab_customer_contact
	with tab1 as(
		select 
			sd.customer_hash_key,
			sd.delete_dttm,
			hsat.version_id
		from t2_stg.staging_cab_customer sd
	    	left join (
				select *
				from t3_core.HSAT_cab_customer_contact
				where effective_to_dttm = '2999-12-31'
			) hsat on sd.customer_hash_key = hsat.customer_hash_key
		where 
			sd.hash_diff_con <> hsat.hash_diff_con
			or NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL
	)
	update t3_core.HSAT_cab_customer_contact hsat
	set 
		effective_to_dttm = current_dttm
	from tab1
	where 
		hsat.customer_hash_key = tab1.customer_hash_key and
		hsat.version_id = tab1.version_id;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в HSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, hsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	hsat_table_name, rows_num;
END;
$$ language plpgsql;


-- HSAT_CRM_CUSTOMER
create or replace procedure t3_core.load_hsat_crm_customer()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	hsat_table_name TEXT := 't3_core.HSAT_crm_customer';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
	-- 1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(hsat_table_name);

	-- 2. Создаем временную таблицу
	CREATE UNLOGGED TABLE staging_data AS
	select 
		sd.*,
		hsat.customer_hash_key as hsat_customer_hash_key,
		hsat.hash_diff as hsat_hash_diff
	from t2_stg.staging_crm_customer sd
    	left join (
			select *
			from t3_core.HSAT_crm_customer
			where effective_to_dttm = '2999-12-31'
		) hsat on sd.customer_hash_key = hsat.customer_hash_key;

	-- 3. Есть ли записи для вставки в HSAT?
	select (
		select
			count(*)
		from staging_data sd
		where 
			(sd.hsat_customer_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL
	) into rows_num;
	
 
	-- 4. Вставляем новые данные в HSAT_crm_customer
	insert into t3_core.hsat_crm_customer
	(
		customer_hash_key,
		version_id,
		hash_diff,
		effective_from_dttm,
		effective_to_dttm,
		src_cd,
		first_nm,
		last_nm,
		birth_dt,
		create_dt,
		delete_dt
	)
	SELECT
		sd.customer_hash_key,
		next_version,
		sd.hash_diff,
        current_dttm,
		'2999-12-31',
        'CRM',
		sd.first_nm,
		sd.last_nm,
		sd.birth_dt::date,
		sd.create_dttm::date,
		sd.delete_dttm::date

		from staging_data sd
		where 
			(sd.hsat_customer_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- 5. Обновление историчности HSAT_crm_customer
	with tab1 as(
		select 
			sd.customer_hash_key,
			sd.delete_dttm,
			hsat.version_id
		from t2_stg.staging_crm_customer sd
	    	left join (
				select *
				from t3_core.HSAT_crm_customer
				where effective_to_dttm = '2999-12-31'
			) hsat on sd.customer_hash_key = hsat.customer_hash_key
		where 
			sd.hash_diff <> hsat.hash_diff
			or NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL
	)
	update t3_core.HSAT_crm_customer hsat
	set 
		effective_to_dttm = current_dttm,
		delete_dt = tab1.delete_dttm::date
	from tab1
	where 
		hsat.customer_hash_key = tab1.customer_hash_key and
		hsat.version_id = tab1.version_id;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в HSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, hsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	hsat_table_name, rows_num;
END;
$$ language plpgsql;


-- HSAT_CRM_CUSTOMER_CONTACT
create or replace procedure t3_core.load_hsat_crm_customer_contact()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	hsat_table_name TEXT := 't3_core.HSAT_crm_customer_contact';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
	-- 1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(hsat_table_name);

	-- 2. Создаем временную таблицу
	CREATE UNLOGGED TABLE staging_data AS
	select 
		sd.*,
		hsat.customer_hash_key as hsat_customer_hash_key,
		hsat.phone_num as hsat_phone_num,
		hsat.email as hsat_email
	from t2_stg.staging_crm_customer sd
    	left join (
			select *
			from t3_core.HSAT_crm_customer_contact
			where effective_to_dttm = '2999-12-31'
		) hsat on sd.customer_hash_key = hsat.customer_hash_key;

	-- 3. Есть ли записи для вставки в HSAT?
	select (
		select
			count(*)
		from staging_data sd
		where 
			(sd.hsat_customer_hash_key is null
			or sd.phone_num <> sd.hsat_phone_num
			or sd.email <> sd.hsat_email)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL
	) into rows_num;
	
 
	-- 4. Вставляем новые данные в HSAT_crm_customer_contact
	insert into t3_core.hsat_crm_customer_contact
	(
		customer_hash_key,
		version_id,
		effective_from_dttm,
		effective_to_dttm,
		src_cd,
		phone_num,
		email
	)
	SELECT
		sd.customer_hash_key,
		next_version,
        current_dttm,
		'2999-12-31',
        'CRM',
		sd.phone_num,
		sd.email

		from staging_data sd
		where 
			(sd.hsat_customer_hash_key is null
			or sd.phone_num <> sd.hsat_phone_num
			or sd.email <> sd.hsat_email)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- 5. Обновление историчности HSAT_crm_customer_contact
	with tab1 as(
		select 
			sd.customer_hash_key,
			sd.delete_dttm,
			hsat.version_id
		from t2_stg.staging_crm_customer sd
	    	left join (
				select *
				from t3_core.HSAT_crm_customer_contact
				where effective_to_dttm = '2999-12-31'
			) hsat on sd.customer_hash_key = hsat.customer_hash_key
		where 
			(sd.phone_num <> hsat.phone_num
			or sd.email <> hsat.email)
			or NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL
	)
	update t3_core.HSAT_crm_customer_contact hsat
	set 
		effective_to_dttm = current_dttm
	from tab1
	where 
		hsat.customer_hash_key = tab1.customer_hash_key and
		hsat.version_id = tab1.version_id;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в HSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, hsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	hsat_table_name, rows_num;
END;
$$ language plpgsql;


-- HSAT_CAB_REQUEST
create or replace procedure t3_core.load_hsat_request()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	hsat_table_name TEXT := 't3_core.HSAT_request';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
	-- 1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(hsat_table_name);

	-- 2. Создаем временную таблицу
	CREATE UNLOGGED TABLE staging_data AS
	select 
		sd.*,
		ssrt.service_request_type_nm,
		hsat.request_hash_key as hsat_request_hash_key,
		hsat.hash_diff as hsat_hash_diff
	from t2_stg.staging_service_request sd
		left join t2_stg.staging_service_request_type ssrt using(service_request_type_cd)
    	left join (
			select *
			from t3_core.HSAT_request
			where effective_to_dttm = '2999-12-31'
		) hsat on sd.request_hash_key = hsat.request_hash_key;

	-- 3. Есть ли записи для вставки в HSAT?
	select (
		select
			count(*)
		from staging_data sd
		where 
			(sd.hsat_request_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL
	) into rows_num;
	
	-- 4. Вставляем новые данные в HSAT_request
	insert into t3_core.hsat_request
	(
		request_hash_key,
		version_id,
		hash_diff,
		effective_from_dttm,
		effective_to_dttm,
		src_cd,
		tail_limit,
		service_request_type_nm,
		create_dt,
		delete_dt
	)

	SELECT
		sd.request_hash_key,
		next_version,
		sd.hash_diff,
        current_dttm,
		'2999-12-31',
        'CAB',
		sd.tail_limit::int,
		sd.service_request_type_nm,
		sd.create_dttm::date,
		sd.delete_dttm::date

		from staging_data sd
		where 
			(sd.hsat_request_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;

	
	-- 5. Обновление историчности HSAT_request
	with tab1 as(
		select 
			sd.request_hash_key,
			sd.delete_dttm,
			hsat.version_id
		from t2_stg.staging_service_request sd
	    	left join (
				select *
				from t3_core.HSAT_request
				where effective_to_dttm = '2999-12-31'
			) hsat on sd.request_hash_key = hsat.request_hash_key
		where 
			sd.hash_diff <> hsat.hash_diff
			or NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL
	)
	update t3_core.HSAT_request hsat
	set 
		effective_to_dttm = current_dttm,
		delete_dt = tab1.delete_dttm::date
	from tab1
	where 
		hsat.request_hash_key = tab1.request_hash_key and
		hsat.version_id = tab1.version_id;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в HSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, hsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	hsat_table_name, rows_num;
END;
$$ language plpgsql;


-- HSAT_CAB_REQUEST_STATUS
create or replace procedure t3_core.load_hsat_request_status()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	hsat_table_name TEXT := 't3_core.HSAT_request_status';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
	-- 1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(hsat_table_name);

	-- 2. Создаем временную таблицу
	CREATE UNLOGGED TABLE staging_data AS
	select 
		sd.request_hash_key,
		sd.delete_dttm,
		ssrs.service_request_status_nm,
		hsat.request_hash_key as hsat_request_hash_key,
		hsat.service_request_status_nm as hsat_service_request_status_nm
	from t2_stg.staging_service_request sd
		left join t2_stg.staging_service_request_status ssrs using(service_request_status_cd)
    	left join (
			select *
			from t3_core.HSAT_request_status
			where effective_to_dttm = '2999-12-31'
		) hsat on sd.request_hash_key = hsat.request_hash_key;

	-- 3. Есть ли записи для вставки в HSAT?
	select (
		select
			count(*)
		from staging_data sd
		where 
			(sd.hsat_request_hash_key is null
			or sd.hsat_service_request_status_nm <> sd.hsat_service_request_status_nm)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL
	) into rows_num;
	
	-- 4. Вставляем новые данные в HSAT_request_status
	insert into
		t3_core.hsat_request_status
		(
		request_hash_key,
		version_id,
		effective_from_dttm,
		effective_to_dttm,
		src_cd,
		service_request_status_nm
	)

	SELECT
		sd.request_hash_key,
		next_version,
        current_dttm,
		'2999-12-31',
        'CAB',
		sd.service_request_status_nm

		from staging_data sd
		where 
			(sd.hsat_request_hash_key is null
			or sd.hsat_service_request_status_nm <> sd.hsat_service_request_status_nm)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;

	
	-- 5. Обновление историчности HSAT_request_status
	with tab1 as(
		select 
			sd.request_hash_key,
			sd.delete_dttm,
			hsat.version_id
		from t2_stg.staging_service_request sd
			left join t2_stg.staging_service_request_status ssrs using(service_request_status_cd)
	    	left join (
				select *
				from t3_core.HSAT_request_status
				where effective_to_dttm = '2999-12-31'
			) hsat on sd.request_hash_key = hsat.request_hash_key
		where 
			ssrs.service_request_status_nm <> hsat.service_request_status_nm
			or NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL
	)
	update t3_core.HSAT_request_status hsat
	set 
		effective_to_dttm = current_dttm
	from tab1
	where 
		hsat.request_hash_key = tab1.request_hash_key and
		hsat.version_id = tab1.version_id;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в HSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, hsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	hsat_table_name, rows_num;
END;
$$ language plpgsql;


-- HSAT_APPLICATION
create or replace procedure t3_core.load_hsat_application()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	hsat_table_name TEXT := 't3_core.HSAT_application';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
	-- 1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(hsat_table_name);

	-- 2. Создаем временную таблицу
	CREATE UNLOGGED TABLE staging_data AS
	select 
		sd.*,
		hsat.application_hash_key as hsat_application_hash_key,
		spt.product_type_nm,
		hsat.hash_diff as hsat_hash_diff
	from t2_stg.staging_application sd
		left join t2_stg.staging_product_type spt using(product_type_cd)
    	left join (
			select *
			from t3_core.HSAT_application
			where effective_to_dttm = '2999-12-31'
		) hsat on sd.application_hash_key = hsat.application_hash_key;

	-- 3. Есть ли записи для вставки в HSAT?
	select (
		select
			count(*)
		from staging_data sd
		where 
			(sd.hsat_application_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL
	) into rows_num;
	
 
	-- 4. Вставляем новые данные в HSAT_application
	insert into t3_core.hsat_application
	(
		application_hash_key,
		version_id,
		hash_diff,
		effective_from_dttm,
		effective_to_dttm,
		src_cd,
		product_type_nm,
		create_dt,
		delete_dt)
	SELECT
		sd.application_hash_key,
		next_version,
		sd.hash_diff,
        current_dttm,
		'2999-12-31',
        'CRM',
		sd.product_type_nm,
		sd.create_dttm::date,
		sd.delete_dttm::date

		from staging_data sd
		where 
			(sd.hsat_application_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- 5. Обновление историчности HSAT_application
	with tab1 as(
		select 
			sd.application_hash_key,
			sd.delete_dttm,
			hsat.version_id
		from t2_stg.staging_application sd
	    	left join (
				select *
				from t3_core.HSAT_application
				where effective_to_dttm = '2999-12-31'
			) hsat on sd.application_hash_key = hsat.application_hash_key
		where 
			sd.hash_diff <> hsat.hash_diff
			or NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL
	)
	update t3_core.HSAT_application hsat
	set 
		effective_to_dttm = current_dttm,
		delete_dt = tab1.delete_dttm::date
	from tab1
	where 
		hsat.application_hash_key = tab1.application_hash_key and
		hsat.version_id = tab1.version_id;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в HSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, hsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	hsat_table_name, rows_num;
END;
$$ language plpgsql;



-- HSAT_TRANSACTION
create or replace procedure t3_core.load_hsat_transaction()
as $$
declare
    next_version INT;
 	last_load_dttm TIMESTAMP;
	hsat_table_name TEXT := 't3_core.HSAT_transaction';
	current_dttm timestamp := now();
	rows_num INT;
BEGIN
	-- 1. Историчность и версионность
	SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(hsat_table_name);

	-- 2. Создаем временную таблицу
	CREATE UNLOGGED TABLE staging_data AS
	select 
		sd.*,
		hsat.transaction_hash_key as hsat_transaction_hash_key,
		sctp.transaction_type_nm,
		hsat.hash_diff as hsat_hash_diff
	from t2_stg.staging_crm_transaction sd
		left join t2_stg.staging_crm_transaction_type sctp using(transaction_type_cd)
    	left join (
			select *
			from t3_core.HSAT_transaction
			where effective_to_dttm = '2999-12-31'
		) hsat on sd.transaction_hash_key = hsat.transaction_hash_key;

	-- 3. Есть ли записи для вставки в HSAT?
	select (
		select
			count(*)
		from staging_data sd
		where 
			(sd.hsat_transaction_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL
	) into rows_num;
	
 
	-- 4. Вставляем новые данные в HSAT_transaction
	insert into
		t3_core.hsat_transaction
	(
		transaction_hash_key,
		version_id,
		hash_diff,
		effective_from_dttm,
		effective_to_dttm,
		src_cd,
		transaction_amt,
		transaction_type_nm,
		transaction_dttm,
		create_dt,
		delete_dt
	)
	SELECT
		sd.transaction_hash_key,
		next_version,
		sd.hash_diff,
        current_dttm,
		'2999-12-31',
        'CRM',
		sd.transaction_amt::float,
		sd.transaction_type_nm,
		sd.transaction_dttm::timestamp,
		sd.create_dttm::date,
		sd.delete_dttm::date

		from staging_data sd
		where 
			(sd.hsat_transaction_hash_key is null
			or sd.hash_diff <> sd.hsat_hash_diff)
			and NULLIF(TRIM(sd.delete_dttm), '') IS NULL;
	
	-- 5. Обновление историчности HSAT_transaction
	with tab1 as(
		select 
			sd.transaction_hash_key,
			sd.delete_dttm,
			hsat.version_id
		from t2_stg.staging_crm_transaction sd
	    	left join (
				select *
				from t3_core.HSAT_transaction
				where effective_to_dttm = '2999-12-31'
			) hsat on sd.transaction_hash_key = hsat.transaction_hash_key
		where 
			sd.hash_diff <> hsat.hash_diff
			or NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL
	)
	update t3_core.HSAT_transaction hsat
	set 
		effective_to_dttm = current_dttm,
		delete_dt = tab1.delete_dttm::date
	from tab1
	where 
		hsat.transaction_hash_key = tab1.transaction_hash_key and
		hsat.version_id = tab1.version_id;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в HSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, hsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	hsat_table_name, rows_num;
END;
$$ language plpgsql;





call t3_core.load_hsat_account();
call t3_core.load_hsat_account_status();
call t3_core.load_hsat_cab_customer();
call t3_core.load_hsat_crm_customer();
call t3_core.load_hsat_cab_customer_contact();
call t3_core.load_hsat_crm_customer_contact();
call t3_core.load_hsat_request();
call t3_core.load_hsat_request_status();
call t3_core.load_hsat_application();
call t3_core.load_hsat_transaction();




