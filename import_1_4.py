import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from datetime import datetime

# Настройки подключения
DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "postgres",
    "user": "postgres",
    "password": "C4v3m6a3K5S8"  # ← ВПИШИ СВОЙ ПАРОЛЬ
}

def import_f101():
    """Импорт данных из CSV в таблицу dm_f101_round_f_v2"""
    print("🚀 Запуск импорта Формы 101...")
    
    file_path = r"C:\project_etl\data\f101_report.csv"  # Путь к CSV файлу
    
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        
        # Чтение CSV
        df = pd.read_csv(file_path, sep=';')  # Попробуй ';' если ',' не работает
        print(f"📄 Прочитано {len(df)} строк из CSV")
        print(f"📋 Колонки в файле: {list(df.columns)}")
        
        # Очистка таблицы перед загрузкой
        cur.execute("TRUNCATE TABLE dm.dm_f101_round_f_v2")
        conn.commit()
        
        # Подготовка данных для вставки
        # Заменяем NaN на None для PostgreSQL
        df = df.where(pd.notnull(df), None)
        
        # Вставка данных через execute_values
        cols = ", ".join(df.columns)
        values = [tuple(x) for x in df.to_numpy()]
        
        insert_sql = f"INSERT INTO dm.dm_f101_round_f_v2 ({cols}) VALUES %s"
        execute_values(cur, insert_sql, values)
        
        conn.commit()
        cur.close()
        conn.close()
        
        print(f"✅ Успешно! Импортировано {len(df)} строк в dm.dm_f101_round_f_v2")
        
    except Exception as e:
        print(f"❌ Ошибка импорта: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    import_f101()