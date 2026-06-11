CREATE SCHEMA IF NOT EXISTS t4_test;

CREATE SCHEMA IF NOT EXISTS t4_test;

-- ============================================================================
-- ТЕСТ 1: Наложение временных интервалов (overlapping intervals)
-- ============================================================================
CREATE OR REPLACE FUNCTION t4_test.check_overlapping_intervals(
    p_table_name TEXT,
    p_bk_column TEXT
)
RETURNS TABLE (
    bk_value TEXT,
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format($sql$
        WITH ordered AS (
            SELECT 
                %I as bk,
                version_id,
                effective_from_dttm,
                effective_to_dttm,
                LEAD(effective_from_dttm) OVER (
                    PARTITION BY %I ORDER BY effective_from_dttm
                ) as next_eff_from
            FROM %s
            WHERE effective_to_dttm != '2999-12-31'
        )
        SELECT 
            bk::TEXT,
            version_id,
            effective_from_dttm,
            effective_to_dttm
        FROM ordered
        WHERE effective_to_dttm > next_eff_from
    $sql$,
    p_bk_column, p_bk_column, p_table_name
    );
    
    RETURN QUERY EXECUTE v_sql;
END;
$$;





-- ============================================================================
-- ТЕСТ 2: Проверка явных дат удаления (effective_to должно быть delete_dttm)
-- ============================================================================
CREATE OR REPLACE FUNCTION t4_test.check_explicit_deletion(
    p_hsat_table TEXT,       -- Таблица HSAT (откуда берем effective_to)
    p_source_table TEXT,     -- Таблица-источник (откуда берем delete_dttm)
    p_bk_column TEXT         -- Название колонки бизнес-ключа
)
RETURNS TABLE (
    bk_value TEXT,
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format($sql$
        SELECT 
            t1.%I::TEXT as bk_value,
            t1.version_id,
            t1.effective_from_dttm,
            t1.effective_to_dttm
        FROM %s t1
        JOIN %s t2 
            ON t1.%I = t2.%I 
           AND t1.effective_from_dttm = NULLIF(TRIM(t2.create_dttm), '')::timestamp
        WHERE NULLIF(TRIM(t2.delete_dttm), '') IS NOT NULL
          AND t1.effective_to_dttm != NULLIF(TRIM(t2.delete_dttm), '')::timestamp
    $sql$,
    p_bk_column, p_hsat_table, p_source_table, p_bk_column, p_bk_column
    );
    
    RETURN QUERY EXECUTE v_sql;
END;
$$;

-- ============================================================================
-- ТЕСТ 3: Множественные актуальные записи (multiple current records)
-- ============================================================================
CREATE OR REPLACE FUNCTION t4_test.check_multiple_current_records(
    p_table_name TEXT,
    p_bk_column TEXT
)
RETURNS TABLE (
    bk_value TEXT,
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format($sql$
        WITH duplicates AS (
            SELECT %I as bk
            FROM %s
            WHERE effective_to_dttm = '2999-12-31'
            GROUP BY %I
            HAVING COUNT(*) > 1
        )
        SELECT 
            t.%I::TEXT,
            t.version_id,
            t.effective_from_dttm,
            t.effective_to_dttm
        FROM %s t
        JOIN duplicates d ON t.%I = d.bk
        WHERE t.effective_to_dttm = '2999-12-31'
    $sql$,
    p_bk_column, p_table_name, p_bk_column,
    p_bk_column, p_table_name, p_bk_column
    );
    
    RETURN QUERY EXECUTE v_sql;
END;
$$;

-- ============================================================================
-- ТЕСТ 4: Разрывы в историчности (gaps between intervals)
-- ============================================================================
CREATE OR REPLACE FUNCTION t4_test.check_gaps_in_history(
    p_table_name TEXT,
    p_bk_column TEXT
)
RETURNS TABLE (
    bk_value TEXT,
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format($sql$
        WITH ordered AS (
            SELECT 
                %I as bk,
                version_id,
                effective_from_dttm,
                effective_to_dttm,
                LEAD(effective_from_dttm) OVER (
                    PARTITION BY %I ORDER BY effective_from_dttm
                ) as next_eff_from
            FROM %s
        )
        SELECT 
            bk::TEXT,
            version_id,
            effective_from_dttm,
            effective_to_dttm
        FROM ordered
        WHERE effective_to_dttm != '2999-12-31'
          AND next_eff_from IS NOT NULL
          AND next_eff_from > effective_to_dttm
    $sql$,
    p_bk_column, p_bk_column, p_table_name
    );
    
    RETURN QUERY EXECUTE v_sql;
END;
$$;

-- ============================================================================
-- ТЕСТ 5: Отсутствие записи в HUB (orphan records)
-- ============================================================================
CREATE OR REPLACE FUNCTION t4_test.check_referential_integrity(
    p_hsat_table TEXT,
    p_hub_table TEXT,
    p_bk_column TEXT
)
RETURNS TABLE (
    bk_value TEXT,
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format($sql$
        SELECT DISTINCT
            t.%I::TEXT,
            t.version_id,
            t.effective_from_dttm,
            t.effective_to_dttm
        FROM %s t
        LEFT JOIN %s h ON t.%I = h.%I
        WHERE h.%I IS NULL
    $sql$,
    p_bk_column, p_hsat_table, p_hub_table, p_bk_column, p_bk_column, p_bk_column
    );
    
    RETURN QUERY EXECUTE v_sql;
END;
$$;

-- ============================================================================
-- ТЕСТ 6: Отрицательная длительность интервала (invalid interval)
-- ============================================================================
CREATE OR REPLACE FUNCTION t4_test.check_invalid_intervals(
    p_table_name TEXT,
    p_bk_column TEXT
)
RETURNS TABLE (
    bk_value TEXT,
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format($sql$
        SELECT 
            %I::TEXT,
            version_id,
            effective_from_dttm,
            effective_to_dttm
        FROM %s
        WHERE effective_from_dttm > effective_to_dttm
    $sql$,
    p_bk_column, p_table_name
    );
    
    RETURN QUERY EXECUTE v_sql;
END;
$$;

-- ============================================================================
-- ТЕСТ 7: Дубликаты по BK + effective_from (duplicate keys)
-- ============================================================================
CREATE OR REPLACE FUNCTION t4_test.check_duplicate_keys(
    p_table_name TEXT,
    p_bk_column TEXT
)
RETURNS TABLE (
    bk_value TEXT,
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format($sql$
        WITH duplicates AS (
            SELECT %I as bk, effective_from_dttm
            FROM %s
            GROUP BY %I, effective_from_dttm
            HAVING COUNT(*) > 1
        )
        SELECT 
            t.%I::TEXT,
            t.version_id,
            t.effective_from_dttm,
            t.effective_to_dttm
        FROM %s t
        JOIN duplicates d 
            ON t.%I = d.bk 
           AND t.effective_from_dttm = d.effective_from_dttm
    $sql$,
    p_bk_column, p_table_name, p_bk_column,
    p_bk_column, p_table_name, p_bk_column
    );
    
    RETURN QUERY EXECUTE v_sql;
END;
$$;

-- ============================================================================
-- ТЕСТ 8: NULL в обязательных полях (NULL in required columns)
-- ============================================================================
CREATE OR REPLACE FUNCTION t4_test.check_null_required_field(
    p_table_name TEXT,
    p_bk_column TEXT,
    p_column_name TEXT
)
RETURNS TABLE (
    bk_value TEXT,
    version_id BIGINT,
    effective_from_dttm TIMESTAMP,
    effective_to_dttm TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sql TEXT;
BEGIN
    v_sql := format($sql$
        SELECT 
            %I::TEXT,
            version_id,
            effective_from_dttm,
            effective_to_dttm
        FROM %s
        WHERE %I IS NULL
    $sql$,
    p_bk_column, p_table_name, p_column_name
    );
    
    RETURN QUERY EXECUTE v_sql;
END;
$$;

-------------------------------------------------------------------------------

-- 1. Наложение
--SELECT * FROM t4_test.check_overlapping_intervals('t3_core.HSAT_account', 'account_hash_key');
--
-- 2. Ошибки в дате удаления (сравниваем с staging)
--SELECT * FROM t4_test.check_explicit_deletion(
--    't3_core.HSAT_account', 
--    't2_stg.staging_crm_account', 
--    'account_hash_key'
--);
--
-- 3. Дубли актуальных записей
--SELECT * FROM t4_test.check_multiple_current_records('t3_core.HSAT_account', 'account_hash_key');
--
-- 4. Разрывы
--SELECT * FROM t4_test.check_gaps_in_history('t3_core.HSAT_account', 'account_hash_key');
--
-- 5. Сироты (нет в HUB)
--SELECT * FROM t4_test.check_referential_integrity(
--    't3_core.HSAT_account', 
--    't3_core.HUB_account', 
--    'account_hash_key'
--);
--
-- 6. Отрицательный интервал
--SELECT * FROM t4_test.check_invalid_intervals('t3_core.HSAT_account', 'account_hash_key');
--
-- 7. Дубли PK
--SELECT * FROM t4_test.check_duplicate_keys('t3_core.HSAT_account', 'account_hash_key');
--
-- 8. NULL в hash_diff
--SELECT * FROM t4_test.check_null_required_field('t3_core.HSAT_account', 'account_hash_key', 'hash_diff');

---------------------------------------------------------------------------------
CREATE OR REPLACE VIEW t4_test.v_test_results AS
WITH test_execution AS (
    -- ТЕСТ 1: Наложение временных интервалов
    SELECT 
        't3_core.HSAT_account' AS table_name,
        'check_overlapping_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_overlapping_intervals('t3_core.HSAT_account', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account_status' AS table_name,
        'check_overlapping_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_overlapping_intervals('t3_core.HSAT_account_status', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_application' AS table_name,
        'check_overlapping_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_overlapping_intervals('t3_core.HSAT_application', 'application_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_crm_customer' AS table_name,
        'check_overlapping_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_overlapping_intervals('t3_core.HSAT_crm_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_cab_customer' AS table_name,
        'check_overlapping_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_overlapping_intervals('t3_core.HSAT_cab_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request' AS table_name,
        'check_overlapping_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_overlapping_intervals('t3_core.HSAT_request', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request_status' AS table_name,
        'check_overlapping_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_overlapping_intervals('t3_core.HSAT_request_status', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_transaction' AS table_name,
        'check_overlapping_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_overlapping_intervals('t3_core.HSAT_transaction', 'transaction_hash_key')
    
    union ALL
    -- ТЕСТ 2: Проверка даты удаления
    SELECT 
        't3_core.HSAT_account' AS table_name,
        'check_explicit_deletion' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_explicit_deletion(
    't3_core.HSAT_account', 
    't2_stg.staging_crm_account', 
    'account_hash_key'
    )
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account_status' AS table_name,
        'check_explicit_deletion' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_explicit_deletion(
    't3_core.HSAT_account_status', 
    't2_stg.staging_crm_account', 
    'account_hash_key'
    )
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_application' AS table_name,
        'check_explicit_deletion' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_explicit_deletion(
    't3_core.HSAT_application', 
    't2_stg.staging_application', 
    'application_hash_key'
    )
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_crm_customer' AS table_name,
        'check_explicit_deletion' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_explicit_deletion(
    't3_core.HSAT_crm_customer', 
    't2_stg.staging_crm_customer', 
    'customer_hash_key'
    )
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_cab_customer' AS table_name,
        'check_explicit_deletion' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_explicit_deletion(
    't3_core.HSAT_cab_customer', 
    't2_stg.staging_cab_customer', 
    'customer_hash_key'
    )
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request' AS table_name,
        'check_explicit_deletion' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_explicit_deletion(
    't3_core.HSAT_request', 
    't2_stg.staging_service_request', 
    'request_hash_key'
    )
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request_status' AS table_name,
        'check_explicit_deletion' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_explicit_deletion(
    't3_core.HSAT_request_status', 
    't2_stg.staging_service_request', 
    'request_hash_key'
    )
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_transaction' AS table_name,
        'check_explicit_deletion' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_explicit_deletion(
    't3_core.HSAT_transaction', 
    't2_stg.staging_crm_transaction', 
    'transaction_hash_key'
    )
    
    -- ТЕСТ 3: Множественные актуальные записи
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account' AS table_name,
        'check_multiple_current_records' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_multiple_current_records('t3_core.HSAT_account', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account_status' AS table_name,
        'check_multiple_current_records' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_multiple_current_records('t3_core.HSAT_account_status', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_application' AS table_name,
        'check_multiple_current_records' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_multiple_current_records('t3_core.HSAT_application', 'application_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_crm_customer' AS table_name,
        'check_multiple_current_records' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_multiple_current_records('t3_core.HSAT_crm_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_cab_customer' AS table_name,
        'check_multiple_current_records' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_multiple_current_records('t3_core.HSAT_cab_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request' AS table_name,
        'check_multiple_current_records' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_multiple_current_records('t3_core.HSAT_request', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request_status' AS table_name,
        'check_multiple_current_records' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_multiple_current_records('t3_core.HSAT_request_status', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_transaction' AS table_name,
        'check_multiple_current_records' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_multiple_current_records('t3_core.HSAT_transaction', 'transaction_hash_key')
    
    -- ТЕСТ 4: Разрывы в историчности
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account' AS table_name,
        'check_gaps_in_history' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_gaps_in_history('t3_core.HSAT_account', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account_status' AS table_name,
        'check_gaps_in_history' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_gaps_in_history('t3_core.HSAT_account_status', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_application' AS table_name,
        'check_gaps_in_history' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_gaps_in_history('t3_core.HSAT_application', 'application_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_crm_customer' AS table_name,
        'check_gaps_in_history' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_gaps_in_history('t3_core.HSAT_crm_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_cab_customer' AS table_name,
        'check_gaps_in_history' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_gaps_in_history('t3_core.HSAT_cab_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request' AS table_name,
        'check_gaps_in_history' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_gaps_in_history('t3_core.HSAT_request', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request_status' AS table_name,
        'check_gaps_in_history' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_gaps_in_history('t3_core.HSAT_request_status', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_transaction' AS table_name,
        'check_gaps_in_history' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_gaps_in_history('t3_core.HSAT_transaction', 'transaction_hash_key')
    
    -- ТЕСТ 5: Отсутствие записи в HUB (orphan records)
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account' AS table_name,
        'check_referential_integrity' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_referential_integrity('t3_core.HSAT_account', 't3_core.HUB_account', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account_status' AS table_name,
        'check_referential_integrity' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_referential_integrity('t3_core.HSAT_account_status', 't3_core.HUB_account', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_application' AS table_name,
        'check_referential_integrity' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_referential_integrity('t3_core.HSAT_application', 't3_core.HUB_application', 'application_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_crm_customer' AS table_name,
        'check_referential_integrity' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_referential_integrity('t3_core.HSAT_crm_customer', 't3_core.HUB_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_cab_customer' AS table_name,
        'check_referential_integrity' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_referential_integrity('t3_core.HSAT_cab_customer', 't3_core.HUB_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request' AS table_name,
        'check_referential_integrity' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_referential_integrity('t3_core.HSAT_request', 't3_core.HUB_request', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request_status' AS table_name,
        'check_referential_integrity' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_referential_integrity('t3_core.HSAT_request_status', 't3_core.HUB_request', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_transaction' AS table_name,
        'check_referential_integrity' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_referential_integrity('t3_core.HSAT_transaction', 't3_core.HUB_transaction', 'transaction_hash_key')
    
    -- ТЕСТ 6: Отрицательная длительность интервала
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account' AS table_name,
        'check_invalid_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_invalid_intervals('t3_core.HSAT_account', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account_status' AS table_name,
        'check_invalid_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_invalid_intervals('t3_core.HSAT_account_status', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_application' AS table_name,
        'check_invalid_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_invalid_intervals('t3_core.HSAT_application', 'application_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_crm_customer' AS table_name,
        'check_invalid_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_invalid_intervals('t3_core.HSAT_crm_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_cab_customer' AS table_name,
        'check_invalid_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_invalid_intervals('t3_core.HSAT_cab_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request' AS table_name,
        'check_invalid_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_invalid_intervals('t3_core.HSAT_request', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request_status' AS table_name,
        'check_invalid_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_invalid_intervals('t3_core.HSAT_request_status', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_transaction' AS table_name,
        'check_invalid_intervals' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_invalid_intervals('t3_core.HSAT_transaction', 'transaction_hash_key')
    
    -- ТЕСТ 7: Дубликаты по BK + effective_from
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account' AS table_name,
        'check_duplicate_keys' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_duplicate_keys('t3_core.HSAT_account', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account_status' AS table_name,
        'check_duplicate_keys' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_duplicate_keys('t3_core.HSAT_account_status', 'account_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_application' AS table_name,
        'check_duplicate_keys' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_duplicate_keys('t3_core.HSAT_application', 'application_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_crm_customer' AS table_name,
        'check_duplicate_keys' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_duplicate_keys('t3_core.HSAT_crm_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_cab_customer' AS table_name,
        'check_duplicate_keys' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_duplicate_keys('t3_core.HSAT_cab_customer', 'customer_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request' AS table_name,
        'check_duplicate_keys' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_duplicate_keys('t3_core.HSAT_request', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request_status' AS table_name,
        'check_duplicate_keys' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_duplicate_keys('t3_core.HSAT_request_status', 'request_hash_key')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_transaction' AS table_name,
        'check_duplicate_keys' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_duplicate_keys('t3_core.HSAT_transaction', 'transaction_hash_key')
    
    -- ТЕСТ 8: NULL в обязательных полях (hash_diff)
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account' AS table_name,
        'check_null_hash_diff' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_null_required_field('t3_core.HSAT_account', 'account_hash_key', 'hash_diff')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_account_status' AS table_name,
        'check_null_hash_diff' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_null_required_field('t3_core.HSAT_account_status', 'account_hash_key', 'hash_diff')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_application' AS table_name,
        'check_null_hash_diff' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_null_required_field('t3_core.HSAT_application', 'application_hash_key', 'hash_diff')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_crm_customer' AS table_name,
        'check_null_hash_diff' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_null_required_field('t3_core.HSAT_crm_customer', 'customer_hash_key', 'hash_diff')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_cab_customer' AS table_name,
        'check_null_hash_diff' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_null_required_field('t3_core.HSAT_cab_customer', 'customer_hash_key', 'hash_diff')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request' AS table_name,
        'check_null_hash_diff' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_null_required_field('t3_core.HSAT_request', 'request_hash_key', 'hash_diff')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_request_status' AS table_name,
        'check_null_hash_diff' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_null_required_field('t3_core.HSAT_request_status', 'request_hash_key', 'hash_diff')
    
    UNION ALL
    
    SELECT 
        't3_core.HSAT_transaction' AS table_name,
        'check_null_hash_diff' AS test_name,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS result,
        STRING_AGG(distinct version_id::text, '#') as versions,
        COUNT(*) AS error_count
    FROM t4_test.check_null_required_field('t3_core.HSAT_transaction', 'transaction_hash_key', 'hash_diff')
)
SELECT 
    table_name,
    test_name,
    result,
    versions,
    error_count,
    NOW() AS check_timestamp
FROM test_execution
ORDER BY table_name, test_name;




-- 1. Статистика по таблицам
SELECT 
    table_name,
    COUNT(*) AS total_tests,
    SUM(CASE WHEN result = 'PASS' THEN 1 ELSE 0 END) AS passed_tests,
    SUM(CASE WHEN result = 'FAIL' THEN 1 ELSE 0 END) AS failed_tests,
    ROUND(100.0 * SUM(CASE WHEN result = 'PASS' THEN 1 ELSE 0 END) / COUNT(*), 2) AS pass_rate_percent
FROM t4_test.v_test_results
GROUP BY table_name
ORDER BY pass_rate_percent ASC;


-- 2. Статистика по падениям
SELECT 
    table_name,
    test_name,
    versions
FROM t4_test.v_test_results
where result = 'FAIL';