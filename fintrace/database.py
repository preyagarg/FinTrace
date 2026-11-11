# database.py
# This file creates and manages the connection to MySQL database
# Think of this as the bridge between Flask and MySQL Workbench

import os
from flask_mysqldb import MySQL
from dotenv import load_dotenv

# Load the .env file so we can read MYSQL_PASSWORD etc.
load_dotenv()

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

    # This line actually connects Flask to MySQL
    mysql.init_app(app)