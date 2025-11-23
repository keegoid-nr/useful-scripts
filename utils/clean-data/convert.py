import pandas as pd
from bs4 import BeautifulSoup
import sys
import os
from pathlib import Path

def clean_html(text):
    """
    Parses HTML text and returns plain text.
    Uses BeautifulSoup for robust parsing.
    """
    if not text or pd.isna(text):
        return ""
    
    # BeautifulSoup parses the HTML and get_text() extracts the text
    # separator=' ' ensures words don't merge when tags are removed
    try:
        soup = BeautifulSoup(str(text), "html.parser")
        text = soup.get_text(separator=" ").strip()
    except Exception as e:
        # Fallback if BS4 fails (rare)
        return str(text)
    
    # Remove excessive whitespace (newlines, tabs, multiple spaces)
    text = " ".join(text.split())
    
    return text

def parse_custom_text_file(filepath):
    """
    Reads a text file where headers and values are separated by a blank line.
    Format:
    Header1
    Header2
    ...
    <blank line>
    Value1
    Value2
    ...
    """
    try:
        # Try UTF-8 first
        with open(filepath, 'r', encoding='utf-8') as f:
            lines = f.read().splitlines()
    except UnicodeDecodeError:
        # Fallback to Latin-1 if UTF-8 fails (common for email dumps)
        with open(filepath, 'r', encoding='latin-1') as f:
            lines = f.read().splitlines()

    if not lines:
        return None, None

    # Find the separator (first empty line)
    try:
        sep_index = lines.index('')
    except ValueError:
        # If no blank line is found, we can't parse the structure reliably
        print(f"Skipping [{filepath.name}]: No blank line separator found.")
        return None, None

    headers = lines[:sep_index]
    raw_values = lines[sep_index+1:]

    # Chunk the values based on the number of headers
    num_headers = len(headers)
    if num_headers == 0:
        return None, None

    # Filter out empty lines from raw_values if any (optional, but safer)
    # raw_values = [v for v in raw_values if v.strip()] 
    # Actually, let's assume the structure is strict for now as per user description.
    
    if len(raw_values) % num_headers != 0:
        print(f"Warning [{filepath.name}]: Value count ({len(raw_values)}) is not a multiple of header count ({num_headers}). Data might be misaligned.")
        # We will proceed but warn.
    
    value_sets = [raw_values[i:i + num_headers] for i in range(0, len(raw_values), num_headers)]

    return headers, value_sets

def process_directory(input_dir_path, output_dir_path):
    input_dir = Path(input_dir_path)
    output_dir = Path(output_dir_path)

    if not input_dir.exists():
        print(f"Error: Input directory '{input_dir}' does not exist.")
        return

    # Create output directory if it doesn't exist
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Input Directory:  {input_dir}")
    print(f"Output Directory: {output_dir}")

    # Process all .txt files
    files = list(input_dir.glob('*.txt'))
    if not files:
        print(f"No .txt files found in {input_dir}")
        return

    print(f"Found {len(files)} text files. Processing...")

    processed_count = 0
    for file_path in files:
        headers, value_sets = parse_custom_text_file(file_path)
        
        if headers is None or not value_sets:
            continue

        records = []
        for values in value_sets:
            # Basic validation: Headers must match Values count
            if len(headers) != len(values):
                print(f"Warning [{file_path.name}]: Mismatch - {len(headers)} headers vs {len(values)} values in a record. Skipping record.")
                continue

            # Create Dictionary mapping headers to values
            record = dict(zip(headers, values))

            # Find the 'Body' column (case-insensitive search)
            body_key = next((h for h in headers if h.lower() == 'body'), None)

            if body_key:
                original_body = record[body_key]
                clean_body = clean_html(original_body)
                
                # Truncate to 50,000 chars for Google Sheets/Excel compatibility
                if len(clean_body) > 50000:
                    clean_body = clean_body[:50000]
                
                record[body_key] = clean_body
            
            records.append(record)

        if not records:
            continue

        # Create DataFrame
        df = pd.DataFrame(records)

        # Define output filename (same name, .csv extension)
        output_file = output_dir / f"{file_path.stem}.csv"
        
        # Write to CSV
        try:
            df.to_csv(output_file, index=False)
            processed_count += 1
            # Optional: Print progress for every 10 files
            if processed_count % 10 == 0:
                print(f"Processed {processed_count} files...")
        except Exception as e:
            print(f"Error writing {output_file.name}: {e}")

    print(f"Done! Successfully processed {processed_count} files.")

if __name__ == "__main__":
    # Check arguments
    if len(sys.argv) < 2:
        print("Usage: python convert.py <input_txt_directory> [output_csv_directory]")
        print("Example: python convert.py ./data/txt/")
        sys.exit(1)

    input_path = sys.argv[1]
    
    # Determine output path
    if len(sys.argv) > 2:
        output_path = sys.argv[2]
    else:
        # Default behavior: Create a 'csv' folder at the same level as the 'txt' folder
        # e.g., if input is /my/data/txt, output will be /my/data/csv
        input_p = Path(input_path)
        # If the input path ends in 'txt', try to swap it to 'csv'
        if input_p.name == 'txt':
            output_path = input_p.parent / 'csv'
        else:
            # Otherwise just create a 'processed_csv' folder inside the input
            output_path = input_p / 'processed_csv'

    process_directory(input_path, output_path)