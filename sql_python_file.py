import psycopg2


def get_db_connection():
    """Create and return a database connection."""
    return psycopg2.connect(
        dbname="testing",
        user="postgres",
        password="qwerty123",
        host="localhost",
    )


def create_table_if_not_exists():
    """Create the reports table if it doesn't exist."""
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS reports (
            id SERIAL PRIMARY KEY,
            "Category" TEXT NOT NULL,
            "WhatIsIt" TEXT NOT NULL,
            latitude DOUBLE PRECISION NOT NULL,
            longitude DOUBLE PRECISION NOT NULL,
            "timestamp" TIMESTAMP NOT NULL,
            priority INTEGER NOT NULL
        )
        """
    )

    conn.commit()
    cursor.close()
    conn.close()

def save_report(category, whatIsIt, latitude, longitude, timestamp, priority):
    """
    Save report results to the database.

    Args:
        category: Report category string
        whatIsIt: What is in the image
        latitude: Latitude coordinate (float)
        longitude: Longitude coordinate (float)
        timestamp: ISO timestamp string
        priority: Priority 1-10 (int)

    Returns:
        int: The ID of the inserted record
    """
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        cursor.execute(
            """
            INSERT INTO reports ("Category", "WhatIsIt", latitude, longitude, "timestamp", priority)
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING id
            """,
            (category, whatIsIt, latitude, longitude, timestamp, priority),
        )

        record_id = cursor.fetchone()[0]
        conn.commit()
        return record_id
    except Exception as e:
        conn.rollback()
        raise Exception(f"Error saving to database: {str(e)}")
    finally:
        cursor.close()
        conn.close()