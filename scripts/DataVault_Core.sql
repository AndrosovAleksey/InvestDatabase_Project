-- DLL
-- 1. Создание схемы и таблицы версий
CREATE SCHEMA IF NOT EXISTS t3_core;
drop table if exists staging_data;


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


-- 3. СКЛЕИВАНИЕ ИСТОРИЧНОСТИ для связей

CREATE OR REPLACE FUNCTION t3_core.merge_intervals(
    source_table_name TEXT,
    key_column_name   TEXT
)
RETURNS TABLE (
    key             TEXT,
    create_dttm     TIMESTAMP,
    delete_dttm     TIMESTAMP
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY EXECUTE format(
        $sql$
        WITH normalized AS (
            -- 1. Нормализация: NULL в delete_dttm заменяем на бесконечность
            SELECT
                %2$I::TEXT AS key,
                create_dttm,
                COALESCE(delete_dttm, '2999-12-31'::TIMESTAMP) AS delete_dttm
            FROM %1$I
            WHERE create_dttm IS NOT NULL
        ),
        lagged AS (
            -- 2. Смотрим дату окончания предыдущей записи для того же ключа
            SELECT
                key,
                create_dttm,
                delete_dttm,
                LAG(delete_dttm) OVER (
                    PARTITION BY key 
                    ORDER BY create_dttm ASC, delete_dttm ASC
                ) AS prev_delete_dttm
            FROM normalized
        ),
        grouped AS (
            -- 3. Размечаем группы:
            -- Если текущее начало > предыдущего конца -> разрыв (новый интервал)
            -- Иначе (<=, включая равенство) -> склеиваем
            SELECT
                key,
                create_dttm,
                delete_dttm,
                SUM(CASE WHEN create_dttm > prev_delete_dttm THEN 1 ELSE 0 END) 
                    OVER (PARTITION BY key ORDER BY create_dttm ASC) AS group_id
            FROM lagged
        )
        -- 4. Агрегируем по группам
        SELECT
            key,
            MIN(create_dttm) AS create_dttm,
            NULLIF(MAX(delete_dttm), '2999-12-31'::TIMESTAMP) AS delete_dttm
        FROM grouped
        GROUP BY key, group_id
        ORDER BY key, create_dttm
        $sql$,
        source_table_name,  -- %1$I - имя таблицы
        key_column_name     -- %2$I - имя колонки ключа
    );
END;
$$;





-- 4. Создаем таблицы
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
    PRIMARY KEY (account_hash_key, effective_from_dttm)
);

-- HSAT: HUB_account_status
drop table if exists t3_core.HSAT_account_status;
CREATE TABLE t3_core.HSAT_account_status (
    account_hash_key VARCHAR(32),
    version_id BIGINT,
    hash_diff VARCHAR(32),
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    account_status_nm VARCHAR(256),
    PRIMARY KEY (account_hash_key, effective_from_dttm)
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
    PRIMARY KEY (application_hash_key, effective_from_dttm)
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
    PRIMARY KEY (customer_hash_key, effective_from_dttm)
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
    PRIMARY KEY (customer_hash_key, effective_from_dttm)
);

drop table if exists t3_core.HSAT_crm_customer_contact;
CREATE TABLE t3_core.HSAT_crm_customer_contact (
    customer_hash_key VARCHAR(32),
    version_id BIGINT,
    hash_diff_con VARCHAR(32),
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    phone_num TEXT,
    email VARCHAR(256),
    PRIMARY KEY (customer_hash_key, effective_from_dttm)
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
    PRIMARY KEY (customer_hash_key, effective_from_dttm)
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
    PRIMARY KEY (request_hash_key, effective_from_dttm)
);

drop table if exists t3_core.HSAT_request_status;
CREATE TABLE t3_core.HSAT_request_status (
    request_hash_key VARCHAR(32),
    version_id BIGINT,
    hash_diff VARCHAR(32),
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    service_request_status_nm VARCHAR(256),
    PRIMARY KEY (request_hash_key, effective_from_dttm)
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
    PRIMARY KEY (transaction_hash_key, effective_from_dttm)
);


-- LSAT: LINK_acc_x_app
drop table if exists t3_core.LSAT_acc_x_app;
CREATE TABLE t3_core.LSAT_acc_x_app (
    acc_x_app_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    PRIMARY KEY (acc_x_app_hash_key, effective_from_dttm)
);

-- LSAT: LINK_cust_x_app
drop table if exists t3_core.LSAT_cust_x_app;
CREATE TABLE t3_core.LSAT_cust_x_app (
    cust_x_app_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    PRIMARY KEY (cust_x_app_hash_key, effective_from_dttm)
);


-- LSAT: LINK_cust_x_req
drop table if exists t3_core.LSAT_cust_x_req;
CREATE TABLE t3_core.LSAT_cust_x_req (
    cust_x_req_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    PRIMARY KEY (cust_x_req_hash_key, effective_from_dttm)
);

-- LSAT: LINK_acc_x_trans
drop table if exists t3_core.LSAT_acc_x_trans;
CREATE TABLE t3_core.LSAT_acc_x_trans (
    acc_x_trans_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    PRIMARY KEY (acc_x_trans_hash_key, effective_from_dttm)
);

-- LSAT: LINK_trans_x_orig_trans
drop table if exists t3_core.LSAT_trans_x_orig_trans;
CREATE TABLE t3_core.LSAT_trans_x_orig_trans (
    trans_x_orig_trans_hash_key VARCHAR(32),
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP,
    src_cd VARCHAR(8),
    PRIMARY KEY (trans_x_orig_trans_hash_key, effective_from_dttm)
);



-- 5. ПРОЦЕДУРЫ

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
	drop table if exists staging_data;
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
		SELECT distinct orig_transaction_hash_key, orig_id FROM t2_stg.staging_crm_transaction
		where orig_transaction_hash_key is not NULL-- целевая таблица
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
		NULLIF(t.create_dttm, '')::timestamp as create_dttm,
		NULLIF(t.delete_dttm, '')::timestamp as delete_dttm
    FROM t2_stg.staging_crm_account t
	union 
	select
		l.acc_x_app_hash_key,
		NULL,
		NULL,
		l.effective_from_dttm,
		l.effective_to_dttm
    FROM 
		t3_core.LSAT_acc_x_app l
	where l.effective_to_dttm = '2999-12-31'
	and EXISTS (select 1 from t2_stg.staging_crm_account t
				where t.acc_x_app_hash_key = l.acc_x_app_hash_key);

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
	) into rows_num;

	IF rows_num = 0 
		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', link_table_name;
		drop table staging_data;
    	RETURN;  -- Досрочный выход из процедуры
	END IF;
 

    -- 4. Вставляем только новые acc_x_app связи в LINK
    INSERT INTO t3_core.LINK_acc_x_app (
		acc_x_app_hash_key,
		account_hash_key,
		application_hash_key, 
		load_dttm, 
		src_cd
	)
    SELECT distinct
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
		sd.key,
		next_version,
        sd.create_dttm,
		coalesce(sd.delete_dttm, '2999-12-31'::timestamp),	
        'CRM'
    FROM 
		t3_core.merge_intervals('staging_data', 'acc_x_app_hash_key') as sd
    ON CONFLICT (acc_x_app_hash_key, effective_from_dttm) 
	DO UPDATE SET effective_to_dttm = EXCLUDED.effective_to_dttm;
	
--	 и обновляем строчки для удаленных 
--
--	update t3_core.LSAT_acc_x_app lsat
--	set effective_to_dttm = NULLIF(sd.delete_dttm,'')::timestamp
--	from staging_data sd
--	where 
--		effective_to_dttm = '2999-12-31'::timestamp
--		and sd.acc_x_app_hash_key = lsat.acc_x_app_hash_key
--		and NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL;

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
    SELECT distinct
		t.cust_x_app_hash_key,
		t.customer_hash_key,
		t.application_hash_key,
		NULLIF(t.create_dttm, '')::timestamp as create_dttm,
		NULLIF(t.delete_dttm, '')::timestamp as delete_dttm
    FROM t2_stg.staging_application t
	union 
	select
		l.cust_x_app_hash_key,
		NULL,
		NULL,
		l.effective_from_dttm,
		l.effective_to_dttm
    FROM 
		t3_core.LSAT_cust_x_app l
	where l.effective_to_dttm = '2999-12-31'
	and EXISTS (select 1 from t2_stg.staging_application t
				where t.cust_x_app_hash_key = l.cust_x_app_hash_key);

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
	) into rows_num;

	IF rows_num = 0 
		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', link_table_name;
		drop table staging_data;
    	RETURN;  -- Досрочный выход из процедуры
	END IF;
 

    -- 4. Вставляем только новые cust_x_app связи в LINK
    INSERT INTO t3_core.LINK_cust_x_app (
		cust_x_app_hash_key,
		customer_hash_key,
		application_hash_key, 
		load_dttm, 
		src_cd
	)
    SELECT distinct
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
		sd.key,
		next_version,
        sd.create_dttm,
		coalesce(sd.delete_dttm, '2999-12-31'::timestamp),	
        'CRM'
    FROM 
		t3_core.merge_intervals('staging_data', 'cust_x_app_hash_key') as sd
    ON CONFLICT (cust_x_app_hash_key, effective_from_dttm) 
	DO UPDATE SET effective_to_dttm = EXCLUDED.effective_to_dttm;
	
--	 и обновляем строчки для удаленных 
--	update t3_core.LSAT_cust_x_app lsat
--	set effective_to_dttm = current_dttm
--	from staging_data sd
--	where 
--		sd.cust_x_app_hash_key = lsat.cust_x_app_hash_key
--		and NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL;

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
    SELECT distinct
		t.cust_x_req_hash_key,
		t.customer_hash_key,
		t.request_hash_key,
		NULLIF(t.create_dttm, '')::timestamp as create_dttm,
		NULLIF(t.delete_dttm, '')::timestamp as delete_dttm
    FROM t2_stg.staging_service_request t
	union 
	select
		l.cust_x_req_hash_key,
		NULL,
		NULL,
		l.effective_from_dttm,
		l.effective_to_dttm
    FROM 
		t3_core.LSAT_cust_x_req l
	where l.effective_to_dttm = '2999-12-31'
	and EXISTS (select 1 from t2_stg.staging_service_request t
				where t.cust_x_req_hash_key = l.cust_x_req_hash_key);

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
	) into rows_num;

	IF rows_num = 0 
		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', link_table_name;
		drop table staging_data;
    	RETURN;  -- Досрочный выход из процедуры
	END IF;
 

    -- 4. Вставляем только новые cust_x_req связи в LINK
    INSERT INTO t3_core.LINK_cust_x_req (
		cust_x_req_hash_key,
		customer_hash_key,
		request_hash_key, 
		load_dttm, 
		src_cd
	)
    SELECT distinct
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
		sd.key,
		next_version,
        sd.create_dttm,
		coalesce(sd.delete_dttm, '2999-12-31'::timestamp),	
        'CRM'
    FROM 
		t3_core.merge_intervals('staging_data', 'cust_x_req_hash_key') as sd
    ON CONFLICT (cust_x_req_hash_key, effective_from_dttm) 
	DO UPDATE SET effective_to_dttm = EXCLUDED.effective_to_dttm;
	
--	 и обновляем строчки для удаленных 
--	update t3_core.LSAT_cust_x_req lsat
--	set effective_to_dttm = current_dttm
--	from staging_data sd
--	where 
--		sd.cust_x_req_hash_key = lsat.cust_x_req_hash_key
--		and NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL;

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
    SELECT distinct
		t.acc_x_trans_hash_key,
		t.account_hash_key,
		t.transaction_hash_key,
		NULLIF(t.create_dttm, '')::timestamp as create_dttm,
		NULLIF(t.delete_dttm, '')::timestamp as delete_dttm
    FROM t2_stg.staging_crm_transaction t
	union 
	select
		l.acc_x_trans_hash_key,
		NULL,
		NULL,
		l.effective_from_dttm,
		l.effective_to_dttm
    FROM 
		t3_core.LSAT_acc_x_trans l
	where l.effective_to_dttm = '2999-12-31'
	and EXISTS (select 1 from t2_stg.staging_crm_transaction t
				where t.acc_x_trans_hash_key = l.acc_x_trans_hash_key);

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
	) into rows_num;

	IF rows_num = 0 
		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', link_table_name;
		drop table staging_data;
    	RETURN;  -- Досрочный выход из процедуры
	END IF;
 

    -- 4. Вставляем только новые acc_x_trans связи в LINK
    INSERT INTO t3_core.LINK_acc_x_trans (
		acc_x_trans_hash_key,
		account_hash_key,
		transaction_hash_key, 
		load_dttm, 
		src_cd
	)
    SELECT distinct
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
		sd.key,
		next_version,
        sd.create_dttm,
		coalesce(sd.delete_dttm, '2999-12-31'::timestamp),	
        'CRM'
    FROM 
		t3_core.merge_intervals('staging_data', 'acc_x_trans_hash_key') as sd
    ON CONFLICT (acc_x_trans_hash_key, effective_from_dttm) 
	DO UPDATE SET effective_to_dttm = EXCLUDED.effective_to_dttm;
	
	-- и обновляем строчки для удаленных 
--	update t3_core.LSAT_acc_x_trans lsat
--	set effective_to_dttm = current_dttm
--	from staging_data sd
--	where 
--		sd.acc_x_trans_hash_key = lsat.acc_x_trans_hash_key
--		and NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL;

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
    SELECT distinct
		t.trans_x_orig_trans_hash_key,
		t.transaction_hash_key,
		t.orig_transaction_hash_key,
		NULLIF(t.create_dttm, '')::timestamp as create_dttm,
		NULLIF(t.delete_dttm, '')::timestamp as delete_dttm
    FROM t2_stg.staging_crm_transaction t
		where orig_transaction_hash_key is not NULL
	union 
	select
		l.trans_x_orig_trans_hash_key,
		NULL,
		NULL,
		l.effective_from_dttm,
		l.effective_to_dttm
    FROM 
		t3_core.LSAT_trans_x_orig_trans l
	where l.effective_to_dttm = '2999-12-31'
	and EXISTS (select 1 from t2_stg.staging_crm_transaction t
				where t.trans_x_orig_trans_hash_key = l.trans_x_orig_trans_hash_key);

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
	) into rows_num;

	IF rows_num = 0 
		THEN RAISE NOTICE '%: Нет данных для загрузки. Завершаем процедуру.', link_table_name;
		drop table staging_data;
    	RETURN;  -- Досрочный выход из процедуры
	END IF;
 

    -- 4. Вставляем только новые trans_x_orig_trans связи в LINK
    INSERT INTO t3_core.LINK_trans_x_orig_trans (
		trans_x_orig_trans_hash_key,
		transaction_hash_key,
		orig_transaction_hash_key, 
		load_dttm, 
		src_cd
	)
    SELECT distinct
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
		sd.key,
		next_version,
        sd.create_dttm,
		coalesce(sd.delete_dttm, '2999-12-31'::timestamp),	
        'CRM'
    FROM 
		t3_core.merge_intervals('staging_data', 'trans_x_orig_trans_hash_key') as sd
    ON CONFLICT (trans_x_orig_trans_hash_key, effective_from_dttm) 
	DO UPDATE SET effective_to_dttm = EXCLUDED.effective_to_dttm;
	
	-- и обновляем строчки для удаленных 
--	update t3_core.LSAT_trans_x_orig_trans lsat
--	set effective_to_dttm = current_dttm
--	from staging_data sd
--	where 
--		sd.trans_x_orig_trans_hash_key = lsat.trans_x_orig_trans_hash_key
--		and NULLIF(TRIM(sd.delete_dttm), '') IS NOT NULL;

--	 6. Обновляем реестр версий (если загрузили хоть что-то в LSAT)
  	IF rows_num > 0 
    	THEN PERFORM t3_core.record_version_load(current_dttm, next_version, lsat_table_name);
  	END IF;

	drop table staging_data;
	RAISE NOTICE '%: Для % записей добавлена история в CORE слое', 
	lsat_table_name, rows_num;
END;
$$ language plpgsql;


-------------------------------------------------------------------------------------
-- Общая функция загрузки SAT

CREATE OR REPLACE PROCEDURE t3_core.load_hsat_generic(
    p_target_table TEXT,       -- Например, 't3_core.HSAT_account'
    p_staging_query TEXT,      -- SELECT, возвращающий: bk, hash, create_dttm, delete_dttm, [attributes]
    p_bk_column TEXT,          -- Имя бизнес-ключа
    p_src_cd TEXT,             -- Код источника
    p_hash_column TEXT,        -- Имя колонки хеша
    p_attr_columns TEXT[]      -- Массив имен атрибутов
) AS $$
DECLARE
    next_version INT;
    last_load_dttm TIMESTAMP;
    current_dttm TIMESTAMP := now();
    v_col_list TEXT;
    v_val_list TEXT;
    v_stg_attrs TEXT := '';
    v_hist_attrs TEXT := '';
    v_pass_attrs TEXT := '';
    i INT;
    v_sql TEXT;
    v_rows BIGINT;
BEGIN
    -- 1. Получаем версию загрузки
    SELECT * INTO last_load_dttm, next_version
    FROM t3_core.get_last_version_load(p_target_table);

    -- 2. Формируем списки колонок для INSERT
    v_col_list := format('%I, version_id, %I, effective_from_dttm, effective_to_dttm, src_cd', p_bk_column, p_hash_column);
    v_val_list := format('sd.bk, %L, sd.hash, sd.eff_from, sd.eff_to, %L', next_version, p_src_cd);

    -- Собираем строки атрибутов для разных частей CTE
    IF array_length(p_attr_columns, 1) IS NOT NULL AND array_length(p_attr_columns, 1) > 0 THEN
        FOR i IN 1..array_length(p_attr_columns, 1) LOOP
            v_col_list := v_col_list || ', ' || format('%I', p_attr_columns[i]);
            v_val_list := v_val_list || ', sd.' || format('%I', p_attr_columns[i]);
            
            v_stg_attrs  := v_stg_attrs  || (CASE WHEN i > 1 THEN ', ' ELSE '' END) || 's.' || format('%I', p_attr_columns[i]);
            v_hist_attrs := v_hist_attrs || (CASE WHEN i > 1 THEN ', ' ELSE '' END) || 'h.' || format('%I', p_attr_columns[i]);
            v_pass_attrs := v_pass_attrs || (CASE WHEN i > 1 THEN ', ' ELSE '' END) || 'sd.' || format('%I', p_attr_columns[i]);
        END LOOP;
    ELSE
        v_stg_attrs := 'NULL::text'; v_hist_attrs := 'NULL::text'; v_pass_attrs := 'NULL::text';
    END IF;

    -- 3. Создаем временную таблицу
    EXECUTE format('CREATE UNLOGGED TABLE staging_data AS %s', p_staging_query);

    -- 4. Формируем и выполняем SQL Паттерна 1
    v_sql := format($sql$
        WITH dist_keys AS (
            SELECT %I as bk, MAX(create_dttm) as max_dt, MIN(create_dttm) as min_dt
            FROM staging_data GROUP BY %I
        ),
        merged_data AS (
            -- Новые данные из staging
            SELECT s.%I as bk, s.%I as hash, s.create_dttm as eff_from, s.delete_dttm as eff_to,
                   %s, TRUE as mark
            FROM staging_data s
            UNION ALL
            -- Затронутая история из target
            SELECT h.%I, h.%I, h.effective_from_dttm, h.effective_to_dttm,
                   %s,
                   CASE WHEN h.effective_to_dttm = '2999-12-31' AND h.effective_from_dttm < dk.max_dt THEN TRUE ELSE FALSE END
            FROM %s h
            JOIN dist_keys dk ON h.%I = dk.bk
            WHERE h.effective_from_dttm >= dk.min_dt
              AND NOT EXISTS (
                  SELECT 1 FROM staging_data s 
                  WHERE s.%I = h.%I AND s.create_dttm = h.effective_from_dttm
              )
        ),
        calculated AS (
            SELECT sd.bk, sd.hash, sd.eff_from, sd.eff_to, sd.mark,
                   %s,
                   CASE WHEN sd.mark THEN 
                       COALESCE(NULLIF(sd.eff_to, '2999-12-31'), LEAD(sd.eff_from) OVER(PARTITION BY sd.bk ORDER BY sd.eff_from))
                   ELSE sd.eff_to END as new_eff_to
            FROM merged_data sd
        ),
        final_data AS (
            SELECT 
					sd.bk, sd.hash, sd.eff_from, COALESCE(sd.new_eff_to, '2999-12-31') as eff_to, sd.mark,
                   %s
            FROM calculated sd
            WHERE sd.mark = TRUE
        )
        INSERT INTO %s (%s)
        SELECT %s
        FROM final_data sd
        ON CONFLICT (%I, effective_from_dttm) 
        DO UPDATE SET
            effective_to_dttm = EXCLUDED.effective_to_dttm,
            version_id = EXCLUDED.version_id
    $sql$,
    p_bk_column, p_bk_column,
    p_bk_column, p_hash_column, v_stg_attrs,
    p_bk_column, p_hash_column, v_hist_attrs,
    p_target_table, p_bk_column, p_bk_column, p_bk_column, -- ИСПРАВЛЕНО: добавлен p_bk_column
    v_pass_attrs,
    v_pass_attrs,
    p_target_table, v_col_list, v_val_list,
    p_bk_column
    );

    -- Увеличиваем память для сортировки LEAD() в рамках транзакции
    EXECUTE 'SET LOCAL work_mem = ''256MB''';
    EXECUTE v_sql;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    -- 5. Фиксируем версию
    PERFORM t3_core.record_version_load(current_dttm, next_version, p_target_table);
    RAISE NOTICE '%: Pattern 1 complete. Rows processed: %', p_target_table, v_rows;

    EXECUTE 'DROP TABLE IF EXISTS staging_data';
END;
$$ LANGUAGE plpgsql;

----------------------------------------------------------------------------------

--HSAT_ACCOUNT
CREATE OR REPLACE PROCEDURE t3_core.load_hsat_account() AS $func$
DECLARE
    v_staging_sql TEXT;
BEGIN
    -- Запрос должен вернуть: bk, hash, create_dttm, delete_dttm, [attributes]
    v_staging_sql := $$
        SELECT 
            stg.account_hash_key,
            stg.hash_diff,
            NULLIF(stg.create_dttm, '')::timestamp as create_dttm,
            NULLIF(stg.delete_dttm, '')::timestamp as delete_dttm,
            scast.account_type_nm,
            stg.account_create_dt::date
        FROM t2_stg.staging_crm_account stg
        LEFT JOIN t2_stg.staging_crm_account_status_type scast 
            ON stg.account_type_cd = scast.account_type_cd
    $$;

    CALL t3_core.load_hsat_generic(
        p_target_table    => 't3_core.HSAT_account',
        p_staging_query   => v_staging_sql,
        p_bk_column       => 'account_hash_key',
        p_src_cd          => 'CRM',
        p_hash_column     => 'hash_diff',
        p_attr_columns    => ARRAY['account_type_nm', 'account_create_dt']
    );
END;
$func$ LANGUAGE plpgsql;




-- HSAT_CAB_CUSTOMER
CREATE OR REPLACE PROCEDURE t3_core.load_hsat_cab_customer() AS $func$
DECLARE
    v_staging_sql TEXT;
BEGIN
    v_staging_sql := $$
        SELECT
            stg.customer_hash_key,
            stg.hash_diff,
            NULLIF(stg.create_dttm, '')::timestamp as create_dttm,
            NULLIF(stg.delete_dttm, '')::timestamp as delete_dttm,
            stg.first_nm,
            stg.last_nm,
            stg.middle_nm,
            stg.birth_dt::date,
            stg.passport_num
        FROM t2_stg.staging_cab_customer stg
    $$;

    CALL t3_core.load_hsat_generic(
        p_target_table    => 't3_core.HSAT_cab_customer',
        p_staging_query   => v_staging_sql,
        p_bk_column       => 'customer_hash_key',
        p_src_cd          => 'CAB',
        p_hash_column     => 'hash_diff',
        p_attr_columns    => ARRAY['first_nm', 'last_nm', 'middle_nm', 'birth_dt', 'passport_num']
    );
END;
$func$ LANGUAGE plpgsql;


-- HSAT_CAB_CUSTOMER_CONTACT
CREATE OR REPLACE PROCEDURE t3_core.load_hsat_cab_customer_contact() AS $func$
DECLARE
    v_staging_sql TEXT;
BEGIN
    v_staging_sql := $$
        SELECT
            stg.customer_hash_key,
            stg.hash_diff_con,
            NULLIF(stg.create_dttm, '')::timestamp as create_dttm,
            NULLIF(stg.delete_dttm, '')::timestamp as delete_dttm,
            stg.phone_num,
            stg.add_phone_num,
            stg.email,
            stg.reg_address_txt,
            stg.fact_address_txt
        FROM t2_stg.staging_cab_customer stg
    $$;

    CALL t3_core.load_hsat_generic(
        p_target_table    => 't3_core.HSAT_cab_customer_contact',
        p_staging_query   => v_staging_sql,
        p_bk_column       => 'customer_hash_key',
        p_src_cd          => 'CAB',
        p_hash_column     => 'hash_diff_con',
        p_attr_columns    => ARRAY['phone_num', 'add_phone_num', 'email', 'reg_address_txt', 'fact_address_txt']
    );
END;
$func$ LANGUAGE plpgsql;


-- HSAT_CRM_CUSTOMER
CREATE OR REPLACE PROCEDURE t3_core.load_hsat_crm_customer() AS $func$
DECLARE
    v_staging_sql TEXT;
BEGIN
    v_staging_sql := $$
        SELECT
            stg.customer_hash_key,
            stg.hash_diff,
            NULLIF(stg.create_dttm, '')::timestamp as create_dttm,
            NULLIF(stg.delete_dttm, '')::timestamp as delete_dttm,
            stg.first_nm,
            stg.last_nm,
            stg.birth_dt::date
        FROM t2_stg.staging_crm_customer stg
    $$;

    CALL t3_core.load_hsat_generic(
        p_target_table    => 't3_core.HSAT_crm_customer',
        p_staging_query   => v_staging_sql,
        p_bk_column       => 'customer_hash_key',
        p_src_cd          => 'CRM',
        p_hash_column     => 'hash_diff',
        p_attr_columns    => ARRAY['first_nm', 'last_nm', 'birth_dt']
    );
END;
$func$ LANGUAGE plpgsql;


-- HSAT_CRM_CUSTOMER_CONTACT
CREATE OR REPLACE PROCEDURE t3_core.load_hsat_crm_customer_contact() AS $func$
DECLARE
    v_staging_sql TEXT;
BEGIN
    v_staging_sql := $$
        SELECT
            stg.customer_hash_key,
            md5(concat_ws(':', stg.phone_num, stg.email)) as hash_diff_con,
            NULLIF(stg.create_dttm, '')::timestamp as create_dttm,
            NULLIF(stg.delete_dttm, '')::timestamp as delete_dttm,
            stg.phone_num,
            stg.email
        FROM t2_stg.staging_crm_customer stg
    $$;

    CALL t3_core.load_hsat_generic(
        p_target_table    => 't3_core.HSAT_crm_customer_contact',
        p_staging_query   => v_staging_sql,
        p_bk_column       => 'customer_hash_key',
        p_src_cd          => 'CRM',
        p_hash_column     => 'hash_diff_con',
        p_attr_columns    => ARRAY['phone_num', 'email']
    );
END;
$func$ LANGUAGE plpgsql;


-- HSAT_REQUEST
CREATE OR REPLACE PROCEDURE t3_core.load_hsat_request() AS $func$
DECLARE
    v_staging_sql TEXT;
BEGIN
    v_staging_sql := $$
        SELECT
            stg.request_hash_key,
            stg.hash_diff,
            NULLIF(stg.create_dttm, '')::timestamp as create_dttm,
            NULLIF(stg.delete_dttm, '')::timestamp as delete_dttm,
            stg.tail_limit::int,
            ssrt.service_request_type_nm
        FROM t2_stg.staging_service_request stg
        LEFT JOIN t2_stg.staging_service_request_type ssrt ON stg.service_request_type_cd = ssrt.service_request_type_cd
    $$;

    CALL t3_core.load_hsat_generic(
        p_target_table    => 't3_core.HSAT_request',
        p_staging_query   => v_staging_sql,
        p_bk_column       => 'request_hash_key',
        p_src_cd          => 'CAB',
        p_hash_column     => 'hash_diff',
        p_attr_columns    => ARRAY['tail_limit', 'service_request_type_nm']
    );
END;
$func$ LANGUAGE plpgsql;


-- HSAT_REQUEST_STATUS
CREATE OR REPLACE PROCEDURE t3_core.load_hsat_request_status() AS $func$
DECLARE
    v_staging_sql TEXT;
BEGIN
    v_staging_sql := $$
        SELECT
            stg.request_hash_key,
            md5(coalesce(ssrs.service_request_status_nm, '')) as hash_diff,
            NULLIF(stg.create_dttm, '')::timestamp as create_dttm,
            NULLIF(stg.delete_dttm, '')::timestamp as delete_dttm,
            ssrs.service_request_status_nm
        FROM t2_stg.staging_service_request stg
        LEFT JOIN t2_stg.staging_service_request_status ssrs ON stg.service_request_status_cd = ssrs.service_request_status_cd
    $$;

    CALL t3_core.load_hsat_generic(
        p_target_table    => 't3_core.HSAT_request_status',
        p_staging_query   => v_staging_sql,
        p_bk_column       => 'request_hash_key',
        p_src_cd          => 'CAB',
        p_hash_column     => 'hash_diff',
        p_attr_columns    => ARRAY['service_request_status_nm']
    );
END;
$func$ LANGUAGE plpgsql;


-- HSAT_APPLICATION
CREATE OR REPLACE PROCEDURE t3_core.load_hsat_application() AS $func$
DECLARE
    v_staging_sql TEXT;
BEGIN
    v_staging_sql := $$
        SELECT
            stg.application_hash_key,
            stg.hash_diff,
            NULLIF(stg.create_dttm, '')::timestamp as create_dttm,
            NULLIF(stg.delete_dttm, '')::timestamp as delete_dttm,
            spt.product_type_nm
        FROM t2_stg.staging_application stg
        LEFT JOIN t2_stg.staging_product_type spt ON stg.product_type_cd = spt.product_type_cd
    $$;

    CALL t3_core.load_hsat_generic(
        p_target_table    => 't3_core.HSAT_application',
        p_staging_query   => v_staging_sql,
        p_bk_column       => 'application_hash_key',
        p_src_cd          => 'CRM',
        p_hash_column     => 'hash_diff',
        p_attr_columns    => ARRAY['product_type_nm']
    );
END;
$func$ LANGUAGE plpgsql;


-- HSAT_TRANSACTION
CREATE OR REPLACE PROCEDURE t3_core.load_hsat_transaction() AS $func$
DECLARE
    v_staging_sql TEXT;
BEGIN
    v_staging_sql := $$
        SELECT
            stg.transaction_hash_key,
            stg.hash_diff,
            NULLIF(stg.create_dttm, '')::timestamp as create_dttm,
            NULLIF(stg.delete_dttm, '')::timestamp as delete_dttm,
            stg.transaction_amt::decimal,
            sctp.transaction_type_nm,
            stg.transaction_dttm::timestamp
        FROM t2_stg.staging_crm_transaction stg
        LEFT JOIN t2_stg.staging_crm_transaction_type sctp ON stg.transaction_type_cd = sctp.transaction_type_cd
    $$;

    CALL t3_core.load_hsat_generic(
        p_target_table    => 't3_core.HSAT_transaction',
        p_staging_query   => v_staging_sql,
        p_bk_column       => 'transaction_hash_key',
        p_src_cd          => 'CRM',
        p_hash_column     => 'hash_diff',
        p_attr_columns    => ARRAY['transaction_amt', 'transaction_type_nm', 'transaction_dttm']
    );
END;
$func$ LANGUAGE plpgsql;
-------------------------------------------------------------------------------------



call t3_core.load_hub_account();
call t3_core.load_hub_customer();
call t3_core.load_hub_request();
call t3_core.load_hub_transaction();
call t3_core.load_hub_application();


call t3_core.load_acc_x_app();
call t3_core.load_cust_x_app();
call t3_core.load_cust_x_req();
call t3_core.load_acc_x_trans();
call t3_core.load_trans_x_orig_trans();



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

select * from t3_core.hsat_account ha 

--CREATE UNLOGGED TABLE staging_data AS 
--select acc_x_app_hash_key, create_dttm, delete_dttm, account_id 
--from t2_stg.staging_crm_account where account_id in ('0', '1');
--
--select * from staging_data;
--
--select * from t3_core.merge_intervals('staging_data', 'acc_x_app_hash_key')
--
--drop table staging_data;


