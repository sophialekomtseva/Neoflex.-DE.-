CREATE TABLE dm.dm_f101_round_f_v2 (
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

---------------------------------------------------------

