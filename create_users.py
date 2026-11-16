import mysql.connector
import bcrypt
import os
from dotenv import load_dotenv

# ---
# This script securely populates the 'Users' table.
# It reads the plain-text passwords, hashes them using the
# exact same 'bcrypt' library your Flask app uses,
# and then inserts them into the database.
#
# This 100% guarantees the hashes will match.
# ---

# Load database config from .env file in the same directory
load_dotenv()

db_config = {
    'host': os.getenv('DB_HOST'),
    'user': os.getenv('DB_USER'),
    'password': os.getenv('DB_PASSWORD'),
    'database': os.getenv('DB_NAME')
}

# The users we want to create
users_to_add = [
    # (username,  plain_text_password, role)
    ('admin', 'admin', 'admin'),
    ('warehouse_user', 'warehouse', 'warehouse')
]

def hash_password(password):
    """Hashes a password using bcrypt."""
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')

def create_users():
    try:
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor()
        
        # Clear the table first to avoid "Duplicate entry" errors
        cursor.execute("TRUNCATE TABLE Users")
        print("Emptied 'Users' table.")

        # Loop and insert each user
        for username, plain_pass, role in users_to_add:
            # Hash the password
            hashed_password = hash_password(plain_pass)
            
            # Insert the user
            sql = "INSERT INTO Users (Username, PasswordHash, Role) VALUES (%s, %s, %s)"
            val = (username, hashed_password, role)
            cursor.execute(sql, val)
        
        conn.commit()
        
        print(f"Successfully created {cursor.rowcount} users.")
        
        cursor.close()
        conn.close()

    except mysql.connector.Error as err:
        print(f"Error: {err}")
    except Exception as e:
        print(f"An unknown error occurred: {e}")

if __name__ == "__main__":
    create_users()





