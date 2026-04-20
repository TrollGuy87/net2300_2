#!/bin/bash

# dblogrotate.sh - Log rotation script for dbmigrate.log
# Rotates log file at midnight every day
# Keeps last 7 days of logs
#
# To schedule with cron (runs at midnight daily):
# 0 0 * * * /path/to/dblogrotate.sh

set -euo pipefail

# Configuration
LOG_FILE="${LOG_FILE:-./dbmigrate.log}"
LOG_DIR="${LOG_DIR:-./logs}"
MAX_DAYS=7
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message"
}

# Function to rotate log
rotate_log() {
    log_message "INFO" "Starting log rotation for: $LOG_FILE"
    
    # Check if log file exists
    if [ ! -f "$LOG_FILE" ]; then
        log_message "WARN" "Log file does not exist: $LOG_FILE"
        return 0
    fi
    
    # Get file size
    local filesize=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
    log_message "INFO" "Current log file size: $filesize bytes"
    
    # Create log directory if it doesn't exist
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        log_message "INFO" "Created log directory: $LOG_DIR"
    fi
    
    # Skip rotation if file is empty or very small
    if [ "$filesize" -lt 100 ]; then
        log_message "INFO" "Log file is too small to rotate (< 100 bytes). Skipping."
        return 0
    fi
    
    # Generate rotated filename
    local rotated_file="$LOG_DIR/dbmigrate-$TIMESTAMP.log"
    
    # Copy current log to rotated file
    cp "$LOG_FILE" "$rotated_file"
    log_message "INFO" "Log file copied to: $rotated_file"
    
    # Compress rotated log
    gzip "$rotated_file"
    log_message "INFO" "Compressed: $rotated_file.gz"
    
    # Clear the current log file (don't delete, just truncate)
    > "$LOG_FILE"
    log_message "INFO" "Truncated current log file: $LOG_FILE"
    
    # Write rotation marker to new log
    echo "=== Log rotated at $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG_FILE"
    echo "Previous log archived as: $rotated_file.gz" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# Function to cleanup old logs
cleanup_old_logs() {
    log_message "INFO" "Cleaning up logs older than $MAX_DAYS days"
    
    if [ ! -d "$LOG_DIR" ]; then
        log_message "WARN" "Log directory does not exist: $LOG_DIR"
        return 0
    fi
    
    # Find and delete logs older than MAX_DAYS
    local deleted_count=0
    while IFS= read -r -d '' file; do
        rm -f "$file"
        log_message "INFO" "Deleted old log: $file"
        ((deleted_count++)) || true
    done < <(find "$LOG_DIR" -name "dbmigrate-*.log.gz" -type f -mtime +$MAX_DAYS -print0 2>/dev/null || true)
    
    if [ "$deleted_count" -gt 0 ]; then
        log_message "INFO" "Deleted $deleted_count old log file(s)"
    else
        log_message "INFO" "No old log files to delete"
    fi
}

# Function to display statistics
show_stats() {
    echo ""
    echo -e "${GREEN}═══ Log Rotation Statistics ═══${NC}"
    echo ""
    
    # Current log size
    if [ -f "$LOG_FILE" ]; then
        local current_size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
        local current_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")
        echo -e "${BLUE}Current Log:${NC}"
        echo "  File: $LOG_FILE"
        echo "  Size: $current_size bytes"
        echo "  Lines: $current_lines"
    else
        echo -e "${YELLOW}Current log file does not exist${NC}"
    fi
    
    echo ""
    
    # Archived logs
    if [ -d "$LOG_DIR" ]; then
        local archive_count=$(find "$LOG_DIR" -name "dbmigrate-*.log.gz" -type f 2>/dev/null | wc -l)
        local total_archive_size=0
        for f in $(find "$LOG_DIR" -name "dbmigrate-*.log.gz" -type f 2>/dev/null); do
            local fsize=$(stat -c%s "$f" 2>/dev/null || echo "0")
            total_archive_size=$((total_archive_size + fsize))
        done
        
        echo -e "${BLUE}Archived Logs:${NC}"
        echo "  Directory: $LOG_DIR"
        echo "  Count: $archive_count"
        echo "  Total Size: $total_archive_size bytes"
        
        if [ "$archive_count" -gt 0 ]; then
            echo ""
            echo -e "${BLUE}Recent Archives:${NC}"
            find "$LOG_DIR" -name "dbmigrate-*.log.gz" -type f -exec ls -lh {} + 2>/dev/null | tail -5 | awk '{print "  " $9 " (" $5 ")"}'
        fi
    else
        echo -e "${YELLOW}Archive directory does not exist${NC}"
    fi
    
    echo ""
}

# Function to create cron job
install_cron() {
    local script_path=$(realpath "$0")
    local cron_line="0 0 * * * $script_path >> $LOG_DIR/rotation.log 2>&1"
    
    echo -e "${YELLOW}═══ Cron Installation ═══${NC}"
    echo ""
    echo "To install this script to run at midnight every day, add this line to crontab:"
    echo ""
    echo -e "${GREEN}$cron_line${NC}"
    echo ""
    echo "Run: crontab -e"
    echo "Then add the line above."
    echo ""
    echo "Or run this command to install automatically:"
    echo -e "${GREEN}(crontab -l 2>/dev/null; echo \"$cron_line\") | crontab -${NC}"
    echo ""
}

# Main execution
main() {
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Database Log Rotation Script                      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Parse command line arguments
    case "${1:-rotate}" in
        rotate)
            rotate_log
            cleanup_old_logs
            show_stats
            ;;
        stats)
            show_stats
            ;;
        install)
            install_cron
            ;;
        help|--help|-h)
            echo "Usage: $0 [rotate|stats|install|help]"
            echo ""
            echo "Commands:"
            echo "  rotate  - Rotate log file and cleanup old logs (default)"
            echo "  stats   - Show log statistics only"
            echo "  install - Show cron installation instructions"
            echo "  help    - Show this help message"
            echo ""
            echo "Configuration (via environment variables):"
            echo "  LOG_FILE  - Path to log file (default: ./dbmigrate.log)"
            echo "  LOG_DIR   - Directory for rotated logs (default: ./logs)"
            echo "  MAX_DAYS  - Days to keep old logs (default: 7)"
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
    
    log_message "INFO" "Log rotation completed successfully"
}

# Run main function
main "$@"
