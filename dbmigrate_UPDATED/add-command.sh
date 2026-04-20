#!/bin/bash

# add-command.sh - Add commands to the execution queue
#
# Usage: ./add-command.sh "your command here"
# Example: ./add-command.sh "echo 'Hello World'"

DB_FILE="${DB_FILE:-./engine.db}"

# Function to escape SQL strings
sql_escape() {
    local str="$1"
    echo "${str//\'/\'\'}"
}

# Check arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <command>"
    echo ""
    echo "Examples:"
    echo "  $0 'echo Hello World'"
    echo "  $0 'ls -la /tmp'"
    echo "  $0 'sleep 5 && echo Done'"
    exit 1
fi

command="$1"

# Ensure database exists
if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database file not found at $DB_FILE"
    echo "Please run ./start-engine.sh first to initialize the database."
    exit 1
fi

# Escape command for SQL
escaped_command=$(sql_escape "$command")

# Add command to logs table
result=$(sqlite3 "$DB_FILE" <<EOF
INSERT INTO logs (command, status)
VALUES ('$escaped_command', 'pending');

SELECT last_insert_rowid();
EOF
)

echo "✓ Command queued successfully!"
echo "  ID: $result"
echo "  Command: $command"
echo "  Status: pending"
echo ""
echo "Run ./start-engine.sh to process pending commands."
