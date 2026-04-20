#!/bin/bash

# frontend.sh - Interactive frontend for the script execution engine
# Provides a user-friendly interface to manage and execute commands

DB_FILE="${DB_FILE:-./engine.db}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to print header
print_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        Script Execution Engine - Frontend Interface            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to check engine status
check_engine_status() {
    if [ -f /tmp/script-engine.pid ]; then
        local pid=$(cat /tmp/script-engine.pid)
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}● Engine Status: RUNNING (PID: $pid)${NC}"
        else
            echo -e "${RED}● Engine Status: STOPPED (stale PID file)${NC}"
        fi
    else
        echo -e "${YELLOW}● Engine Status: STOPPED${NC}"
    fi
    echo ""
}

# Function to show menu
show_menu() {
    echo -e "${BLUE}═══ Main Menu ═══${NC}"
    echo "1. Add command to queue"
    echo "2. View pending commands"
    echo "3. View execution history"
    echo "4. View execution logs (detailed)"
    echo "5. Start engine (background)"
    echo "6. Stop engine"
    echo "7. Process queue once"
    echo "8. View statistics"
    echo "9. Test with sample commands"
    echo "0. Exit"
    echo ""
    echo -n "Select option: "
}

# Function to add command
add_command() {
    echo -e "\n${CYAN}═══ Add Command ═══${NC}"
    echo -n "Enter command to execute: "
    read -r command
    
    if [ -z "$command" ]; then
        echo -e "${RED}Error: Command cannot be empty${NC}"
        return
    fi
    
    # Escape single quotes for SQL
    escaped_command="${command//\'/\'\'}"
    
    result=$(sqlite3 "$DB_FILE" <<EOF
INSERT INTO logs (command, status)
VALUES ('$escaped_command', 'pending');
SELECT last_insert_rowid();
EOF
)
    
    echo -e "${GREEN}✓ Command queued successfully!${NC}"
    echo -e "  ${BLUE}ID:${NC} $result"
    echo -e "  ${BLUE}Command:${NC} $command"
    echo -e "  ${BLUE}Status:${NC} pending"
}

# Function to view pending commands
view_pending() {
    echo -e "\n${CYAN}═══ Pending Commands ═══${NC}\n"
    
    sqlite3 "$DB_FILE" <<'EOF'
.mode column
.headers on
.width 5 60 10 20

SELECT 
    id,
    CASE 
        WHEN LENGTH(command) > 60 THEN SUBSTR(command, 1, 57) || '...'
        ELSE command
    END as command,
    status,
    created_at
FROM logs
WHERE status = 'pending'
ORDER BY created_at ASC;
EOF
    
    local count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM logs WHERE status = 'pending';")
    echo ""
    echo -e "${BLUE}Total pending:${NC} $count"
}

# Function to view execution history
view_history() {
    echo -e "\n${CYAN}═══ Execution History (Last 20) ═══${NC}\n"
    
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
LIMIT 20;
EOF
}

# Function to view detailed execution logs
view_execution_logs() {
    echo -e "\n${CYAN}═══ Detailed Execution Logs ═══${NC}\n"
    
    echo -e "${YELLOW}Recent executions with output:${NC}\n"
    
    sqlite3 "$DB_FILE" <<'EOF'
.mode line
.headers on

SELECT 
    l.id as 'Log ID',
    l.command as 'Command',
    l.status as 'Status',
    e.exit_code as 'Exit Code',
    e.output as 'Output',
    e.error_output as 'Error Output',
    e.executed_at as 'Executed At'
FROM logs l
JOIN execution_log e ON l.id = e.log_id
ORDER BY e.executed_at DESC
LIMIT 10;
EOF
}

# Function to start engine
start_engine() {
    echo -e "\n${CYAN}═══ Starting Engine ═══${NC}"
    
    if [ -f /tmp/script-engine.pid ]; then
        local pid=$(cat /tmp/script-engine.pid)
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}Engine is already running (PID: $pid)${NC}"
            return
        fi
    fi
    
    nohup ./start-engine.sh --watch > /dev/null 2>&1 &
    sleep 2
    
    if [ -f /tmp/script-engine.pid ]; then
        local pid=$(cat /tmp/script-engine.pid)
        echo -e "${GREEN}✓ Engine started successfully (PID: $pid)${NC}"
        echo -e "  Logs are being written to: ${BLUE}dbmigrate.log${NC}"
    else
        echo -e "${RED}✗ Failed to start engine${NC}"
    fi
}

# Function to stop engine
stop_engine() {
    echo -e "\n${CYAN}═══ Stopping Engine ═══${NC}"
    
    if [ ! -f /tmp/script-engine.pid ]; then
        echo -e "${YELLOW}Engine is not running${NC}"
        return
    fi
    
    local pid=$(cat /tmp/script-engine.pid)
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        sleep 1
        echo -e "${GREEN}✓ Engine stopped (PID: $pid)${NC}"
    else
        echo -e "${YELLOW}Engine was not running (stale PID file removed)${NC}"
    fi
    
    rm -f /tmp/script-engine.pid /tmp/script-engine.lock
}

# Function to process queue once
process_once() {
    echo -e "\n${CYAN}═══ Processing Queue ═══${NC}\n"
    ./start-engine.sh --once
}

# Function to view statistics
view_stats() {
    echo -e "\n${CYAN}═══ Statistics ═══${NC}\n"
    ./start-engine.sh --stats
}

# Function to add test commands
add_test_commands() {
    echo -e "\n${CYAN}═══ Adding Test Commands ═══${NC}\n"
    
    echo "Adding valid commands..."
    ./add-command.sh "echo 'Test 1: Hello from script engine'"
    ./add-command.sh "date '+%Y-%m-%d %H:%M:%S'"
    ./add-command.sh "uname -a"
    ./add-command.sh "ls -la /tmp | head -5"
    ./add-command.sh "echo 'Multi-step command' && sleep 1 && echo 'Step complete'"
    ./add-command.sh "whoami"
    ./add-command.sh "pwd"
    
    echo -e "\n${YELLOW}Adding commands that will fail...${NC}"
    ./add-command.sh "ls /nonexistent/directory"
    ./add-command.sh "cat /etc/shadow"
    ./add-command.sh "invalid_command_xyz"
    ./add-command.sh "grep --invalid-flag file.txt"
    ./add-command.sh "exit 99"
    
    echo -e "\n${GREEN}✓ Test commands added!${NC}"
    echo -e "${BLUE}Total commands added: 12 (7 valid, 5 will fail)${NC}"
}

# Main loop
main() {
    # Ensure database exists
    if [ ! -f "$DB_FILE" ]; then
        echo "Initializing database..."
        ./start-engine.sh --once > /dev/null 2>&1
    fi
    
    while true; do
        print_header
        check_engine_status
        show_menu
        
        read -r choice
        
        case $choice in
            1)
                add_command
                ;;
            2)
                view_pending
                ;;
            3)
                view_history
                ;;
            4)
                view_execution_logs
                ;;
            5)
                start_engine
                ;;
            6)
                stop_engine
                ;;
            7)
                process_once
                ;;
            8)
                view_stats
                ;;
            9)
                add_test_commands
                ;;
            0)
                echo -e "\n${GREEN}Goodbye!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
        
        echo ""
        echo -n "Press Enter to continue..."
        read
    done
}

# Run main
main
