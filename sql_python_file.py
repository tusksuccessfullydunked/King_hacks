import psycopg2
from psycopg2.extras import execute_values
import base64

def get_db_connection():
    """Create and return a database connection."""
    return psycopg2.connect(
        dbname="testing",
        user="postgres",
        password="qwerty123",
        host="localhost"
    )

def create_table_if_not_exists():
    """Create the images table if it doesn't exist."""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS analyzed_images (
            id SERIAL PRIMARY KEY,
            image_data BYTEA NOT NULL,
            location VARCHAR(255),
            image_description VARCHAR(255),
            confidence_score FLOAT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    conn.commit()
    cursor.close()
    conn.close()

def save_image_analysis(image_data, location, description, confidence_score):
    """
    Save image analysis results to the database.
    
    Args:
        image_data: Binary image data (bytes)
        location: Location string from frontend
        description: What the image is (from AI analysis)
        confidence_score: Confidence score from AI
        
    Returns:
        int: The ID of the inserted record
    """
    conn = get_db_connection()
    cursor = conn.cursor()
    
    try:
        cursor.execute("""
            INSERT INTO analyzed_images (image_data, location, image_description, confidence_score)
            VALUES (%s, %s, %s, %s)
            RETURNING id
        """, (image_data, location, description, confidence_score))
        
        record_id = cursor.fetchone()[0]
        conn.commit()
        return record_id
    except Exception as e:
        conn.rollback()
        raise Exception(f"Error saving to database: {str(e)}")
    finally:
        cursor.close()
        conn.close()