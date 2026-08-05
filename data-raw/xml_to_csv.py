#!/usr/bin/env python3
import xml.etree.ElementTree as ET
import csv
import sys
import time

def xml_to_csv(xml_path, csv_path):
    start_time = time.time()
    
    # Parse XML
    tree = ET.parse(xml_path)
    root = tree.getroot()
    
    # Find all elements (ElementTree handles namespaces automatically in iteration)
    # Get the namespace from root tag
    ns = ''
    if '}' in root.tag:
        ns = root.tag.split('}')[0] + '}'
    
    # Find all child elements (skip the wrapper, get actual records)
    records = list(root)
    
    if not records:
        print(f"ERROR: No records found", file=sys.stderr)
        return False
    
    print(f"Found {len(records)} records", file=sys.stderr)
    
    # Extract field names from first record
    field_names = []
    for child in records[0]:
        tag = child.tag
        if '}' in tag:
            tag = tag.split('}')[1]
        field_names.append(tag)
    
    print(f"Found {len(field_names)} fields", file=sys.stderr)
    
    # Write CSV
    with open(csv_path, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=field_names)
        writer.writeheader()
        
        for record in records:
            row = {}
            for field in field_names:
                # Find element with or without namespace
                elem = record.find(f'{ns}{field}')
                if elem is None:
                    elem = record.find(field)
                row[field] = (elem.text or '').strip() if elem is not None else ''
            writer.writerow(row)
    
    elapsed = time.time() - start_time
    file_size = os.path.getsize(csv_path) / 1024 / 1024
    print(f"Wrote {len(records)} rows in {elapsed:.2f}s | CSV size: {file_size:.1f} MB", file=sys.stderr)
    return True

import os
if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: python3 xml_to_csv.py input.xml output.csv", file=sys.stderr)
        sys.exit(1)
    
    xml_path, csv_path = sys.argv[1], sys.argv[2]
    success = xml_to_csv(xml_path, csv_path)
    sys.exit(0 if success else 1)
