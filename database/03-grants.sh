#!/bin/bash
# Re-assert the app user's privileges after schema.sql has dropped and recreated the database.
# Sourced by the mysql image entrypoint, which provides docker_process_sql.
docker_process_sql --database=mysql <<-EOSQL
	GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
	FLUSH PRIVILEGES;
EOSQL
