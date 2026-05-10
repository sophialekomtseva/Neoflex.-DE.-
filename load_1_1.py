import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
import time
from datetime import datetime
import os

# === НАСТРОЙКИ ===
DB_PASSWORD = "C4v3m6a3K5S8"  # ← ВПИШИ СВОЙ ПАРОЛЬ
CSV_FOLDER_PATH = r"C:\project_etl\csv"  # ← ПУТЬ К ТВОИМ ФАЙЛАМ

TABLES_MAP = {
    "ft_balance_f.csv":        {"table": "ft_balance_f",        "pk": ["on_date", "account_rk"]},
    "ft_posting_f.csv":        {"table": "ft_posting_f",        "pk": []},
    "md_account_d.csv":        {"table": "md_account_d",        "pk": ["data_actual_date", "account_rk"]},
    "md_currency_d.csv":       {"table": "md_currency_d",       "pk": ["currency_rk", "data_actual_date"]},
    "md_exchange_rate_d.csv":  {"table": "md_exchange_rate_d",  "pk": ["data_actual_date", "currency_rk"]},
    "md_ledger_account_s.csv": {"table": "md_ledger_account_s", "pk": ["ledger_account", "start_date"]}
}

def read_csv_smart(file_path):
    """Читает CSV, пробуя разные кодировки"""
    encodings = ['utf-8', 'cp1251', 'latin1']
    for enc in encodings:
        try:
            df = pd.read_csv(file_path, sep=";", encoding=enc, parse_dates=True, dayfirst=True, date_format="mixed")
            return df
        except UnicodeDecodeError:
            continue
    raise Exception(f"Не удалось прочитать {file_path}")

def clean_data(df):
    """Чистит данные: убирает пробелы и форматирует даты"""
    # 1. Убираем пробелы у всех текстовых колонок
    for col in df.select_dtypes(include=['object']).columns:
        df[col] = df[col].astype(str).str.strip()
        
    # 2. Приводим все даты к формату YYYY-MM-DD
    for col in df.columns:
        if pd.api.types.is_datetime64_any_dtype(df[col]):
            df[col] = df[col].dt.strftime('%Y-%m-%d')
    
    return df

def run_etl():
    print("🚀 Запуск ETL процесса...")
    try:
        conn = psycopg2.connect(
            host="localhost", dbname="postgres", user="postgres", password=DB_PASSWORD
        )
        cur = conn.cursor()
    except Exception as e:
        print(f"❌ Ошибка подключения: {e}")
        return

    for filename, config in TABLES_MAP.items():
        table_name = config["table"]
        pk_cols = config["pk"]
        file_path = os.path.join(CSV_FOLDER_PATH, filename)
        
        if not os.path.exists(file_path):
            print(f"⚠️ Файл {filename} не найден.")
            continue
            
        print(f"\n📂 Обработка: {filename} -> ds.{table_name}")
        
        # 1. Лог СТАРТА
        start_time = datetime.now()
        cur.execute("INSERT INTO logs.etl_log (process_name, status, start_time) VALUES (%s, 'START', %s)", 
                    (f"LOAD_{table_name}", start_time))
        conn.commit()

        # 2. Пауза 5 секунд
        time.sleep(5)

        try:
            # 3. Чтение CSV
            df = read_csv_smart(file_path)
            df.columns = [c.strip().lower() for c in df.columns]
            
            # 4. ОЧИСТКА ДАННЫХ
            df = clean_data(df)

            # 5. Удаление старых данных
            if pk_cols:
                # Сначала получаем уникальные комбинации ключей
                keys_df = df[pk_cols].drop_duplicates()
                
                # 🔧 ВАЖНО: Приводим типы ключей к правильным для каждой таблицы
                if table_name == 'ft_balance_f':
                    if 'account_rk' in keys_df.columns:
                        keys_df['account_rk'] = pd.to_numeric(keys_df['account_rk'], errors='coerce')
                    if 'currency_rk' in keys_df.columns:
                        keys_df['currency_rk'] = pd.to_numeric(keys_df['currency_rk'], errors='coerce')
                elif table_name == 'md_account_d':
                    if 'account_rk' in keys_df.columns:
                        keys_df['account_rk'] = pd.to_numeric(keys_df['account_rk'], errors='coerce')
                elif table_name == 'md_currency_d':
                    if 'currency_rk' in keys_df.columns:
                        keys_df['currency_rk'] = pd.to_numeric(keys_df['currency_rk'], errors='coerce')
                elif table_name == 'md_exchange_rate_d':
                    if 'currency_rk' in keys_df.columns:
                        keys_df['currency_rk'] = pd.to_numeric(keys_df['currency_rk'], errors='coerce')
                
                # Удаляем построчно
                for idx, row in keys_df.iterrows():
                    where_conditions = []
                    params = []
                    for col in pk_cols:
                        where_conditions.append(f"{col} = %s")
                        val = row[col]
                        # Если значение NaN, пропускаем эту строку
                        if pd.isna(val):
                            continue
                        params.append(val)
                    
                    if params:  # Если есть параметры для удаления
                        where_sql = " AND ".join(where_conditions)
                        delete_sql = f"DELETE FROM ds.{table_name} WHERE {where_sql}"
                        cur.execute(delete_sql, params)
            else:
                # Для таблиц без PK - полная очистка
                cur.execute(f"TRUNCATE TABLE ds.{table_name}")
            
            conn.commit()

            # 6. Вставка данных
            # Заменяем NaN на None для PostgreSQL
            df = df.where(pd.notnull(df), None)
            
            cols = ", ".join(df.columns)
            values = [tuple(x) for x in df.to_numpy()]
            insert_sql = f"INSERT INTO ds.{table_name} ({cols}) VALUES %s"
            execute_values(cur, insert_sql, values)
            
            conn.commit()
            
            # 7. Лог УСПЕХА
            end_time = datetime.now()
            cur.execute("""UPDATE logs.etl_log 
                           SET status='SUCCESS', end_time=%s, rows_loaded=%s 
                           WHERE process_name=%s AND start_time=%s""", 
                        (end_time, len(df), f"LOAD_{table_name}", start_time))
            conn.commit()
            
            print(f"✅ Успешно! Загружено {len(df)} строк.")

        except Exception as e:
            conn.rollback()
            print(f"❌ Ошибка с {filename}: {e}")
            import traceback
            traceback.print_exc()
            cur.execute("UPDATE logs.etl_log SET status='FAILED', error_message=%s WHERE process_name=%s AND start_time=%s", 
                        (str(e), f"LOAD_{table_name}", start_time))
            conn.commit()

    cur.close()
    conn.close()
    print("\n🎉 Всё готово!")

if __name__ == "__main__":
    run_etl()
