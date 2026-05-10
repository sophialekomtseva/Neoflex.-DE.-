import pandas as pd
import psycopg2
from datetime import datetime

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "postgres",
    "user": "postgres",
    "password": "C4v3m6a3K5S8"  # <-- ВПИШИ СВОЙ ПАРОЛЬ
}

def export_f101():
    print("🚀 Запуск экспорта Формы 101...")
    conn = psycopg2.connect(**DB_CONFIG)
    
    # Записываем лог
    start_time = datetime.now()
    cur = conn.cursor()
    cur.execute("INSERT INTO logs.etl_log (process_name, status, start_time) VALUES (%s, %s, %s)",
                ('EXPORT_F101', 'START', start_time))
    conn.commit()

    try:
        # 1. Читаем данные из основной таблицы
        df = pd.read_sql("SELECT * FROM dm.dm_f101_round_f ORDER BY ledger_account", conn)
        
        # 2. Сохраняем в CSV
        file_path = r"C:\project_etl\data\f101_report.csv"
        df.to_csv(file_path, index=False, sep=';')
        
        # Лог успеха
        cur.execute("UPDATE logs.etl_log SET status='SUCCESS', end_time=%s, rows_loaded=%s WHERE process_name=%s AND start_time=%s",
                    (datetime.now(), len(df), 'EXPORT_F101', start_time))
        conn.commit()
        print(f"✅ Успешно! Экспортировано {len(df)} строк в {file_path}")
        
    except Exception as e:
        conn.rollback()
        print(f"❌ Ошибка: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    export_f101()