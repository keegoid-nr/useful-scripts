#!/usr/bin/env python3
"""
Data Processing Orchestrator

This script manages the two-step data cleaning process:
1. Convert TXT to CSV (stripping HTML)
2. Sanitize CSV (redacting sensitive info)

Usage:
    python process_data.py <input_txt_directory>
"""

import sys
import os
import subprocess
import time
from pathlib import Path

def run_step(command, step_name):
    """Runs a shell command and handles errors."""
    print(f"\n{'='*60}")
    print(f"Starting Step: {step_name}")
    print(f"Command: {' '.join(command)}")
    print(f"{'='*60}\n")

    start_time = time.time()
    
    try:
        # Run command and stream output
        result = subprocess.run(command, check=True, text=True)
        
        duration = time.time() - start_time
        print(f"\n[SUCCESS] {step_name} completed in {duration:.2f} seconds.")
        return True
        
    except subprocess.CalledProcessError as e:
        print(f"\n[ERROR] {step_name} failed with exit code {e.returncode}.")
        return False
    except Exception as e:
        print(f"\n[ERROR] An unexpected error occurred during {step_name}: {e}")
        return False

def main():
    if len(sys.argv) < 2:
        print("Usage: python process_data.py <input_txt_directory>")
        sys.exit(1)

    input_txt_dir = Path(sys.argv[1]).resolve()
    
    if not input_txt_dir.exists():
        print(f"Error: Input directory '{input_txt_dir}' does not exist.")
        sys.exit(1)

    # Define directory structure
    # Assumes structure:
    # parent/
    #   txt/  (input)
    #   csv/  (intermediate)
    #   sanitized_csv/ (final)
    
    base_dir = input_txt_dir.parent
    csv_dir = base_dir / "csv"
    sanitized_dir = base_dir / "sanitized_csv"

    print(f"Processing Data...")
    print(f"Input:     {input_txt_dir}")
    print(f"Intermed:  {csv_dir}")
    print(f"Output:    {sanitized_dir}")

    # Get paths to scripts (assuming they are in the same directory as this script)
    script_dir = Path(__file__).parent.resolve()
    convert_script = script_dir / "convert.py"
    sanitize_script = script_dir / "sanitize.py"

    if not convert_script.exists() or not sanitize_script.exists():
        print("Error: Could not find child scripts (convert.py, sanitize.py) in the same directory.")
        sys.exit(1)

    # --- Step 1: Convert ---
    cmd_convert = [sys.executable, str(convert_script), str(input_txt_dir), str(csv_dir)]
    if not run_step(cmd_convert, "Convert TXT to CSV"):
        print("\nProcessing aborted due to failure in Step 1.")
        sys.exit(1)

    # --- Step 2: Sanitize ---
    cmd_sanitize = [sys.executable, str(sanitize_script), str(csv_dir), "--output_dir", str(sanitized_dir)]
    if not run_step(cmd_sanitize, "Sanitize CSV"):
        print("\nProcessing aborted due to failure in Step 2.")
        sys.exit(1)

    print(f"\n{'='*60}")
    print("ALL STEPS COMPLETED SUCCESSFULLY")
    print(f"Final sanitized data is available in: {sanitized_dir}")
    print(f"{'='*60}")

if __name__ == "__main__":
    main()
