import psycopg2
from datetime import datetime, timedelta

# Настройки подключения
DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "postgres",
    "user": "postgres",
    "password": "C4v3m6a3K5S8"  # ← ВПИШИТЕ ПАРОЛЬ
}

def log_process(conn, process_name, status, start_time, end_time=None, rows=0, error=None):
    """Запись лога в таблицу logs.etl_log"""
    cur = conn.cursor()
    try:
        if end_time is None:
            cur.execute("""
                INSERT INTO logs.etl_log (process_name, status, start_time)
                VALUES (%s, %s, %s)
            """, (process_name, status, start_time))
        else:
            cur.execute("""
                UPDATE logs.etl_log 
                SET status = %s, end_time = %s, rows_loaded = %s, error_message = %s
                WHERE process_name = %s AND start_time = %s AND status = 'START'
            """, (status, end_time, rows, error, process_name, start_time))
        
        conn.commit()
    except Exception as e:
        print(f"Ошибка логирования: {e}")
        conn.rollback()
    finally:
        cur.close()

def calculate_january_2018():
    """Расчет витрин за каждый день января 2018"""
    print("🚀 Запуск расчета витрин за январь 2018...")
    
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    current_date = datetime(2018, 1, 9)  # Начинаем с 9 января
    end_date = datetime(2018, 1, 31)
    
    while current_date <= end_date:
        date_str = current_date.strftime('%Y-%m-%d')
        print(f"\n📅 Обработка даты: {date_str}")
        
        try:
            # 1. Расчет оборотов
            start_time = datetime.now()
            log_process(conn, f'TURNOVER_{date_str}', 'START', start_time)
            
            cur.execute("CALL ds.fill_account_turnover_f(%s)", (date_str,))
            conn.commit()
            
            cur.execute("SELECT COUNT(*) FROM dm.dm_account_turnover_f WHERE on_date = %s", (date_str,))
            rows = cur.fetchone()[0]
            log_process(conn, f'TURNOVER_{date_str}', 'SUCCESS', start_time, datetime.now(), rows)
            
            # 2. Расчет остатков
            start_time = datetime.now()
            log_process(conn, f'BALANCE_{date_str}', 'START', start_time)
            
            cur.execute("CALL ds.fill_account_balance_f(%s)", (date_str,))
            conn.commit()
            
            cur.execute("SELECT COUNT(*) FROM dm.dm_account_balance_f WHERE on_date = %s", (date_str,))
            rows = cur.fetchone()[0]
            log_process(conn, f'BALANCE_{date_str}', 'SUCCESS', start_time, datetime.now(), rows)
            
            print(f"✅ Успешно! {date_str} обработана.")
            
        except Exception as e:
            conn.rollback()
            print(f"❌ Ошибка на дате {date_str}: {e}")
        
        current_date += timedelta(days=1)
    
    cur.close()
    conn.close()
    print("\n🎉 Расчет за январь 2018 завершен!")

if __name__ == "__main__":
    calculate_january_2018()