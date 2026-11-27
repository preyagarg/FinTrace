# database.py
# This file creates and manages the connection to MySQL database
# Think of this as the bridge between Flask and MySQL Workbench

import os
import time
import logging
import MySQLdb
from flask_mysqldb import MySQL
from dotenv import load_dotenv

# Load the .env file so we can read MYSQL_PASSWORD etc.
load_dotenv()

log = logging.getLogger(__name__)

# This object will hold our MySQL connection
# We pass it into app.py to initialize it
mysql = MySQL()

def init_db(app):
    """
    This function takes the Flask app and attaches MySQL to it.
    Call this once when the app starts.
    """

    # Tell Flask where the database is and how to connect
    app.config['MYSQL_HOST']     = os.getenv('MYSQL_HOST',     'localhost')
    app.config['MYSQL_USER']     = os.getenv('MYSQL_USER',     'root')
    app.config['MYSQL_PASSWORD'] = os.getenv('MYSQL_PASSWORD', '')
    app.config['MYSQL_DB']       = os.getenv('MYSQL_DB',       'fintrace')
    app.config['MYSQL_PORT']     = int(os.getenv('MYSQL_PORT', 3306))
    app.config['MYSQL_CHARSET']  = 'utf8mb4'

    # Wait for MySQL to accept connections (useful when started via docker compose)
    retries = int(os.getenv('DB_CONNECT_RETRIES', 30))
    for attempt in range(1, retries + 1):
        try:
            log.warning('Connecting to MySQL (attempt %d/%d)...', attempt, retries)
            conn = MySQLdb.connect(
                host=app.config['MYSQL_HOST'],
                user=app.config['MYSQL_USER'],
                passwd=app.config['MYSQL_PASSWORD'],
                db=app.config['MYSQL_DB'],
                port=app.config['MYSQL_PORT'],
            )
            conn.close()
            log.warning('MySQL connection OK.')
            break
        except MySQLdb.Error as e:
            log.warning('MySQL not ready: %s', e)
            if attempt == retries:
                raise
            time.sleep(2)

    # This line actually connects Flask to MySQL
    mysql.init_app(app)