#!/bin/bash

# start-engine.sh - Script Execution Engine
# Processes pending commands from logs table
# 
# Usage: ./start-engine.sh [options]
# Options:
#   --watch     Run in continuous mode (processes every 30 seconds)
#   --once      Run once and exit (default)
#   --stats     Show statistics only

set -euo pipefail

# Configuration
DB_FILE="${DB_FILE:-./engine.db}"
LOG_FILE="${LOG_FILE:-./engine.log}"
LOCK_FILE="${LOCK_FILE:-/tmp/script-engine.lock}"
WATCH_MODE=false
STATS_ONLY=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --watch)
            WATCH_MODE=true
            shift
            ;;
        --once)
            WATCH_MODE=false
            shift
            ;;
        --stats)
            STATS_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--watch|--once|--stats]"
            exit 1
            ;;
    esac
done

# Function to log messages
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"
    
    # Write to log file
    echo "$log_entry" >> "$LOG_FILE"
    
    # Print to console with colors
    case "$level" in
        ERROR)
            echo -e "${RED}$log_entry${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}$log_entry${NC}"
            ;;
        WARN)
            echo -e "${YELLOW}$log_entry${NC}"
            ;;
        INFO)
            echo -e "${BLUE}$log_entry${NC}"
            ;;
        *)
            echo "$log_entry"
            ;;
    esac
}

# Function to initialize database
init_database() {
    if [ -f "$DB_FILE" ]; then
        log_message "INFO" "Database already exists: $DB_FILE"
    else
        log_message "INFO" "Creating new database: $DB_FILE"
    fi
    
   sqlite3 "$DB_FILE" <<'EOF'
-- Create logs table if it doesn't exist
CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    command TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    CHECK (status IN ('pending', 'done', 'error'))
);

-- Create execution_log table
CREATE TABLE IF NOT EXISTS execution_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    log_id INTEGER NOT NULL,
    status TEXT NOT NULL,
    output TEXT,
    error_output TEXT,
    exit_code INTEGER,
    executed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (log_id) REFERENCES logs(id)
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_logs_status ON logs(status);
CREATE INDEX IF NOT EXISTS idx_logs_created ON logs(created_at);
CREATE INDEX IF NOT EXISTS idx_execution_log_log_id ON execution_log(log_id);
EOF
    
    log_message "INFO" "Database initialized successfully"
}

# Function to acquire lock
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
        if [ "$pid" != "unknown" ] && kill -0 "$pid" 2>/dev/null; then
            log_message "WARN" "Another instance is running (PID: $pid). Exiting."
            exit 1
        else
            log_message "WARN" "Stale lock file found. Removing..."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    log_message "INFO" "Lock acquired (PID: $$)"
}

# Function to release lock
release_lock() {
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
        log_message "INFO" "Lock released"
    fi
}

# Function to safely escape SQL strings
sql_escape() {
    local str="$1"
    # Replace single quotes with two single quotes for SQL escaping
    echo "${str//\'/\'\'}"
}

# Function to execute command
execute_command() {
    local log_id="$1"
    local command="$2"
    
    log_message "INFO" "Executing command (ID: $log_id): $command"
    
    # Create temporary files for output
    local stdout_file=$(mktemp)
    local stderr_file=$(mktemp)
    local exit_code=0
    
    # Execute command and capture output
    set +e
    bash -c "$command" > "$stdout_file" 2> "$stderr_file"
    exit_code=$?
    set -e
    
    # Determine status
    local status
    if [ $exit_code -eq 0 ]; then
        status="done"
        log_message "SUCCESS" "Command completed successfully (ID: $log_id, Exit Code: $exit_code)"
    else
        status="error"
        log_message "ERROR" "Command failed (ID: $log_id, Exit Code: $exit_code)"
    fi
    
    # Read output
    local stdout_content=$(cat "$stdout_file")
    local stderr_content=$(cat "$stderr_file")
    
    # Escape for SQL
    local stdout_escaped=$(sql_escape "$stdout_content")
    local stderr_escaped=$(sql_escape "$stderr_content")
    
    # Update logs table
    sqlite3 "$DB_FILE" <<EOF
UPDATE logs 
SET status = '$status', 
    updated_at = CURRENT_TIMESTAMP 
WHERE id = $log_id;
EOF
    
    # Insert into execution_log
    sqlite3 "$DB_FILE" <<EOF
INSERT INTO execution_log (log_id, status, output, error_output, exit_code)
VALUES (
    $log_id,
    '$status',
    '$stdout_escaped',
    '$stderr_escaped',
    $exit_code
);
EOF
    
    # Log output to file if present
    if [ -n "$stdout_content" ]; then
        log_message "INFO" "Output (ID: $log_id):"
        echo "$stdout_content" | while IFS= read -r line; do
            log_message "INFO" "  $line"
        done
    fi
    
    if [ -n "$stderr_content" ]; then
        log_message "WARN" "Error Output (ID: $log_id):"
        echo "$stderr_content" | while IFS= read -r line; do
            log_message "WARN" "  $line"
        done
    fi
    
    # Clean up temporary files
    rm -f "$stdout_file" "$stderr_file"
    
    return $exit_code
}

# Function to process pending commands
process_pending() {
    log_message "INFO" "Checking for pending commands..."
    
    # Get count of pending commands
    local pending_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM logs WHERE status = 'pending';")
    
    if [ "$pending_count" -eq 0 ]; then
        log_message "INFO" "No pending commands found"
        return 0
    fi
    
    log_message "INFO" "Found $pending_count pending command(s)"
    
    local total=0
    local success=0
    local failed=0
    
    # Process each pending command
    sqlite3 "$DB_FILE" "SELECT id, command FROM logs WHERE status = 'pending' ORDER BY created_at ASC;" | while IFS='|' read -r id command; do
        ((total++)) || true
        
        if execute_command "$id" "$command"; then
            ((success++)) || true
        else
            ((failed++)) || true
        fi
        
        echo ""
    done
    
    log_message "INFO" "Batch complete: Total=$pending_count, Success=$success, Failed=$failed"
}

# Function to show statistics
show_stats() {
    echo ""
    echo -e "${GREEN}=== Execution Statistics ===${NC}"
    echo ""
    
    sqlite3 "$DB_FILE" <<'EOF'
.mode column
.headers on
.width 15 10

SELECT 
    status,
    COUNT(*) as count
FROM logs
GROUP BY status
ORDER BY status;
EOF
    
    echo ""
    echo -e "${GREEN}=== Recent Executions (Last 10) ===${NC}"
    echo ""
    
    sqlite3 "$DB_FILE" <<'EOF'
.mode column
.headers on
.width 5 45 10 10 20

SELECT 
    l.id,
    CASE 
        WHEN LENGTH(l.command) > 45 THEN SUBSTR(l.command, 1, 42) || '...'
        ELSE l.command
    END as command,
    l.status,
    COALESCE(e.exit_code, '') as exit_code,
    COALESCE(e.executed_at, 'Not executed') as executed_at
FROM logs l
LEFT JOIN execution_log e ON l.id = e.log_id
ORDER BY l.updated_at DESC
LIMIT 10;
EOF
    
    echo ""
}

# Cleanup function
cleanup() {
    release_lock
    log_message "INFO" "Engine stopped"
}

# Main execution
main() {
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   Script Execution Engine v1.0        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Database: $DB_FILE"
    echo "Log File: $LOG_FILE"
    echo "Mode: $([ "$WATCH_MODE" = true ] && echo "Continuous" || echo "Single Run")"
    echo ""
    
    # Set up cleanup trap
    trap cleanup EXIT INT TERM
    
    # Acquire lock
    acquire_lock
    
    # Initialize database
    init_database
    
    # If stats only mode
    if [ "$STATS_ONLY" = true ]; then
        show_stats
        exit 0
    fi
    
    # Process commands
    if [ "$WATCH_MODE" = true ]; then
        log_message "INFO" "Starting in watch mode (checking every 30 seconds)..."
        log_message "INFO" "Press Ctrl+C to stop"
        
        while true; do
            process_pending
            show_stats
            sleep 30
        done
    else
        process_pending
        show_stats
    fi
    
    log_message "INFO" "Engine cycle completed"
}

# Run main function
main "$@"
