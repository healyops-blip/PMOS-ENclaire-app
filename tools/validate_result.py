import os
import sys
import json

def validate(root_dir: str) -> int:
    truth_map_path = os.path.join(root_dir, 'truth_mapping.json')
    if not os.path.exists(truth_map_path):
        print(f"ERROR: truth_mapping.json not found in {root_dir}")
        return 1

    # load mapping
    with open(truth_map_path, 'r', encoding='utf-8') as f:
        mapping = json.load(f)

    # uniqueness of keys
    keys = list(mapping.keys())
    if len(set(keys)) != len(keys):
        print("ERROR: duplicate keys found in truth_mapping.json")
        return 2

    # check existence of files and minimal schema
    missing = []
    schema_issues = []
    for fname, meta in mapping.items():
        truth_rel = meta.get('truth_file')
        if not truth_rel:
            schema_issues.append((fname, 'missing truth_file in mapping entry'))
            continue
        truth_path = os.path.join(root_dir, truth_rel)
        img_path = os.path.join(os.path.dirname(truth_path), os.path.basename(truth_path).replace('.json', '.jpg'))
        if not os.path.exists(truth_path):
            missing.append(('truth', truth_path))
        if not os.path.exists(img_path):
            missing.append(('image', img_path))
        # validate json schema minimal
        try:
            with open(truth_path, 'r', encoding='utf-8') as tf:
                j = json.load(tf)
            for field in ['doc_id','hospital','department','visit_date','diagnosis_summary','medical_advice','examinations','medication_suggestions','original_file_name']:
                if field not in j:
                    schema_issues.append((fname, f'missing field: {field}'))
        except Exception as e:
            schema_issues.append((fname, f'read_error: {e}'))

    print(f"Total entries: {len(mapping)}")
    print(f"Missing files: {len(missing)}")
    if missing:
        for kind, path in missing[:5]:
            print(f"  - missing {kind}: {path}")
    print(f"Schema issues: {len(schema_issues)}")
    if schema_issues:
        for item in schema_issues[:5]:
            print("  -", item)

    ok = (not missing) and (not schema_issues)
    print("Validation:", "OK" if ok else "FAILED")
    return 0 if ok else 3

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python tools/validate_result.py <result_dir>")
        sys.exit(1)
    sys.exit(validate(sys.argv[1]))
