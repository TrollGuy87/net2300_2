#!/usr/bin/env python3

"""
demo-improved-engine.py - Demonstration of the improved script engine
Shows all requested features without requiring sqlite3 binary
"""

import sqlite3
import subprocess
import time
import os
from datetime import datetime
from pathlib import Path

# Colors for output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    MAGENTA = '\033[0;35m'
    NC = '\033[0m'

def print_header(text):
    """Print a formatted header"""
    print(f"\n{Colors.GREEN}{'='*70}{Colors.NC}")
    print(f"{Colors.GREEN}{text}{Colors.NC}")
    print(f"{Colors.GREEN}{'='*70}{Colors.NC}\n")

def init_database(db_file="engine.db"):
    """Initialize the database"""
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    
    # Create logs table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            command TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            CHECK (status IN ('pending', 'done', 'error'))
        )
    ''')
    
    # Create execution_log table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS execution_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            log_id INTEGER NOT NULL,
            status TEXT NOT NULL,
            output TEXT,
            error_output TEXT,
            exit_code INTEGER,
            executed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (log_id) REFERENCES logs(id)
        )
    ''')
    
    conn.commit()
    conn.close()
    print(f"{Colors.GREEN}✓ Database initialized{Colors.NC}")

def add_command(command, db_file="engine.db"):
    """Add a command to the queue"""
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    cursor.execute("INSERT INTO logs (command, status) VALUES (?, 'pending')", (command,))
    cmd_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return cmd_id

def execute_command(log_id, command, db_file="engine.db"):
    """Execute a command and log results"""
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        status = 'done' if result.returncode == 0 else 'error'
        
        conn = sqlite3.connect(db_file)
        cursor = conn.cursor()
        
        # Update logs table
        cursor.execute(
            "UPDATE logs SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            (status, log_id)
        )
        
        # Insert into execution_log
        cursor.execute('''
            INSERT INTO execution_log (log_id, status, output, error_output, exit_code)
            VALUES (?, ?, ?, ?, ?)
        ''', (log_id, status, result.stdout, result.stderr, result.returncode))
        
        conn.commit()
        conn.close()
        
        return result.returncode == 0
        
    except Exception as e:
        conn = sqlite3.connect(db_file)
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE logs SET status = 'error', updated_at = CURRENT_TIMESTAMP WHERE id = ?",
            (log_id,)
        )
        cursor.execute('''
            INSERT INTO execution_log (log_id, status, output, error_output, exit_code)
            VALUES (?, 'error', '', ?, -1)
        ''', (log_id, str(e)))
        conn.commit()
        conn.close()
        return False

def process_pending(db_file="engine.db"):
    """Process all pending commands"""
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    cursor.execute("SELECT id, command FROM logs WHERE status = 'pending' ORDER BY created_at ASC")
    pending = cursor.fetchall()
    conn.close()
    
    success = 0
    failed = 0
    
    for log_id, command in pending:
        print(f"{Colors.BLUE}[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}]{Colors.NC} Executing ID {log_id}: {command[:50]}...")
        if execute_command(log_id, command, db_file):
            success += 1
            print(f"{Colors.GREEN}  ✓ Success{Colors.NC}")
        else:
            failed += 1
            print(f"{Colors.RED}  ✗ Failed{Colors.NC}")
    
    return len(pending), success, failed

def show_execution_log(db_file="engine.db"):
    """Show execution log entries"""
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT 
            l.id,
            l.command,
            l.status,
            e.exit_code,
            e.output,
            e.error_output,
            e.executed_at
        FROM logs l
        JOIN execution_log e ON l.id = e.log_id
        ORDER BY e.executed_at DESC
        LIMIT 20
    ''')
    
    results = cursor.fetchall()
    conn.close()
    
    for row in results:
        log_id, cmd, status, exit_code, output, error_output, executed_at = row
        print(f"\n{Colors.CYAN}{'─'*70}{Colors.NC}")
        print(f"  {Colors.BLUE}Log ID:{Colors.NC} {log_id}")
        print(f"  {Colors.BLUE}Command:{Colors.NC} {cmd[:60]}")
        print(f"  {Colors.BLUE}Status:{Colors.NC} {status}")
        print(f"  {Colors.BLUE}Exit Code:{Colors.NC} {exit_code}")
        if output:
            print(f"  {Colors.BLUE}Output:{Colors.NC} {output[:100]}")
        if error_output:
            print(f"  {Colors.RED}Error:{Colors.NC} {error_output[:100]}")
        print(f"  {Colors.BLUE}Executed:{Colors.NC} {executed_at}")

def show_statistics(db_file="engine.db"):
    """Show execution statistics"""
    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()
    
    # Status counts
    cursor.execute("SELECT status, COUNT(*) FROM logs GROUP BY status")
    print(f"\n{Colors.CYAN}Status Summary:{Colors.NC}")
    for status, count in cursor.fetchall():
        print(f"  {status:10s}: {count:3d}")
    
    # Success vs Failure
    cursor.execute('''
        SELECT 
            CASE WHEN exit_code = 0 THEN 'Success' ELSE 'Failure' END as result,
            COUNT(*) as count
        FROM execution_log
        GROUP BY (exit_code = 0)
    ''')
    print(f"\n{Colors.CYAN}Result Summary:{Colors.NC}")
    for result, count in cursor.fetchall():
        print(f"  {result:10s}: {count:3d}")
    
    conn.close()

def main():
    """Main demonstration function"""
    print(f"{Colors.CYAN}")
    print("╔" + "="*68 + "╗")
    print("║" + " "*68 + "║")
    print("║" + "     SCRIPT EXECUTION ENGINE - IMPROVED DEMONSTRATION".center(68) + "║")
    print("║" + " "*68 + "║")
    print("╚" + "="*68 + "╝")
    print(f"{Colors.NC}")
    
    db_file = "engine.db"
    log_file = "dbmigrate.log"
    
    # Clean start
    if os.path.exists(db_file):
        os.remove(db_file)
    if os.path.exists(log_file):
        os.remove(log_file)
    
    # STEP 1: Initialize
    print_header("STEP 1: Initialize Database")
    init_database(db_file)
    
    # STEP 2: Add valid Linux commands
    print_header("STEP 2: Add Valid Linux Commands")
    valid_commands = [
        "echo 'Command 1: System Information'",
        "uname -a",
        "echo 'Command 2: Current Date'",
        "date '+%Y-%m-%d %H:%M:%S'",
        "echo 'Command 3: Current User'",
        "whoami",
        "echo 'Command 4: Working Directory'",
        "pwd",
        "echo 'Command 5: List Files'",
        "ls -la /tmp | head -5",
        "echo 'Command 6: Environment'",
        "env | head -5"
    ]
    
    for cmd in valid_commands:
        cmd_id = add_command(cmd, db_file)
        print(f"{Colors.GREEN}  ✓{Colors.NC} Added command {cmd_id}: {cmd[:50]}")
    
    # STEP 3: Add commands with errors
    print_header("STEP 3: Add Commands with Syntax Errors")
    error_commands = [
        "ls /this/directory/does/not/exist",
        "cat /root/secret/file.txt",
        "invalid_command_that_does_not_exist",
        "grep --invalid-option-xyz file.txt",
        "chmod 9999 file.txt",
        "cd /nonexistent && pwd",
        "echo 'Test' | invalid_pipe_command",
        "rm -rf /"  # Will fail (permission denied)
    ]
    
    for cmd in error_commands:
        cmd_id = add_command(cmd, db_file)
        print(f"{Colors.YELLOW}  ⚠{Colors.NC} Added failing command {cmd_id}: {cmd[:50]}")
    
    # STEP 4: Process commands
    print_header("STEP 4: Process All Commands")
    total, success, failed = process_pending(db_file)
    print(f"\n{Colors.BLUE}Summary:{Colors.NC} Total={total}, Success={success}, Failed={failed}")
    
    # STEP 5: Show execution log
    print_header("STEP 5: Show execution_log Table Entries")
    show_execution_log(db_file)
    
    # STEP 6: Show statistics
    print_header("STEP 6: Show Statistics")
    show_statistics(db_file)
    
    # STEP 7: Write to log file
    print_header("STEP 7: Log File Output")
    with open(log_file, 'w') as f:
        f.write(f"=== Script Engine Execution Log - {datetime.now()} ===\n\n")
        conn = sqlite3.connect(db_file)
        cursor = conn.cursor()
        cursor.execute('''
            SELECT l.id, l.command, l.status, e.exit_code, e.executed_at
            FROM logs l
            JOIN execution_log e ON l.id = e.log_id
            ORDER BY e.executed_at
        ''')
        for row in cursor.fetchall():
            f.write(f"[{row[4]}] ID={row[0]} Status={row[2]} ExitCode={row[3]} Command={row[1]}\n")
        conn.close()
    
    log_size = os.path.getsize(log_file)
    print(f"{Colors.GREEN}✓ Log written to {log_file} ({log_size} bytes){Colors.NC}")
    print(f"\nLast 10 lines:")
    with open(log_file, 'r') as f:
        lines = f.readlines()
        for line in lines[-10:]:
            print(f"  {line.rstrip()}")
    
    # Final summary
    print(f"\n{Colors.CYAN}")
    print("╔" + "="*68 + "╗")
    print("║" + " "*68 + "║")
    print("║" + "DEMONSTRATION COMPLETE!".center(68) + "║")
    print("║" + " "*68 + "║")
    print("╚" + "="*68 + "╝")
    print(f"{Colors.NC}\n")
    
    print(f"{Colors.GREEN}Files Created:{Colors.NC}")
    print(f"  • {db_file} - SQLite database with logs and execution_log tables")
    print(f"  • {log_file} - Execution log file")
    print(f"\n{Colors.BLUE}You can now use:{Colors.NC}")
    print(f"  • ./frontend.sh - Interactive frontend")
    print(f"  • ./start-engine.sh --start - Start background engine with nohup")
    print(f"  • ./dblogrotate.sh - Rotate logs\n")

if __name__ == "__main__":
    main()
