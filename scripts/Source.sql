-- 1. Создаем схему и сервер
create schema if not exists t1_src;

CREATE EXTENSION IF NOT EXISTS file_fdw;
CREATE SERVER IF NOT EXISTS csv_server FOREIGN DATA WRAPPER file_fdw;

-- 2. Создаём таблицу с метаданными о таблицах источника
DROP TABLE IF EXISTS t1_src.table_metadata;
CREATE TABLE t1_src.table_metadata (
    entity_name VARCHAR(64) PRIMARY KEY,
    columns_def TEXT NOT NULL,
    has_header BOOLEAN NOT NULL -- явно указываем, а не вычисляем
);

-- Заполняем данные
TRUNCATE t1_src.table_metadata;

insert
	into
	t1_src.table_metadata
values 
('advert_source',
	 'advert_source_id VARCHAR(256), 
	 advert_source_nm VARCHAR(256), 
	 monthly_payment_amt VARCHAR(256), 
	 start_month VARCHAR(256), 
	 end_month VARCHAR(256), 
	 create_dttm VARCHAR(256), 
	 delete_dttm VARCHAR(256),
	 last_update VARCHAR(256)',
true),
('application',
	'application_id VARCHAR(256),
	product_type_cd VARCHAR(256),
	customer_id VARCHAR(256),
	advert_source_id VARCHAR(256),
	create_dttm VARCHAR(256),
	delete_dttm VARCHAR(256),
	last_update VARCHAR(256)',
false),
('cab_customer',
	'customer_id VARCHAR(256),
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
	last_update VARCHAR(256)',
true),
('crm_account',
	'account_id VARCHAR(256),
	account_type_cd VARCHAR(256),
	account_create_dt VARCHAR(256),
	account_status_cd VARCHAR(256),
	application_id VARCHAR(256),
	create_dttm VARCHAR(256),
	delete_dttm VARCHAR(256),
	last_update VARCHAR(256)',
true),
('crm_account_status',
	'account_status_cd VARCHAR(256),
	account_status_nm VARCHAR(256),
	last_update VARCHAR(256)',
true),
('crm_account_status_type',
	'account_type_cd VARCHAR(256),
	account_type_nm VARCHAR(256),
	last_update VARCHAR(256)',
true),
('crm_customer',
	'crm_customer_id VARCHAR(256),
	customer_id VARCHAR(256),
	birth_dt VARCHAR(256),
	phone_num VARCHAR(256),
	email VARCHAR(256),
	first_nm VARCHAR(256),
	last_nm VARCHAR(256),
	create_dttm VARCHAR(256),
	delete_dttm VARCHAR(256),
	last_update VARCHAR(256)',
true),
('crm_transaction',
	'transaction_id VARCHAR(256),
	orig_id VARCHAR(256),
	account_id VARCHAR(256),
	transaction_type_cd VARCHAR(256),
	transaction_amt VARCHAR(256),
	transaction_dttm VARCHAR(256),
	create_dttm VARCHAR(256),
	delete_dttm VARCHAR(256),
	last_update VARCHAR(256)',
false),
('crm_transaction_type',
	'transaction_type_cd VARCHAR(256),
	transaction_type_nm VARCHAR(256),
	last_update VARCHAR(256)',
true),
('product_type',
	'product_type_cd VARCHAR(256),
	product_type_nm VARCHAR(256),
	last_update VARCHAR(256)',
true),
('service_request',
	'service_request_id VARCHAR(256),
	customer_id VARCHAR(256),
	service_request_type_cd VARCHAR(256),
	service_request_status_cd VARCHAR(256),
	tail_limit VARCHAR(256),
	create_dttm VARCHAR(256),
	delete_dttm VARCHAR(256),
	last_update VARCHAR(256)',
false),
('service_request_status',
	'service_request_status_cd VARCHAR(256),
	service_request_status_nm VARCHAR(256),
	last_update VARCHAR(256)',
true),
('service_request_type',
	'service_request_type_cd VARCHAR(256),
	service_request_type_nm VARCHAR(256),
	last_update VARCHAR(256)',
true);

-- 3. Функция создания внешней таблицы
CREATE OR REPLACE FUNCTION t1_src.generate_foreign_table_ddl(
    target_schema TEXT,
    entity TEXT
) RETURNS TEXT AS $code$
DECLARE
    meta RECORD;
    ddl TEXT;
    ps_cmd TEXT;
BEGIN
    SELECT * INTO meta FROM t1_src.table_metadata WHERE entity_name = entity;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Entity % not found in metadata', entity;
    END IF;

    -- Формируем команду PowerShell - указываем путь к папке, где лежат данные
    ps_cmd := format(
        $$powershell -command "Get-ChildItem 'C:\\Data\\%I\\*.csv' | ForEach-Object { (Get-Content $_.FullName) -replace '""' }"$$,
        entity
    ); 

    -- Формируем DDL
    ddl := format('
        DROP FOREIGN TABLE IF EXISTS %I.source_%I;
        CREATE FOREIGN TABLE %I.source_%I (
            %s
        ) SERVER csv_server
        OPTIONS (
            program %L,
            format ''csv'',
            header %L,
            quote ''"'',
            escape ''"'',
            delimiter '',''
        );',
        target_schema, entity,
        target_schema, entity,
        meta.columns_def,
        ps_cmd,
        CASE WHEN meta.has_header THEN 'true' ELSE 'false' END
    );

    RETURN ddl;
END;
$code$ LANGUAGE plpgsql;

-- 4. Процедура создания создания внешних таблиц
CREATE OR REPLACE PROCEDURE t1_src.generate_all_source_tables(
    target_schema TEXT DEFAULT 't1_src'
)
LANGUAGE plpgsql
AS $$
DECLARE
    entity TEXT;
    ddl TEXT;
BEGIN
    FOR entity IN 
        SELECT entity_name FROM t1_src.table_metadata
    LOOP
        SELECT t1_src.generate_foreign_table_ddl(target_schema, entity) INTO ddl;
        BEGIN
            EXECUTE ddl;
            RAISE NOTICE '✅ Внешняя таблица source_% создана', entity;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '❌ Ошибка при создании source_%: %', entity, SQLERRM;
        END;
    END LOOP;
END;
$$;


CALL t1_src.generate_all_source_tables('t1_src');