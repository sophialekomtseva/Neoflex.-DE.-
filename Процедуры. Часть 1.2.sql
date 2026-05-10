CREATE OR REPLACE PROCEDURE ds.fill_account_turnover_f(i_OnDate DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Удаляем данные за эту дату перед расчетом
    DELETE FROM dm.dm_account_turnover_f WHERE on_date = i_OnDate;
    
    -- Вставляем новые данные
    INSERT INTO dm.dm_account_turnover_f (
        on_date, account_rk, credit_amount, credit_amount_rub, debet_amount, debet_amount_rub
    )
    WITH accounts_involved AS (
        SELECT credit_account_rk AS account_rk FROM ds.ft_posting_f WHERE oper_date = i_OnDate
        UNION
        SELECT debet_account_rk AS account_rk FROM ds.ft_posting_f WHERE oper_date = i_OnDate
    ),
    credit_sums AS (
        SELECT credit_account_rk, SUM(credit_amount) AS sum_credit
        FROM ds.ft_posting_f
        WHERE oper_date = i_OnDate
        GROUP BY credit_account_rk
    ),
    debit_sums AS (
        SELECT debet_account_rk, SUM(debet_amount) AS sum_debet
        FROM ds.ft_posting_f
        WHERE oper_date = i_OnDate
        GROUP BY debet_account_rk
    )
    SELECT 
        i_OnDate AS on_date,
        ai.account_rk,
        COALESCE(cs.sum_credit, 0) AS credit_amount,
        COALESCE(cs.sum_credit, 0) * COALESCE(er.reduced_cource, 1) AS credit_amount_rub,
        COALESCE(ds.sum_debet, 0) AS debet_amount,
        COALESCE(ds.sum_debet, 0) * COALESCE(er.reduced_cource, 1) AS debet_amount_rub
    FROM accounts_involved ai
    LEFT JOIN credit_sums cs ON ai.account_rk = cs.credit_account_rk
    LEFT JOIN debit_sums ds ON ai.account_rk = ds.debet_account_rk
    LEFT JOIN ds.md_exchange_rate_d er 
        ON er.data_actual_date = i_OnDate
        AND er.currency_rk = (
            SELECT a.currency_rk FROM ds.md_account_d a
            WHERE a.account_rk = ai.account_rk
            AND i_OnDate BETWEEN a.data_actual_date AND COALESCE(a.data_actual_end_date, '2099-12-31')
        );
    
END;
$$;


-------------------------

CREATE OR REPLACE PROCEDURE ds.fill_account_balance_f(i_OnDate DATE)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Логирование начала
    INSERT INTO logs.etl_log (process_name, status, start_time)
    VALUES ('fill_account_balance_f', 'START', NOW());
    
    -- Удаляем данные за дату расчета (для возможности перезапуска)
    DELETE FROM dm.dm_account_balance_f WHERE on_date = i_OnDate;
    
    -- Рассчитываем остатки
    INSERT INTO dm.dm_account_balance_f (
        on_date,
        account_rk,
        balance_out,
        balance_out_rub
    )
    WITH prev_balance AS (
        -- Остаток за предыдущий день
        SELECT account_rk, balance_out, balance_out_rub
        FROM dm.dm_account_balance_f
        WHERE on_date = i_OnDate - INTERVAL '1 day'
    ),
    turnover AS (
        -- Обороты за текущий день
        SELECT 
            account_rk,
            COALESCE(debet_amount, 0) AS debet_amount,
            COALESCE(debet_amount_rub, 0) AS debet_amount_rub,
            COALESCE(credit_amount, 0) AS credit_amount,
            COALESCE(credit_amount_rub, 0) AS credit_amount_rub
        FROM dm.dm_account_turnover_f
        WHERE on_date = i_OnDate
    ),
    active_accounts AS (
        -- Активные счета
        SELECT a.account_rk
        FROM ds.md_account_d a
        WHERE i_OnDate BETWEEN a.data_actual_date AND COALESCE(a.data_actual_end_date, '9999-12-31')
        AND a.char_type = 'А'
    ),
    passive_accounts AS (
        -- Пассивные счета
        SELECT a.account_rk
        FROM ds.md_account_d a
        WHERE i_OnDate BETWEEN a.data_actual_date AND COALESCE(a.data_actual_end_date, '9999-12-31')
        AND a.char_type = 'П'
    )
    -- Активные счета: prev + debit - credit
    SELECT 
        i_OnDate AS on_date,
        aa.account_rk,
        COALESCE(pb.balance_out, 0) + COALESCE(t.debet_amount, 0) - COALESCE(t.credit_amount, 0) AS balance_out,
        COALESCE(pb.balance_out_rub, 0) + COALESCE(t.debet_amount_rub, 0) - COALESCE(t.credit_amount_rub, 0) AS balance_out_rub
    FROM active_accounts aa
    LEFT JOIN prev_balance pb ON aa.account_rk = pb.account_rk
    LEFT JOIN turnover t ON aa.account_rk = t.account_rk
    
    UNION ALL
    
    -- Пассивные счета: prev - debit + credit
    SELECT 
        i_OnDate AS on_date,
        pa.account_rk,
        COALESCE(pb.balance_out, 0) - COALESCE(t.debet_amount, 0) + COALESCE(t.credit_amount, 0) AS balance_out,
        COALESCE(pb.balance_out_rub, 0) - COALESCE(t.debet_amount_rub, 0) + COALESCE(t.credit_amount_rub, 0) AS balance_out_rub
    FROM passive_accounts pa
    LEFT JOIN prev_balance pb ON pa.account_rk = pb.account_rk
    LEFT JOIN turnover t ON pa.account_rk = t.account_rk;
    
    -- Логирование окончания
    UPDATE logs.etl_log 
    SET status = 'SUCCESS', 
        end_time = NOW(),
        rows_loaded = (SELECT COUNT(*) FROM dm.dm_account_balance_f WHERE on_date = i_OnDate)
    WHERE process_name = 'fill_account_balance_f' 
    AND status = 'START'
    AND start_time = (SELECT MAX(start_time) FROM logs.etl_log WHERE process_name = 'fill_account_balance_f');
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        UPDATE logs.etl_log 
        SET status = 'FAILED', 
            end_time = NOW(),
            error_message = SQLERRM
        WHERE process_name = 'fill_account_balance_f' 
        AND status = 'START'
        AND start_time = (SELECT MAX(start_time) FROM logs.etl_log WHERE process_name = 'fill_account_balance_f');
        COMMIT;
        RAISE;
END;
$$;