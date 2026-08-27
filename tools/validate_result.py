import os
import sys
import json
import re

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
    doc_ids = []
    for fname, meta in mapping.items():
        truth_rel = meta.get('truth_file')
        if not truth_rel:
            schema_issues.append((fname, 'missing truth_file in mapping entry'))
            continue
        truth_path = os.path.join(root_dir, truth_rel)
        # New mapping keys are report-relative image paths, e.g.
        # "医嘱_处方/case_00003.jpg".  Older mappings used only the basename.
        # Prefer the key path when it contains a directory; otherwise infer the
        # image path from truth_file for backward compatibility.
        normalized_key = fname.replace('\\', os.sep).replace('/', os.sep)
        if os.path.dirname(normalized_key):
            img_path = os.path.join(root_dir, normalized_key)
        else:
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
            if 'doc_id' in j:
                doc_ids.append(j.get('doc_id') or '')
            if meta.get('report_type') == '医嘱_处方' or os.path.basename(os.path.dirname(truth_path)) == '医嘱_处方':
                meds = j.get('medication_suggestions', [])
                if len(meds) != 3:
                    schema_issues.append((fname, f'医嘱_处方 medication_suggestions must contain exactly 3 meds, got {len(meds)}'))
                required = ['药品', '用法', '用量', '疗程', '总量']
                for idx, med in enumerate(meds, 1):
                    source_text = med.get('source_text', '')
                    missing_kw = [kw for kw in required if kw not in source_text]
                    if missing_kw:
                        schema_issues.append((fname, f'医嘱_处方 med{idx} source_text missing {missing_kw}: {source_text}'))
            if meta.get('report_type') == '影像文字报告' or os.path.basename(os.path.dirname(truth_path)) == '影像文字报告':
                exams = j.get('examinations', [])
                by_name = {e.get('item_name'): e for e in exams if isinstance(e, dict)}
                for required_name in ['右卵巢', '右侧基础卵泡', '左卵巢', '左侧基础卵泡', '盆腔积液']:
                    if required_name not in by_name:
                        schema_issues.append((fname, f'影像文字报告 missing examination item: {required_name}'))
                for side_item, follicle_item, side_prefix in [('右卵巢', '右侧基础卵泡', '右卵巢'), ('左卵巢', '左侧基础卵泡', '左卵巢')]:
                    side_exam = by_name.get(side_item, {})
                    follicle_exam = by_name.get(follicle_item, {})
                    source_text = side_exam.get('source_text') or follicle_exam.get('source_text') or ''
                    expected_value = str(side_exam.get('value', ''))
                    expected_count = str(follicle_exam.get('value', ''))
                    if not source_text:
                        schema_issues.append((fname, f'影像文字报告 {side_item} missing full-line source_text'))
                    if side_prefix not in source_text or '大小测量' not in source_text or '基础卵泡数目' not in source_text:
                        schema_issues.append((fname, f'影像文字报告 {side_item} source_text is not a full rewritten sentence: {source_text}'))
                    if expected_value and expected_value not in source_text:
                        schema_issues.append((fname, f'影像文字报告 {side_item} value not found in source_text: value={expected_value}, source={source_text}'))
                    if expected_count and not re.search(rf'>\s*{re.escape(expected_count)}\s*个', source_text):
                        schema_issues.append((fname, f'影像文字报告 {follicle_item} count not found in full source_text: count={expected_count}, source={source_text}'))
                effusion = by_name.get('盆腔积液', {})
                effusion_source = effusion.get('source_text', '')
                if '子宫直肠陷窝积液' not in effusion_source or str(effusion.get('value', '')) not in effusion_source:
                    schema_issues.append((fname, f'影像文字报告 盆腔积液 source_text invalid: {effusion_source}'))
                if not j.get('diagnosis_summary'):
                    schema_issues.append((fname, '影像文字报告 diagnosis_summary must be non-empty'))
                if not j.get('medical_advice'):
                    schema_issues.append((fname, '影像文字报告 medical_advice must be non-empty'))
            if meta.get('report_type') == '化验_检测报告' or os.path.basename(os.path.dirname(truth_path)) == '化验_检测报告':
                exams = j.get('examinations', [])
                if len(exams) != 13:
                    schema_issues.append((fname, f'化验_检测报告 examinations must contain 13 table rows, got {len(exams)}'))
                for idx, exam in enumerate(exams, 1):
                    for field in ['item_name', 'value', 'unit', 'reference_range']:
                        if not str(exam.get(field, '')).strip():
                            schema_issues.append((fname, f'化验_检测报告 row{idx} missing {field}: {exam}'))
                if not j.get('medical_advice'):
                    schema_issues.append((fname, '化验_检测报告 medical_advice must be non-empty'))
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
    # enforce doc_id uniqueness across all entries
    unique_ok = len([d for d in doc_ids if d]) == len(set([d for d in doc_ids if d]))
    if not unique_ok:
        print("ERROR: duplicate doc_id (patient_id) detected across results")
        ok = False
    print("Validation:", "OK" if ok else "FAILED")
    return 0 if ok else 3

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python tools/validate_result.py <result_dir>")
        sys.exit(1)
    sys.exit(validate(sys.argv[1]))
