CREATE SCHEMA IF NOT EXISTS t4_mart;


--with tab as (
--	select 'pear' as product, 2 as cnt
--	union
--	select 'pear' as product, 3 as cnt
--	union
--	select 'apple' as product, 4 as cnt
--	union
--	select 'apple' as product, 5 as cnt
--	union
--	select 'pear' as product, 6 as cnt
--)
--select 
--	product,
--	sum(cnt) over(),
--	sum(cnt) over(partition by product),
--	sum(cnt) over(order by product),
--	sum(cnt) over(range between unbounded preceding and current row),
--	sum(cnt) over(rows between unbounded preceding and current row)
--from tab



--drop view if exists t4_mart.activation_deactivation_monthly;
--drop view if exists t4_mart.activation_deactivation_weekly;
--drop view if exists t4_mart.retention_monthly;
--drop view if exists t4_mart.user_activity_monthly;
--drop view if exists t4_mart.transaction_info;
--drop view if exists t4_mart.metrics_monthly_unified;
--drop view if exists t4_mart.customer_monthly_snapshot;
--drop view if exists t4_mart.tail_info;
--drop view t4_mart.customer_revenue;
--drop view t4_mart.v_churn_rate_monthly;
--drop view t4_mart.v_arpu_monthly;
--drop view t4_mart.v_ltv_churn_based;

-- t4_mart.tail_info
create or replace view t4_mart.tail_info as
select 
	lcxr.customer_hash_key, 
	hr2.effective_from_dttm,
	coalesce (
	lead(hr2.effective_from_dttm) over w,
	'2999-12-31'::timestamp) effective_to_dttm,
	hr2.tail_limit,
	hr2.service_request_type_nm,
    LAG(hr2.service_request_type_nm) over w AS prev_status
from 
	t3_core.link_cust_x_req lcxr
	left join t3_core.hsat_request hr2 using(request_hash_key)
	left join t3_core.hsat_request_status hrs using(request_hash_key)
where hrs.service_request_status_nm = 'done'
window w as (partition by lcxr.customer_hash_key order by hr2.effective_from_dttm asc);



-- t4_mart.transaction_info
create or replace view t4_mart.transaction_info as
select
	ht.transaction_hash_key
	, ltot.orig_transaction_hash_key 
	, laxt.account_hash_key
	, lcxa.customer_hash_key
	, ht2.transaction_amt
	, ht2.transaction_type_nm
	, ti.tail_limit
    , ti.service_request_type_nm
	, ht2.transaction_dttm
	, ht2.effective_from_dttm
	, ht2.effective_to_dttm
from 
	t3_core.hub_transaction ht
	left join t3_core.hsat_transaction ht2 on ht2.transaction_hash_key = ht.transaction_hash_key
	left join t3_core.link_trans_x_orig_trans ltot on ht.transaction_hash_key = ltot.transaction_hash_key
	join t3_core.link_acc_x_trans laxt on ht.transaction_hash_key = laxt.transaction_hash_key
	left join t3_core.lsat_acc_x_trans laxt2 on laxt2.acc_x_trans_hash_key = laxt.acc_x_trans_hash_key
	join t3_core.link_acc_x_app laxa on laxt.account_hash_key = laxa.account_hash_key
	left join t3_core.lsat_acc_x_app laxa2 on laxa2.acc_x_app_hash_key = laxa.acc_x_app_hash_key	
	join t3_core.link_cust_x_app lcxa on laxa.application_hash_key = lcxa.application_hash_key
	left join t3_core.lsat_cust_x_app lcxa2 on lcxa2.cust_x_app_hash_key = lcxa.cust_x_app_hash_key
	left join t4_mart.tail_info ti 
		on lcxa.customer_hash_key = ti.customer_hash_key
		and ti.effective_from_dttm <= ht2.transaction_dttm
		and ht2.transaction_dttm < ti.effective_to_dttm
;
--where ht2.transaction_type_nm = 'kopylka'
--and ht2.transaction_amt >= ti.tail_limit
		
	
	
--------------------------------------------------------------------------------------------	
-- Метрика ACTIVATION
	
CREATE OR REPLACE FUNCTION t4_mart.calc_activation_deactivation(
    p_calc_date DATE,
    p_lookback_interval INTERVAL DEFAULT interval '2000 days'
)
RETURNS TABLE (
    calc_date DATE,
    activation BIGINT,
    deactivation BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH tail_info_prev AS (
        SELECT 
            ti.customer_hash_key,
            ti.service_request_type_nm,
            ti.effective_from_dttm,
            ti.effective_to_dttm,
            LEAD(ti.service_request_type_nm) OVER (
                PARTITION BY ti.customer_hash_key 
                ORDER BY ti.effective_to_dttm DESC
            ) AS prev_status
        FROM t4_mart.tail_info ti
    ),
    tail_info_prev_actual AS (
        SELECT 
            tip.*
        FROM tail_info_prev tip
        WHERE 		
            tip.effective_from_dttm <= p_calc_date
            AND p_calc_date - p_lookback_interval < tip.effective_from_dttm
    ),
    activation_calc AS (
        SELECT 
            COUNT(tipa.customer_hash_key) AS activation_count
        FROM tail_info_prev_actual tipa
        WHERE 		
            tipa.service_request_type_nm in ('chg_round', 'enable')
            AND (tipa.prev_status = 'disable' OR tipa.prev_status IS NULL)
    ),
    deactivation_calc AS (
        SELECT 
            COUNT(tipa.customer_hash_key) AS deactivation_count
        FROM tail_info_prev_actual tipa
        WHERE 		
            tipa.service_request_type_nm = 'disable'
            AND tipa.prev_status in ('chg_round', 'enable')
    )
    SELECT 
        p_calc_date AS calc_date,
        ac.activation_count AS activation,
        dc.deactivation_count AS deactivation
    FROM activation_calc ac
    CROSS JOIN deactivation_calc dc;
END;
$$ LANGUAGE plpgsql;	
	



CREATE OR REPLACE VIEW t4_mart.activation_deactivation_monthly AS
SELECT 
    d.date as to_date,
    d.date - INTERVAL '30 day' as from_date,
    m.activation,
    m.deactivation,
    m.activation - m.deactivation AS net_change
FROM 
    generate_series('2019-12-31'::date, '2022-12-31'::date, INTERVAL '30 day') AS d
    CROSS JOIN LATERAL t4_mart.calc_activation_deactivation(d.date, INTERVAL '30 day') m;



CREATE OR REPLACE VIEW t4_mart.activation_deactivation_weekly AS
SELECT 
    d.date as to_date,
    d.date - INTERVAL '7 day' as from_date,
    m.activation,
    m.deactivation,
    m.activation - m.deactivation AS net_change
FROM 
    generate_series('2019-12-31'::date, '2022-12-31'::date, INTERVAL '7 day') AS d
    CROSS JOIN LATERAL t4_mart.calc_activation_deactivation(d.date, INTERVAL '7 day') m;



--------------------------------------------------------------------------------------------	
-- Метрика RETENTION

CREATE OR REPLACE VIEW t4_mart.retention_monthly AS
WITH monthly_activity AS (
    -- 1. Уникальные пользователи по месяцам их активности
    SELECT DISTINCT
        customer_hash_key,
        DATE_TRUNC('month', effective_from_dttm) AS activity_month
    FROM t4_mart.tail_info
    WHERE service_request_type_nm != 'disable'
),
retention_flags AS (
    -- 2. Проверяем, вернулся ли пользователь в следующем месяце
    SELECT
        curr.activity_month AS current_month,
        curr.customer_hash_key,
        CASE WHEN next.activity_month IS NOT NULL THEN 1 ELSE 0 END AS is_retained
    FROM monthly_activity curr
    LEFT JOIN monthly_activity next
        ON curr.customer_hash_key = next.customer_hash_key
       AND next.activity_month = curr.activity_month + INTERVAL '1 month'
),
monthly_metrics AS (
    -- 3. Считаем общие и удержанные значения по месяцам
    SELECT
        current_month,
        COUNT(customer_hash_key) AS total_users,
        SUM(is_retained) AS retained_users
    FROM retention_flags
    GROUP BY current_month
)
-- 4. Итоговая метрика
SELECT
    current_month,
    total_users,
    retained_users,
    ROUND(retained_users::NUMERIC / NULLIF(total_users, 0), 4) AS retention_rate
FROM monthly_metrics
ORDER BY current_month;


--------------------------------------------------------------------------------------------	
-- Числовые метрики

CREATE OR REPLACE VIEW t4_mart.user_activity_monthly AS
WITH 
-- 1. Сетка месяцев для отчётности
monthly_grid AS (
    SELECT DATE_TRUNC('month', dt) AS month_dt
    FROM generate_series('2020-01-01'::date, '2022-12-31'::date, INTERVAL '1 month') AS dt
),

-- 2. Активные пользователи в каждом месяце (из hsat_cab_customer)
active_users AS (
    SELECT 
        mg.month_dt,
        hc.customer_hash_key
    FROM monthly_grid mg
    JOIN t3_core.hsat_cab_customer hcc 
        ON mg.month_dt::timestamp > hcc.effective_from_dttm 
        AND mg.month_dt < COALESCE(hcc.effective_to_dttm, '9999-12-31'::timestamp)
    join t3_core.hub_customer hc using(customer_hash_key)
),

-- 3. Заявки на копилку с периодами действия (только статус done)
sr_with_periods AS (
    SELECT 
        lcxr.customer_hash_key,
        hr2.effective_from_dttm,
        LEAD(hr2.effective_from_dttm) OVER (PARTITION BY lcxr.customer_hash_key ORDER BY hr2.effective_from_dttm) AS effective_to,
        hr2.tail_limit,
        hr2.service_request_type_nm
	from 
		t3_core.link_cust_x_req lcxr
		left join t3_core.hsat_request hr2 using(request_hash_key)
		left join t3_core.hsat_request_status hrs using(request_hash_key)
	where hrs.service_request_status_nm = 'done'
),

-- 4. Статус копилки для каждого пользователя в каждом месяце
user_kopylka_by_month AS (
    SELECT 
        au.month_dt,
        au.customer_hash_key,
        sr.effective_from_dttm,
        COALESCE(sr.tail_limit::int, 0) AS tail_limit,
        sr.service_request_type_nm
    FROM active_users au
    LEFT JOIN sr_with_periods sr on au.customer_hash_key = sr.customer_hash_key
        AND au.month_dt::timestamp >= sr.effective_from_dttm::timestamp
        AND au.month_dt::timestamp < COALESCE(sr.effective_to::timestamp, '2999-12-31'::timestamp)
),

-- ============================================================
-- МЕТРИКА 1: % пользователей с активной копилкой (tail_limit > 0)
-- ============================================================
metric1 AS (
    SELECT 
        month_dt,
        COUNT(DISTINCT customer_hash_key) AS total_active_users,
        COUNT(DISTINCT CASE WHEN tail_limit::int> 0 THEN customer_hash_key END) AS kopylka_users,
        100*ROUND(
            (COUNT(DISTINCT CASE WHEN tail_limit::int > 0 THEN customer_hash_key END))::decimal / 
            NULLIF(COUNT(DISTINCT customer_hash_key), 0), 
            4
        ) AS kopylka_usage_pct
    FROM user_kopylka_by_month
    GROUP BY month_dt
)
-- ============================================================
-- ФИНАЛЬНЫЙ ВЫВОД
-- ============================================================
SELECT 
    m1.month_dt,
    m1.total_active_users,
    m1.kopylka_users,
    m1.total_active_users - m1.kopylka_users as not_active_user,
    m1.kopylka_usage_pct
FROM metric1 m1
ORDER BY m1.month_dt;


--------------------------------------------------------------------------------------------
select * from t4_mart.user_activity_monthly
--------------------------------------------------------------------------------------------

select *
from t4_mart.calc_activation_deactivation('2020-04-28'::date, interval '30 days');


--------------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW t4_mart.metrics_monthly_unified AS
WITH 
-- 1. Общая сетка месяцев
monthly_grid AS (
    SELECT DATE_TRUNC('month', dt)::date AS month_dt
    FROM generate_series('2020-01-01'::date, '2022-12-31'::date, INTERVAL '1 month') AS dt
),

-- 2. Метрика ACTIVATION/DEACTIVATION (агрегируем по месяцам)
activation_monthly AS (
    SELECT 
        DATE_TRUNC('month', d.date)::date AS month_dt,
        SUM(m.activation) AS activation,
        SUM(m.deactivation) AS deactivation,
        SUM(m.activation - m.deactivation) AS net_change
    FROM 
        generate_series('2020-01-01'::date, '2022-12-31'::date, INTERVAL '1 month') AS d
        CROSS JOIN LATERAL t4_mart.calc_activation_deactivation(d.date, INTERVAL '1 month') m
    GROUP BY DATE_TRUNC('month', d.date)
),

-- 3. Метрика RETENTION (уже по месяцам)
retention_monthly AS (
    SELECT 
        current_month AS month_dt,
        total_users,
        retained_users,
        ROUND(retained_users::NUMERIC / NULLIF(total_users, 0), 3) AS retention_rate
    FROM (
        WITH monthly_activity AS (
            SELECT DISTINCT
                customer_hash_key,
                DATE_TRUNC('month', effective_from_dttm) AS activity_month
            FROM t4_mart.tail_info
            WHERE service_request_type_nm != 'disable'
        ),
        retention_flags AS (
            SELECT
                curr.activity_month AS current_month,
                curr.customer_hash_key,
                CASE WHEN next.activity_month IS NOT NULL THEN 1 ELSE 0 END AS is_retained
            FROM monthly_activity curr
            LEFT JOIN monthly_activity next
                ON curr.customer_hash_key = next.customer_hash_key
               AND next.activity_month = curr.activity_month + INTERVAL '1 month'
        ),
        monthly_metrics AS (
            SELECT
                current_month,
                COUNT(customer_hash_key) AS total_users,
                SUM(is_retained) AS retained_users
            FROM retention_flags
            GROUP BY current_month
        )
        SELECT * FROM monthly_metrics
    ) sub
),

-- 4. Метрика USER_ACTIVITY / KOPYLKA (уже по месяцам)
kopylka_monthly AS (
    WITH 
    active_users AS (
        SELECT 
            mg.month_dt,
            hc.customer_hash_key
        FROM monthly_grid mg
        JOIN t3_core.hsat_cab_customer hcc 
            ON mg.month_dt::timestamp > hcc.effective_from_dttm 
            AND mg.month_dt < COALESCE(hcc.effective_to_dttm, '9999-12-31'::timestamp)
        JOIN t3_core.hub_customer hc USING(customer_hash_key)
    ),
    sr_with_periods AS (
        SELECT 
            lcxr.customer_hash_key,
            hr2.effective_from_dttm,
            LEAD(hr2.effective_from_dttm) OVER (PARTITION BY lcxr.customer_hash_key ORDER BY hr2.effective_from_dttm) AS effective_to,
            hr2.tail_limit,
            hr2.service_request_type_nm
        FROM t3_core.link_cust_x_req lcxr
        LEFT JOIN t3_core.hsat_request hr2 USING(request_hash_key)
        LEFT JOIN t3_core.hsat_request_status hrs USING(request_hash_key)
        WHERE hrs.service_request_status_nm = 'done'
    ),
    user_kopylka_by_month AS (
        SELECT 
            au.month_dt,
            au.customer_hash_key,
            sr.effective_from_dttm,
            COALESCE(sr.tail_limit::int, 0) AS tail_limit
        FROM active_users au
        LEFT JOIN sr_with_periods sr 
            ON au.customer_hash_key = sr.customer_hash_key
            AND au.month_dt::timestamp >= sr.effective_from_dttm::timestamp
            AND au.month_dt::timestamp < COALESCE(sr.effective_to::timestamp, '2999-12-31'::timestamp)
    ),
    metric1 AS (
        SELECT 
            month_dt,
            COUNT(DISTINCT customer_hash_key) AS total_active_users,
            COUNT(DISTINCT CASE WHEN tail_limit::int > 0 THEN customer_hash_key END) AS kopylka_users,
            100*ROUND(
                (COUNT(DISTINCT CASE WHEN tail_limit::int > 0 THEN customer_hash_key END))::decimal / 
                NULLIF(COUNT(DISTINCT customer_hash_key), 0), 
                4
            ) AS kopylka_usage_pct
        FROM user_kopylka_by_month
        GROUP BY month_dt
    )
    SELECT * FROM metric1
)

-- 5. Объединяем все метрики по month_dt
SELECT 
    mg.month_dt,
    COALESCE(am.activation, 0) AS activation,
    COALESCE(am.deactivation, 0) AS deactivation,
    COALESCE(am.net_change, 0) AS net_change,
    COALESCE(rm.total_users, 0) AS total_users,
    COALESCE(rm.retained_users, 0) AS retained_users,
    COALESCE(rm.retention_rate, 0) AS retention_rate,
    COALESCE(km.kopylka_users, 0) AS kopylka_users,
    COALESCE(km.kopylka_usage_pct, 0) AS kopylka_usage_pct
FROM monthly_grid mg
LEFT JOIN activation_monthly am ON mg.month_dt = am.month_dt
LEFT JOIN retention_monthly rm ON mg.month_dt = rm.month_dt
LEFT JOIN kopylka_monthly km ON mg.month_dt = km.month_dt
ORDER BY mg.month_dt;




select * from t4_mart.activation_deactivation_monthly;
select * from t4_mart.metrics_monthly_unified;
--------------------------------------------------------------------------------------------
--Проверки КД



select ti.customer_hash_key, sum(transaction_amt)
from t4_mart.transaction_info ti
where ti.transaction_type_nm = 'kopylka'
group by ti.customer_hash_key having round(sum(transaction_amt)) != 0;

--select ti.customer_hash_key, ti.transaction_amt
--from t4_mart.transaction_info ti
--where ti.transaction_type_nm = 'kopylka'
--and ti.customer_hash_key= 'C74D97B01EAE257E44AA9D5BADE97BAF'
--order by abs(ti.transaction_amt)



select ht.transaction_hash_key, ti.transaction_hash_key, ht.transaction_amt, ti.transaction_amt, ti.tail_limit
from 
	t4_mart.transaction_info ti
	join t3_core.hsat_transaction ht on ti.orig_transaction_hash_key = ht.transaction_hash_key
where 
	ti.transaction_type_nm = 'kopylka'
	and abs(ti.transaction_amt) > ti.tail_limit
	--and ti.customer_hash_key= '54229ABFCFA5649E7003B83DD4755294'
order by ht.transaction_hash_key;




--select customer_id, account_type_cd, spt.product_type_nm
--from t2_stg.staging_crm_account sca
--join t2_stg.staging_application sa using(application_id)
--join t2_stg.staging_product_type spt on sca.account_type_cd = spt.product_type_cd
--where customer_id in ('51', '57', '91')





select *
from t4_mart.transaction_info ti
where ti.orig_transaction_hash_key = '0008E5C19677EB25654FD6B3093F0946'

select *
from t4_mart.transaction_info ti
where ti.transaction_hash_key = '000D5320841FD5D0843BCFBEA3A1F19B'

select *
from t4_mart.tail_info ti
where ti.customer_hash_key= 'D1FE173D08E959397ADF34B1D77E88D7'


-------------------------------------------------------------------------

SELECT * FROM t2_stg.staging_service_request_type


select EXTRACT(EPOCH FROM load_dttm) from t3_core.load_version_registry lvr 

select EXTRACT(EPOCH FROM interval '3 day')




select ha1.* 
from 
	t3_core.hsat_account ha1 
	join t3_core.hub_account ha2 using(account_hash_key)
where account_id = '0'
order by effective_from_dttm desc


select s.account_id, s.create_dttm 
from 
	t2_stg.staging_crm_account s
group by s.account_id, s.create_dttm 
having count(*) > 1


select *
from 
	t3_core.hub_transaction a
	join t3_core.hsat_transaction b using(transaction_hash_key)
	where b.transaction_type_nm = 'kopylka' and transaction_amt > 0
	
	
	
-- REVENUE
CREATE OR REPLACE VIEW t4_mart.customer_revenue AS
    -- Расчет комиссии по каждому клиенту в разрезе месяцев
    SELECT 
        lca.customer_hash_key,
        DATE_TRUNC('month', hat.transaction_dttm)::DATE AS revenue_month,
        SUM(ROUND((hat.transaction_amt * 0.01)::NUMERIC, 2)) AS monthly_revenue
    FROM t3_core.HUB_transaction ht
    INNER JOIN t3_core.HSAT_transaction hat 
        ON ht.transaction_hash_key = hat.transaction_hash_key
    INNER JOIN t3_core.LINK_acc_x_trans lat 
        ON ht.transaction_hash_key = lat.transaction_hash_key
    INNER JOIN t3_core.LINK_acc_x_app laa 
        ON lat.account_hash_key = laa.account_hash_key
    INNER JOIN t3_core.LINK_cust_x_app lca 
        ON laa.application_hash_key = lca.application_hash_key
    INNER JOIN t3_core.LINK_cust_x_req lcr 
        ON lca.customer_hash_key = lcr.customer_hash_key
    WHERE 
        hat.transaction_type_nm = 'kopylka'
        AND hat.transaction_amt > 0
        AND hat.transaction_dttm >= hat.effective_from_dttm
        AND hat.transaction_dttm < hat.effective_to_dttm
--        AND lcr.cust_x_req_hash_key = lcr.cust_x_req_hash_key
    GROUP BY lca.customer_hash_key, DATE_TRUNC('month', hat.transaction_dttm)
ORDER BY DATE_TRUNC('month', hat.transaction_dttm);



-- Метрика LTV
CREATE OR REPLACE VIEW t4_mart.v_churn_rate_monthly AS
WITH monthly_customers AS (
    -- Определяем активных клиентов по месяцам на основе статусов запроса
    SELECT 
        lcr.customer_hash_key,
        DATE_TRUNC('month', hsat.effective_from_dttm)::DATE AS active_month,
        hsat.service_request_type_nm,
        -- Клиент активен, если статус не 'disable'
        CASE WHEN hsat.service_request_type_nm != 'disable' THEN true ELSE false END AS is_active
    FROM t3_core.LINK_cust_x_req lcr
    INNER JOIN t3_core.HSAT_request hsat 
        ON lcr.request_hash_key = hsat.request_hash_key
    WHERE 
        hsat.effective_to_dttm = '2999-12-31'::TIMESTAMP  -- Только актуальные записи
        -- Ограничиваем период анализа (опционально)
		-- AND lsat_cr.effective_from_dttm >= '2020-01-01'::TIMESTAMP
),
customer_status_by_month AS (
    -- Агрегируем статус клиента по месяцам (если был активен хотя бы раз — считаем активным)
    SELECT 
        customer_hash_key,
        active_month,
        MAX(is_active::INT) AS is_active_flag  -- 1 = активен, 0 = не активен
    FROM monthly_customers
    GROUP BY customer_hash_key, active_month
),
churn_calc AS (
    -- Рассчитываем отток: клиент был активен в месяце T, но не активен в месяце T+1
    SELECT 
        cs1.active_month AS period_start,
        COUNT(DISTINCT cs1.customer_hash_key) AS customers_start,
        COUNT(DISTINCT CASE 
            WHEN cs1.is_active_flag = 1 AND cs2.is_active_flag = 0 
            THEN cs1.customer_hash_key 
        END) AS customers_lost,
        -- Коэффициент оттока в долях единицы (не в процентах!)
        ROUND(
            COUNT(DISTINCT CASE 
                WHEN cs1.is_active_flag = 1 AND cs2.is_active_flag = 0 
                THEN cs1.customer_hash_key 
            END) * 1.0 / NULLIF(COUNT(DISTINCT cs1.customer_hash_key), 0),
            4
        ) AS churn_rate
    FROM customer_status_by_month cs1
    LEFT JOIN customer_status_by_month cs2 
        ON cs1.customer_hash_key = cs2.customer_hash_key
        AND cs2.active_month = cs1.active_month + INTERVAL '1 month'
    WHERE cs1.is_active_flag = 1  -- Учитываем только тех, кто был активен в начале периода
    GROUP BY cs1.active_month
)
SELECT 
    period_start AS report_date,
    customers_start,
    customers_lost,
    churn_rate,
    -- Дополнительно: отток в процентах для отображения
    ROUND(churn_rate * 100, 2) AS churn_rate_percent
FROM churn_calc
ORDER BY period_start;




CREATE OR REPLACE VIEW t4_mart.v_arpu_monthly AS
WITH customer_monthly_revenue AS (
    -- Доход по каждому клиенту в разрезе месяцев
    SELECT 
        lca.customer_hash_key,
        DATE_TRUNC('month', hat.transaction_dttm)::DATE AS revenue_month,
        SUM(ROUND((hat.transaction_amt * 0.01)::NUMERIC, 2)) AS monthly_revenue
    FROM t3_core.HUB_transaction ht
    INNER JOIN t3_core.HSAT_transaction hat 
        ON ht.transaction_hash_key = hat.transaction_hash_key
    INNER JOIN t3_core.LINK_acc_x_trans lat 
        ON ht.transaction_hash_key = lat.transaction_hash_key
    INNER JOIN t3_core.LINK_acc_x_app laa 
        ON lat.account_hash_key = laa.account_hash_key
    INNER JOIN t3_core.LINK_cust_x_app lca 
        ON laa.application_hash_key = lca.application_hash_key
    WHERE 
        hat.transaction_type_nm = 'kopylka'
        AND hat.transaction_amt > 0
        AND hat.transaction_dttm >= hat.effective_from_dttm
        AND hat.transaction_dttm < hat.effective_to_dttm
    GROUP BY lca.customer_hash_key, DATE_TRUNC('month', hat.transaction_dttm)
),
arpu_agg AS (
    -- Агрегируем по месяцам: средний доход на платящего клиента
    SELECT 
        revenue_month AS report_date,
        COUNT(DISTINCT customer_hash_key) AS paying_customers,
        SUM(monthly_revenue) AS total_revenue,
        -- ARPU = общий доход / количество платящих клиентов
        ROUND(
            SUM(monthly_revenue) * 1.0 / NULLIF(COUNT(DISTINCT customer_hash_key), 0),
            2
        ) AS arpu
    FROM customer_monthly_revenue
    GROUP BY revenue_month
)
SELECT 
    report_date,
    paying_customers,
    total_revenue,
    arpu
FROM arpu_agg
ORDER BY report_date;




--drop view t4_mart.v_ltv_churn_based
CREATE OR REPLACE VIEW t4_mart.v_ltv_churn_based AS
SELECT 
    ar.report_date,
    ar.arpu,
    ch.churn_rate,
    ch.churn_rate_percent,
    ar.paying_customers,
    ar.total_revenue,
    ch.customers_start,
    ch.customers_lost,
    -- Основная формула: LTV = ARPU / Churn Rate
    -- Если отток = 0, LTV не определен (бесконечность), поэтому возвращаем NULL
    avg(ch.churn_rate) over (order by ch.report_date rows between unbounded preceding and current row) as avg_churn_rate,
    CASE 
        WHEN avg(ch.churn_rate) over (order by ch.report_date rows between unbounded preceding and current row) > 0 
        THEN ROUND((ar.arpu / 
        	avg(ch.churn_rate) over (order by ch.report_date rows between unbounded preceding and current row)
        )::NUMERIC, 2)
        ELSE NULL 
    END AS ltv_estimate
FROM t4_mart.v_arpu_monthly ar
LEFT JOIN t4_mart.v_churn_rate_monthly ch 
    ON ar.report_date = ch.report_date
WHERE ch.churn_rate IS NOT NULL  -- Исключаем месяцы без данных по оттоку
ORDER BY ar.report_date;




--select 
--	a.*,
--	avg(a.churn_rate) over (order by report_date rows between unbounded preceding and current row)
--from t4_mart.v_churn_rate_monthly a

select revenue_month, sum(monthly_revenue) 
from t4_mart.customer_revenue
group by revenue_month
order by revenue_month