#!/usr/bin/env python3
"""
CSV Redaction Tool - Production Grade
Author: Senior DevOps & Security Specialist
Description: 
    Recursively scans for CSV files, ingests them using Pandas with strict type handling,
    and applies comprehensive regex-based redaction rules to PII, Infrastructure IPs, 
    Secrets, and specific Business Logic (New Relic exception).

Dependencies: 
    pip install pandas numpy
"""

import os
import sys
import re
import logging
import argparse
import pathlib
import shutil
import pandas as pd
import numpy as np
from typing import Optional, List

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

class RedactionPatterns:
    """
    Centralized repository for compiled Regex patterns to ensure performance.
    """
    def __init__(self):
        # 1. Network & Infrastructure
        self.ipv4 = re.compile(r'(?<!\d)(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(?!\d)')
        self.ipv6 = re.compile(r'(?<![0-9a-fA-F:])(?:[A-F0-9]{1,4}:){7}[A-F0-9]{1,4}(?![0-9a-fA-F:])')
        # Matches FQDNs but excludes those containing "newrelic" (negative lookahead)
        # Uses lookbehind (?<!...) to ensure we don't match the tail of a skipped domain
        self.fqdn = re.compile(r'(?<![a-zA-Z0-9.-])(?![a-zA-Z0-9.-]*newrelic)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}\b')
        self.container_id = re.compile(r'\b[a-fA-F0-9]{64}\b') # 64-char hex strings (SHA256/Docker/K8s)
        self.mac_address = re.compile(r'([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})')

        # 2. Personal Identifiable Information (PII)
        self.email = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b')
        # International phone format heuristics (E.164-ish or dashed)
        self.phone = re.compile(r'(?<!\d)\+?1?[\s.-]?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}(?!\d)')
        self.ssn = re.compile(r'\b\d{3}-\d{2}-\d{4}\b')
        # Greetings (Hi/Hello/Hey Name,) - Case insensitive, preserves whitespace after greeting
        self.greeting_name = re.compile(r'(?i)\b(Hi|Hello|Hey)(\s+)([^\s,<>]+)\s*(?=,)')
        # Support Case Update (Your support case has been updated by Name.)
        self.support_update_name = re.compile(r'(?i)(Your support case has been updated by\s+)([^.]+?)(?=\.|$)')
        # Case Log Pattern (CM-ID,"Date",Name,Type)
        # Only redact if Type is "AllUsers"
        self.case_log_pattern = re.compile(r'(CM-\d+,\s*"[^"]+",\s*)([^,]+)(,\s*AllUsers)')
        
        # 3. Financial & Identifiers
        # Basic Luhn-compatible patterns (13-19 digits) - We will verify these with code
        self.credit_card_candidate = re.compile(r'\b(?:\d[ -]*?){13,19}\b')
        self.uuid = re.compile(r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b')
        
        # 4. Secrets & Keys
        # Broader key assignment matching
        self.api_keys_assignment = re.compile(r'(?i)\b(api_key|access_token|secret|private_key|key|token)\b\s*[:=]\s*[A-Za-z0-9_\-]+')
        # Specific high-entropy patterns
        self.aws_key_id = re.compile(r'\b(AKIA|ASIA)[0-9A-Z]{16}\b')
        self.google_api_key = re.compile(r'\bAIza[0-9A-Za-z\-_]{35}\b')
        self.stripe_key = re.compile(r'\b(sk|pk)_(test|live)_[0-9a-zA-Z]{24,}\b')
        
        # 5. Business Logic Targets (Competitors / Products)
        self.competitors = re.compile(r'(?i)\b(Salesforce|Oracle|SAP|Datadog|Splunk|Dynatrace|AppDynamics)\b', re.IGNORECASE)

class RedactionEngine:
    """
    Handles the logic of applying redactions to Pandas DataFrames.
    Refactored to use vectorized string operations for performance.
    """
    def __init__(self):
        self.patterns = RedactionPatterns()

    def _is_luhn_valid(self, cc_num: str) -> bool:
        """
        Checks if a string of digits passes the Luhn algorithm.
        """
        digits = [int(d) for d in cc_num if d.isdigit()]
        if not digits:
            return False
        checksum = 0
        reverse_digits = digits[::-1]
        for i, d in enumerate(reverse_digits):
            if i % 2 == 1:
                doubled = d * 2
                checksum += doubled if doubled < 10 else doubled - 9
            else:
                checksum += d
        return checksum % 10 == 0

    def _redact_credit_cards(self, text: str) -> str:
        """
        Callback for credit card redaction to apply Luhn check.
        Used in apply() where vectorization is too complex for custom logic.
        """
        if not isinstance(text, str):
            return text
            
        def replace_match(match):
            val = match.group(0)
            # Strip non-digits for check
            digits_only = re.sub(r'\D', '', val)
            if 13 <= len(digits_only) <= 19 and self._is_luhn_valid(digits_only):
                return '[REDACTED: CREDIT_CARD]'
            return val

        return self.patterns.credit_card_candidate.sub(replace_match, text)

    def process_dataframe(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Applies redaction across the entire DataFrame using vectorized operations.
        """
        # Ensure all data is string format
        df = df.astype(str)
        df.replace('nan', '', inplace=True)
        
        logger.info("Applying vectorized redaction rules...")

        # We process column by column to allow for column-specific logic if needed in future
        for col in df.columns:
            # 0. Business Logic Exception: New Relic
            # We want to avoid redacting "New Relic" product names, but still redact PII.
            # Since we are doing vectorized replacements, we can't easily "skip" a cell for one regex 
            # but apply others based on content without complex masking.
            # Strategy: Apply all PII redactions. Then apply Competitor redactions ONLY if "new relic" is NOT present.
            # Actually, the original logic was: if cell has "new relic", don't redact competitors/FQDNs.
            
            # Create a mask for cells that are "safe" (contain 'new relic')
            # We use this to conditionally apply the Competitor/FQDN redactions.
            is_nr_safe_mask = df[col].str.contains('new relic', case=False, na=False)
            
            # 1. Strong Identifiers (Technical)
            df[col] = df[col].str.replace(self.patterns.ipv4, '[REDACTED: IPv4]', regex=True)
            df[col] = df[col].str.replace(self.patterns.ipv6, '[REDACTED: IPv6]', regex=True)
            df[col] = df[col].str.replace(self.patterns.email, '[REDACTED: EMAIL]', regex=True)
            df[col] = df[col].str.replace(self.patterns.mac_address, '[REDACTED: MAC]', regex=True)
            df[col] = df[col].str.replace(self.patterns.uuid, '[REDACTED: UUID]', regex=True)
            df[col] = df[col].str.replace(self.patterns.container_id, '[REDACTED: CONTAINER_ID]', regex=True)
            df[col] = df[col].str.replace(self.patterns.aws_key_id, '[REDACTED: AWS_KEY]', regex=True)
            df[col] = df[col].str.replace(self.patterns.google_api_key, '[REDACTED: GOOGLE_KEY]', regex=True)
            df[col] = df[col].str.replace(self.patterns.stripe_key, '[REDACTED: STRIPE_KEY]', regex=True)
            df[col] = df[col].str.replace(self.patterns.api_keys_assignment, '[REDACTED: API_KEY_ASSIGNMENT]', regex=True)

            # 2. PII & Financial
            df[col] = df[col].str.replace(self.patterns.phone, '[REDACTED: PHONE]', regex=True)
            df[col] = df[col].str.replace(self.patterns.ssn, '[REDACTED: SSN]', regex=True)
            # Redact names in greetings (Hi Name,)
            df[col] = df[col].str.replace(self.patterns.greeting_name, r'\1\2[REDACTED: NAME]', regex=True)
            # Redact names in support case updates (Your support case has been updated by Name.)
            df[col] = df[col].str.replace(self.patterns.support_update_name, r'\1[REDACTED: NAME]', regex=True)
            # Redact names in case log patterns (CM-ID,"Date",Name,Type)
            df[col] = df[col].str.replace(self.patterns.case_log_pattern, r'\1[REDACTED: NAME]\3', regex=True)
            
            # Credit Cards need custom logic (Luhn), so we use apply() for just this pattern
            # This is slower than pure vectorization but necessary for accuracy.
            # We only run it if the column might contain digits.
            if df[col].str.contains(r'\d', regex=True).any():
                 df[col] = df[col].apply(self._redact_credit_cards)



        # 3. Hostnames / FQDNs
            # Apply only where NOT NR Safe and NOT an email (emails already redacted above, so we check for REDACTED: EMAIL)
            # Note: The original logic skipped FQDN if '@' was in val. Since we redacted emails first, 
            # the '@' might be gone or inside '[REDACTED: EMAIL]'. 
            # We'll assume if it's not safe, we redact FQDNs.
            # We use `mask` to apply changes only where the condition (NOT safe) is true.
            
            # Find FQDNs
            # We can't easily use 'mask' with str.replace directly in one go if we want to preserve the "newrelic.com" exception 
            # inside the regex.
            # Let's use a lambda for FQDN to handle the "newrelic.com" check per match if we want to be precise,
            # or just rely on the mask.
            # The original logic: if "new relic" in text, skip FQDN redaction entirely.
            # We will stick to that for performance.
            
            # Calculate the series with FQDNs redacted
            fqdn_redacted = df[col].str.replace(self.patterns.fqdn, '[REDACTED: FQDN]', regex=True)
            # Apply it only where NOT safe
            df[col] = df[col].where(is_nr_safe_mask, fqdn_redacted)

            # 4. Business Logic: Product Names / Competitors
            # Apply only where NOT NR Safe
            comp_redacted = df[col].str.replace(self.patterns.competitors, '[REDACTED: PRODUCT/COMPETITOR]', regex=True)
            df[col] = df[col].where(is_nr_safe_mask, comp_redacted)
            
            # 5. Column-Specific Logic (API Keys in named columns)
            col_lower = col.lower()
            if any(x in col_lower for x in ['api', 'key', 'secret', 'token', 'auth']):
                # Aggressive redaction for secret columns: Redact everything that looks like a high-entropy string
                # or just redact the whole cell if it's not empty?
                # Let's be safe but usable: Redact long alphanumeric strings that aren't already redacted
                # For now, relying on the improved patterns above is a huge step up.
                pass

        # 6. Cross-Column Logic: Case Logs (CM-ID, Date, Name, Type)
        # The regex self.case_log_pattern works if the line is a single string.
        # But if Pandas parses it into columns, we need to look across columns.
        # Pattern: [CM-ID] [Date] [Name] [Type=AllUsers]
        # We look for a column containing "AllUsers" and check if 3 columns back has "CM-".
        
        for i in range(len(df.columns)):
            # We need at least 3 columns before this one (indices 0, 1, 2 exist if i=3)
            if i < 3:
                continue
                
            # Check if current column (Type) has "AllUsers"
            # We use a mask for rows where this is true
            type_col = df.iloc[:, i]
            # Check if it contains AllUsers (exact or substring? User said "AllUsers," so maybe exact or strip)
            # The repro showed "AllUsers" as the value.
            is_all_users = type_col.str.contains(r'\bAllUsers\b', case=False, na=False)
            
            if not is_all_users.any():
                continue
                
            # Check if column i-3 (ID) has "CM-" prefix
            id_col = df.iloc[:, i-3]
            is_cm_id = id_col.str.contains(r'^CM-\d+', na=False)
            
            # Combine masks: Row must be AllUsers AND have CM- ID
            target_mask = is_all_users & is_cm_id
            
            if target_mask.any():
                logger.info(f"Detected structured Case Log pattern. Redacting names in column {df.columns[i-1]}...")
                # Redact column i-1 (Name) where mask is True
                # We replace the entire cell with [REDACTED: NAME] or just the name?
                # Since it's a Name column, we replace the value.
                df.iloc[:, i-1] = df.iloc[:, i-1].mask(target_mask, '[REDACTED: NAME]')

        return df

def get_encoding(file_path):
    """
    Simple heuristic to detect file encoding.
    """
    encodings = ['utf-8', 'latin-1', 'cp1252', 'utf-16']
    for enc in encodings:
        try:
            with open(file_path, 'r', encoding=enc) as f:
                f.read(1024)
            return enc
        except UnicodeDecodeError:
            continue
    return 'utf-8' # Fallback

def main():
    parser = argparse.ArgumentParser(description="Secure CSV Redaction Tool")
    parser.add_argument("input_dir", help="Path to the directory containing CSV files to scan")
    parser.add_argument("--output_dir", help="Path to the directory where redacted files will be saved", default=None)
    args = parser.parse_args()

    input_path = pathlib.Path(args.input_dir)
    if not input_path.exists():
        logger.error(f"Input directory does not exist: {args.input_dir}")
        sys.exit(1)

    # Create Output Directory
    if args.output_dir:
        output_base = pathlib.Path(args.output_dir)
    else:
        # Default behavior: output to 'sanitized_csv' sibling directory
        # e.g. input: ./csv -> output: ./sanitized_csv
        output_base = input_path.parent / "sanitized_csv"

    if output_base.exists():
        logger.warning(f"Output directory {output_base} already exists. Files may be overwritten.")
    else:
        output_base.mkdir(parents=True, exist_ok=True)

    engine = RedactionEngine()
    file_count = 0

    # Recursive Scan
    for root, dirs, files in os.walk(input_path):
        for file in files:
            if file.lower().endswith('.csv'):
                file_count += 1
                source_file = pathlib.Path(root) / file
                
                # Calculate relative path to maintain structure
                rel_path = source_file.relative_to(input_path)
                dest_file = output_base / rel_path
                
                # Ensure subdirectories exist in output
                dest_file.parent.mkdir(parents=True, exist_ok=True)

                logger.info(f"Processing: {source_file}")

                try:
                    # 1. Detect Encoding
                    enc = get_encoding(source_file)
                    
                    # 2. Load Data
                    # dtype=str ensures we don't lose leading zeros in IDs or convert "123E4" to float
                    # dtype=str ensures we don't lose leading zeros in IDs or convert "123E4" to float
                    df = pd.read_csv(source_file, encoding=enc, dtype=str, on_bad_lines='warn')

                    # 3. Process
                    redacted_df = engine.process_dataframe(df)

                    # 4. Save
                    redacted_df.to_csv(dest_file, index=False, encoding='utf-8')
                    logger.info(f"Success: Saved to {dest_file}")

                except Exception as e:
                    logger.error(f"Failed to process {source_file}: {str(e)}")

    logger.info(f"Job Complete. Processed {file_count} CSV files.")
    logger.info(f"Redacted data stored in: {output_base}")

if __name__ == "__main__":
    main()