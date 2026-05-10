CREATE TABLE dm.dm_f101_round_f (
    from_date DATE NOT NULL,
    to_date DATE NOT NULL,
    chapter CHAR(1),
    ledger_account CHAR(5) NOT NULL,
    characteristic CHAR(1),
    balance_in_rub NUMERIC(23,8),
    balance_in_val NUMERIC(23,8),
    balance_in_total NUMERIC(23,8),
    turn_deb_rub NUMERIC(23,8),
    turn_deb_val NUMERIC(23,8),
    turn_deb_total NUMERIC(23,8),
    turn_cre_rub NUMERIC(23,8),
    turn_cre_val NUMERIC(23,8),
    turn_cre_total NUMERIC(23,8),
    balance_out_rub NUMERIC(23,8),
    balance_out_val NUMERIC(23,8),
    balance_out_total NUMERIC(23,8),
    PRIMARY KEY (from_date, ledger_account, characteristic)
);

----------------------------------------------------

CREATE OR REPLACE PROCEDURE dm.fill_f101_round_f(i_OnDate DATE)
LANGUAGE plpgsql
AS $$
DECLARE
    v_from_date DATE;
    v_to_date DATE;
BEGIN
    -- Логирование начала
    INSERT INTO logs.etl_log (process_name, status, start_time)
    VALUES ('fill_f101_round_f', 'START', NOW());
    
    -- Определяем период отчета
    -- i_OnDate - это первый день месяца после отчетного периода
    -- Например, для отчета за январь передаем 01.02.2018
    v_to_date := i_OnDate - INTERVAL '1 day';  -- Последний день отчетного периода (31.01.2018)
    v_from_date := DATE_TRUNC('month', v_to_date);  -- Первый день отчетного периода (01.01.2018)
    
    -- Удаляем данные за период отчета (для возможности перезапуска)
    DELETE FROM dm.dm_f101_round_f 
    WHERE from_date = v_from_date 
    AND to_date = v_to_date;
    
    -- Вставляем рассчитанные данные
    INSERT INTO dm.dm_f101_round_f (
        from_date,
        to_date,
        chapter,
        ledger_account,
        characteristic,
        balance_in_rub,
        balance_in_val,
        balance_in_total,
        turn_deb_rub,
        turn_deb_val,
        turn_deb_total,
        turn_cre_rub,
        turn_cre_val,
        turn_cre_total,
        balance_out_rub,
        balance_out_val,
        balance_out_total
    )
    WITH report_period AS (
        -- Определяем границы отчетного периода
        SELECT 
            v_from_date AS from_date,
            v_to_date AS to_date
    ),
    accounts_with_info AS (
        -- Получаем все счета с информацией о балансовом счете и валюте
        SELECT DISTINCT
            a.account_rk,
            a.account_number,
            LEFT(a.account_number, 5) AS ledger_account,  -- Первые 5 символов - счет 2-го порядка
            a.char_type AS characteristic,
            a.currency_rk,
            a.currency_code,
            las.chapter,
            las.ledger_account AS ledger_acc_full
        FROM ds.md_account_d a
        LEFT JOIN ds.md_ledger_account_s las 
            ON LEFT(a.account_number, 5) = CAST(las.ledger_account AS VARCHAR(5))
            AND rp.from_date BETWEEN las.start_date AND COALESCE(las.end_date, '9999-12-31')
        CROSS JOIN report_period rp
        WHERE rp.from_date BETWEEN a.data_actual_date AND COALESCE(a.data_actual_end_date, '9999-12-31')
    ),
    balance_in AS (
        -- Входящие остатки (на день перед началом отчетного периода)
        SELECT 
            awi.ledger_account,
            awi.characteristic,
            awi.chapter,
            -- Рублевые счета (810 или 643)
            SUM(CASE 
                WHEN awi.currency_code IN ('810', '643') THEN b.balance_out_rub 
                ELSE 0 
            END) AS balance_in_rub,
            -- Валютные счета
            SUM(CASE 
                WHEN awi.currency_code NOT IN ('810', '643') THEN b.balance_out_rub 
                ELSE 0 
            END) AS balance_in_val,
            -- Всего
            SUM(b.balance_out_rub) AS balance_in_total
        FROM accounts_with_info awi
        LEFT JOIN dm.dm_account_balance_f b 
            ON awi.account_rk = b.account_rk
            AND b.on_date = (SELECT from_date - INTERVAL '1 day' FROM report_period)
        GROUP BY awi.ledger_account, awi.characteristic, awi.chapter
    ),
    turnover_deb AS (
        -- Дебетовые обороты за период
        SELECT 
            awi.ledger_account,
            awi.characteristic,
            awi.chapter,
            -- Рублевые счета
            SUM(CASE 
                WHEN awi.currency_code IN ('810', '643') THEN t.debet_amount_rub 
                ELSE 0 
            END) AS turn_deb_rub,
            -- Валютные счета
            SUM(CASE 
                WHEN awi.currency_code NOT IN ('810', '643') THEN t.debet_amount_rub 
                ELSE 0 
            END) AS turn_deb_val,
            -- Всего
            SUM(t.debet_amount_rub) AS turn_deb_total
        FROM accounts_with_info awi
        LEFT JOIN dm.dm_account_turnover_f t 
            ON awi.account_rk = t.account_rk
            AND t.on_date BETWEEN (SELECT from_date FROM report_period) 
                               AND (SELECT to_date FROM report_period)
        GROUP BY awi.ledger_account, awi.characteristic, awi.chapter
    ),
    turnover_cre AS (
        -- Кредитовые обороты за период
        SELECT 
            awi.ledger_account,
            awi.characteristic,
            awi.chapter,
            -- Рублевые счета
            SUM(CASE 
                WHEN awi.currency_code IN ('810', '643') THEN t.credit_amount_rub 
                ELSE 0 
            END) AS turn_cre_rub,
            -- Валютные счета
            SUM(CASE 
                WHEN awi.currency_code NOT IN ('810', '643') THEN t.credit_amount_rub 
                ELSE 0 
            END) AS turn_cre_val,
            -- Всего
            SUM(t.credit_amount_rub) AS turn_cre_total
        FROM accounts_with_info awi
        LEFT JOIN dm.dm_account_turnover_f t 
            ON awi.account_rk = t.account_rk
            AND t.on_date BETWEEN (SELECT from_date FROM report_period) 
                               AND (SELECT to_date FROM report_period)
        GROUP BY awi.ledger_account, awi.characteristic, awi.chapter
    ),
    balance_out AS (
        -- Исходящие остатки (на последний день отчетного периода)
        SELECT 
            awi.ledger_account,
            awi.characteristic,
            awi.chapter,
            -- Рублевые счета
            SUM(CASE 
                WHEN awi.currency_code IN ('810', '643') THEN b.balance_out_rub 
                ELSE 0 
            END) AS balance_out_rub,
            -- Валютные счета
            SUM(CASE 
                WHEN awi.currency_code NOT IN ('810', '643') THEN b.balance_out_rub 
                ELSE 0 
            END) AS balance_out_val,
            -- Всего
            SUM(b.balance_out_rub) AS balance_out_total
        FROM accounts_with_info awi
        LEFT JOIN dm.dm_account_balance_f b 
            ON awi.account_rk = b.account_rk
            AND b.on_date = (SELECT to_date FROM report_period)
        GROUP BY awi.ledger_account, awi.characteristic, awi.chapter
    )
    SELECT 
        rp.from_date,
        rp.to_date,
        COALESCE(bi.chapter, td.chapter, tc.chapter, bo.chapter) AS chapter,
        COALESCE(bi.ledger_account, td.ledger_account, tc.ledger_account, bo.ledger_account) AS ledger_account,
        COALESCE(bi.characteristic, td.characteristic, tc.characteristic, bo.characteristic) AS characteristic,
        COALESCE(bi.balance_in_rub, 0) AS balance_in_rub,
        COALESCE(bi.balance_in_val, 0) AS balance_in_val,
        COALESCE(bi.balance_in_total, 0) AS balance_in_total,
        COALESCE(td.turn_deb_rub, 0) AS turn_deb_rub,
        COALESCE(td.turn_deb_val, 0) AS turn_deb_val,
        COALESCE(td.turn_deb_total, 0) AS turn_deb_total,
        COALESCE(tc.turn_cre_rub, 0) AS turn_cre_rub,
        COALESCE(tc.turn_cre_val, 0) AS turn_cre_val,
        COALESCE(tc.turn_cre_total, 0) AS turn_cre_total,
        COALESCE(bo.balance_out_rub, 0) AS balance_out_rub,
        COALESCE(bo.balance_out_val, 0) AS balance_out_val,
        COALESCE(bo.balance_out_total, 0) AS balance_out_total
    FROM report_period rp
    FULL JOIN balance_in bi ON 1=1
    FULL JOIN turnover_deb td ON bi.ledger_account = td.ledger_account AND bi.characteristic = td.characteristic
    FULL JOIN turnover_cre tc ON COALESCE(bi.ledger_account, td.ledger_account) = tc.ledger_account 
                                  AND COALESCE(bi.characteristic, td.characteristic) = tc.characteristic
    FULL JOIN balance_out bo ON COALESCE(bi.ledger_account, td.ledger_account, tc.ledger_account) = bo.ledger_account 
                                 AND COALESCE(bi.characteristic, td.characteristic, tc.characteristic) = bo.characteristic
    WHERE COALESCE(bi.ledger_account, td.ledger_account, tc.ledger_account, bo.ledger_account) IS NOT NULL;
    
    -- Логирование окончания
    UPDATE logs.etl_log 
    SET status = 'SUCCESS', 
        end_time = NOW(),
        rows_loaded = (SELECT COUNT(*) FROM dm.dm_f101_round_f 
                       WHERE from_date = v_from_date AND to_date = v_to_date)
    WHERE process_name = 'fill_f101_round_f' 
    AND status = 'START'
    AND start_time = (SELECT MAX(start_time) FROM logs.etl_log WHERE process_name = 'fill_f101_round_f');
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        UPDATE logs.etl_log 
        SET status = 'FAILED', 
            end_time = NOW(),
            error_message = SQLERRM
        WHERE process_name = 'fill_f101_round_f' 
        AND status = 'START'
        AND start_time = (SELECT MAX(start_time) FROM logs.etl_log WHERE process_name = 'fill_f101_round_f');
        COMMIT;
        RAISE;
END;
$$;