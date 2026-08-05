#!/usr/bin/env python3
"""
Fast XML to Parquet converter with type casting for DATRAS files.
Eliminates intermediate CSV by parsing, typing, and writing parquet in one pass.

Usage: python3 xml_to_parquet.py input.xml output.parquet dict.yaml

Takes opus data-dict.yaml to determine types (int, float, string, etc).
"""

import xml.etree.ElementTree as ET
import pyarrow as pa
import pyarrow.parquet as pq
import yaml
import sys
import time
import os

def get_type_for_field(field_name, record_type, dict_spec):
    """Get opus type spec for a field."""
    if record_type not in dict_spec:
        return None

    record = dict_spec[record_type]
    if 'columns' not in record:
        return None

    column = record['columns'].get(field_name)
    if not column:
        return None

    return column.get('type')

def cast_value(value, field_type):
    """Cast a string value to the appropriate Python type."""
    if not value or value.strip() == '':
        return None

    value = value.strip()

    if field_type == 'number(quantity)' or field_type == 'number':
        try:
            return float(value)
        except (ValueError, TypeError):
            return None

    elif field_type == 'number(ordinal)' or field_type == 'number(id)':
        try:
            return int(value)
        except (ValueError, TypeError):
            return None

    elif field_type == 'enum' or field_type == 'string':
        return value

    else:
        return value

def xml_to_parquet(xml_path, parquet_path, dict_spec):
    """Convert XML to Parquet with type casting."""
    start_time = time.time()

    # Parse XML
    tree = ET.parse(xml_path)
    root = tree.getroot()

    # Get namespace
    ns = ''
    if '}' in root.tag:
        ns = root.tag.split('}')[0] + '}'

    # Get records
    records = list(root)
    if not records:
        print("ERROR: No records found in XML", file=sys.stderr)
        return False

    # Determine record type from tag
    record_tag = records[0].tag
    if '}' in record_tag:
        record_type = record_tag.split('}')[1]
    else:
        record_type = record_tag

    # Remove the "Cls_DatrasExchange_" prefix to get the type (HH, HL, CA, LT)
    if record_type.startswith('Cls_DatrasExchange_'):
        record_type = record_type.replace('Cls_DatrasExchange_', '')

    print(f"Found {len(records)} records of type {record_type}", file=sys.stderr)

    # Extract field names from first record
    field_names = []
    for child in records[0]:
        tag = child.tag
        if '}' in tag:
            tag = tag.split('}')[1]
        field_names.append(tag)

    print(f"Found {len(field_names)} fields", file=sys.stderr)

    # Extract data with type casting
    typed_data = {field: [] for field in field_names}

    for record in records:
        for field in field_names:
            # Find element with or without namespace
            elem = record.find(f'{ns}{field}')
            if elem is None:
                elem = record.find(field)

            value = (elem.text or '').strip() if elem is not None else ''

            # Get type spec from opus dict
            field_type = get_type_for_field(field, record_type, dict_spec)

            # Cast value
            typed_value = cast_value(value, field_type)
            typed_data[field].append(typed_value)

    # Build PyArrow table
    arrays = []
    schema_fields = []

    for field in field_names:
        values = typed_data[field]

        # Infer type from values
        field_type = get_type_for_field(field, record_type, dict_spec)

        if field_type in ['number(quantity)', 'number']:
            # Float type
            array = pa.array(values, type=pa.float64())
            schema_fields.append(pa.field(field, pa.float64()))
        elif field_type in ['number(ordinal)', 'number(id)']:
            # Integer type
            array = pa.array(values, type=pa.int64())
            schema_fields.append(pa.field(field, pa.int64()))
        else:
            # String type (default)
            array = pa.array(values, type=pa.string())
            schema_fields.append(pa.field(field, pa.string()))

        arrays.append(array)

    schema = pa.schema(schema_fields)
    table = pa.table({field: arrays[i] for i, field in enumerate(field_names)}, schema=schema)

    # Write parquet
    pq.write_table(table, parquet_path, compression='snappy')

    elapsed = time.time() - start_time
    file_size = os.path.getsize(parquet_path) / 1024 / 1024

    print(f"Wrote {len(records)} rows to {parquet_path} in {elapsed:.2f}s | Parquet size: {file_size:.1f} MB",
          file=sys.stderr)
    return True

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: python3 xml_to_parquet.py input.xml output.parquet dict.yaml",
              file=sys.stderr)
        sys.exit(1)

    xml_path, parquet_path, dict_path = sys.argv[1], sys.argv[2], sys.argv[3]

    # Load opus dict
    try:
        with open(dict_path) as f:
            dict_spec = yaml.safe_load(f) or {}
    except Exception as e:
        print(f"ERROR: Failed to load dict: {e}", file=sys.stderr)
        sys.exit(1)

    # Convert
    success = xml_to_parquet(xml_path, parquet_path, dict_spec)
    sys.exit(0 if success else 1)
