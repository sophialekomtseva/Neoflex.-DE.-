-- 1. Схемы
CREATE SCHEMA IF NOT EXISTS ds;
CREATE SCHEMA IF NOT EXISTS logs;

-- 2. Таблица логов
CREATE TABLE logs.etl_log (
    log_id SERIAL PRIMARY KEY,
    process_name TEXT NOT NULL,
    status TEXT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    rows_loaded INT DEFAULT 0,
    error_message TEXT
);


CREATE TABLE ds.ft_balance_f (
    on_date DATE NOT NULL,
    account_rk BIGINT NOT NULL,
    currency_rk BIGINT,
    balance_out DOUBLE PRECISION,
    PRIMARY KEY (on_date, account_rk)
);

CREATE TABLE ds.ft_posting_f (
    oper_date DATE NOT NULL,
    credit_account_rk BIGINT NOT NULL,
    debet_account_rk BIGINT NOT NULL,
    credit_amount DOUBLE PRECISION,
    debet_amount DOUBLE PRECISION
); -- Нет PK, будем очищать полностью перед загрузкой

CREATE TABLE ds.md_account_d (
    data_actual_date DATE NOT NULL,
    data_actual_end_date DATE NOT NULL,
    account_rk BIGINT NOT NULL,
    account_number VARCHAR(20) NOT NULL,
    char_type VARCHAR(1) NOT NULL,
    currency_rk BIGINT NOT NULL,
    currency_code VARCHAR(3) NOT NULL,
    PRIMARY KEY (data_actual_date, account_rk)
);

CREATE TABLE ds.md_currency_d (
    currency_rk BIGINT NOT NULL,
    data_actual_date DATE NOT NULL,
    data_actual_end_date DATE,
    currency_code VARCHAR(3),
    code_iso_char VARCHAR(3),
    PRIMARY KEY (currency_rk, data_actual_date)
);

CREATE TABLE ds.md_exchange_rate_d (
    data_actual_date DATE NOT NULL,
    data_actual_end_date DATE,
    currency_rk BIGINT NOT NULL,
    reduced_cource DOUBLE PRECISION, -- оставлено как в ТЗ
    code_iso_num VARCHAR(3),
    PRIMARY KEY (data_actual_date, currency_rk)
);

CREATE TABLE ds.md_ledger_account_s (
    chapter CHAR(1), chapter_name VARCHAR(16),
    section_number INT, section_name VARCHAR(22), subsection_name VARCHAR(21),
    ledger1_account INT, ledger1_account_name VARCHAR(47),
    ledger_account BIGINT NOT NULL, ledger_account_name VARCHAR(153),
    characteristic CHAR(1), is_resident INT, is_reserve INT, is_reserved INT,
    is_loan INT, is_reserved_assets INT, is_overdue INT, is_interest INT,
    pair_account VARCHAR(5),
    start_date DATE NOT NULL, end_date DATE,
    is_rub_only INT, min_term INT, min_term_measure CHAR(1),
    max_term INT, max_term_measure CHAR(1),
    ledger_acc_full_name_translit VARCHAR(100),
    is_revaluation INT, is_correct INT,
    PRIMARY KEY (ledger_account, start_date)
);