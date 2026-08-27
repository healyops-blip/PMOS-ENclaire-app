"""医嘱_处方 - 数据生成器"""
import os
import json
import random
from datetime import datetime, timedelta
from .names import get_patient_name


def _load_pomi_mapping():
    try:
        base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        path = os.path.join(base, 'data', 'pomi_mapping.json')
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return []

POMI = _load_pomi_mapping()


def _dose_total_for_form(form, usage):
    """按剂型生成更自然的展示用量/总量，避免注射剂出现“片”。"""
    text = f"{form} {usage}"
    if "注射" in text or "针" in text:
        return random.choice(["每次1支", "按医嘱"]), random.choice(["1支", "2支", "4支"])
    if "粉" in text or "袋" in text:
        return random.choice(["每次1袋", "按医嘱"]), random.choice(["14袋", "20袋", "30袋"])
    if "胶囊" in text or "粒" in text:
        return random.choice(["每次1粒", "按医嘱"]), random.choice(["14粒", "20粒", "28粒"])
    return random.choice(["每次1片", "按医嘱"]), random.choice(["7片", "14片", "20片", "28片", "1盒"])


def generate_data():
    """生成医嘱处方的泛化数据"""
    now = datetime.now()

    # 从 Pomi 映射中固定选择3种药品（仅PCOS相关类别）。
    # 处方模板本身有3个药品位置；如果只生成1-2种药，clean base 会擦空剩余位置，
    # 视觉上就像“缺失/空白”。因此这里始终填满3个药位。
    pcos_items = [x for x in POMI if x.get('category') in ('PCOS管理相关', '生育及备孕', '补充剂')]
    # 若映射为空则提供后备（不会为空时）
    if not pcos_items:
        pcos_items = [
            {"standard_name": "二甲双胍", "strengths": ["0.5g"], "frequency_options": ["每日2-3次"], "days_options": ["长期"], "usage_options": ["口服"]}
        ]
    if len(pcos_items) >= 3:
        meds_sel = random.sample(pcos_items, 3)
    else:
        meds_sel = [random.choice(pcos_items) for _ in range(3)]

    data = {
        # 患者信息
        "exam_date": (now - timedelta(days=random.randint(1, 30))).strftime("%Y-%m-%d"),
        "patient_id": f"PR{random.randint(10000, 99999)}",
        # 姓名统一由 report_types.names 生成
        "name": get_patient_name(gender="女"),
        "age": random.randint(20, 55),
        "gender": "女",
        "doctor": random.choice([
            "张医生", "李医生", "王医生", "刘医生", "赵医生", "陈医生",
            "周医生", "吴医生", "郑医生", "孙医生"
        ]),

        # 处方药品（从 Pomi 映射映射）
        "med1_name": meds_sel[0]["standard_name"],
        "med1_spec": random.choice(meds_sel[0].get("strengths", [""])),
        "med1_freq": random.choice(meds_sel[0].get("frequency_options", [""])),
        "med1_days": random.choice(meds_sel[0].get("days_options", [""])),
        "med1_usage": random.choice(meds_sel[0].get("usage_options", ["口服"])),
        "med1_instruction": meds_sel[0].get("instruction", ""),
        "med2_name": meds_sel[1]["standard_name"],
        "med2_spec": random.choice(meds_sel[1].get("strengths", [""])),
        "med2_freq": random.choice(meds_sel[1].get("frequency_options", [""])),
        "med2_days": random.choice(meds_sel[1].get("days_options", [""])),
        "med2_usage": random.choice(meds_sel[1].get("usage_options", ["口服"])),
        "med2_instruction": meds_sel[1].get("instruction", ""),
        "med3_name": meds_sel[2]["standard_name"],
        "med3_spec": random.choice(meds_sel[2].get("strengths", [""])),
        "med3_freq": random.choice(meds_sel[2].get("frequency_options", [""])),
        "med3_days": random.choice(meds_sel[2].get("days_options", [""])),
        "med3_usage": random.choice(meds_sel[2].get("usage_options", ["口服"])),
        "med3_instruction": meds_sel[2].get("instruction", ""),

        # 诊断
        "diagnosis": random.choice([
            "多囊卵巢综合征",
            "多囊卵巢综合征（代谢异常需评估）",
        ]),

        # 剂量相关
        "dose_count": random.randint(1, 4),
        "dose_unit": random.choice(["片", "粒", "支", "支"]),
        "total_amount": random.randint(1, 100),
        "usage": random.choice(
            (meds_sel[0].get("usage_options") or ["口服"]) +
            ((meds_sel[1].get("usage_options") if len(meds_sel) > 1 else []) or []) +
            ((meds_sel[2].get("usage_options") if len(meds_sel) > 2 else []) or [])
        ),
    }

    # 移动端病历页的处方卡片需要展示“药品/用法/用量/疗程/总量”。
    # 这些字段不追求医学剂量精确，只用于与截图式样一致的可读文本。
    for i, med in enumerate(meds_sel, 1):
        alias = random.choice(med.get("aliases", []) or [data[f"med{i}_name"]])
        form = random.choice(med.get("dosage_forms", []) or ["片剂"])
        dose, total = _dose_total_for_form(form, data[f"med{i}_usage"])
        data[f"med{i}_display"] = f"{data[f'med{i}_name']}（{alias}） {data[f'med{i}_spec']}"
        data[f"med{i}_form"] = form
        data[f"med{i}_dose"] = dose
        data[f"med{i}_total"] = total

    data["treatment_plan"] = random.choice([
        "生活方式干预，规律复诊评估",
        "调整月经周期，监测排卵及代谢指标",
        "控制体重，配合药物治疗及随访",
    ])
    return data


def get_fields():
    """返回字段定义列表"""
    return [
        # 顶部移动端导航/状态栏（原图是病历小程序截图，不是传统纸质处方笺）
        {"name": "status_time", "bbox": [70, 55, 180, 104], "template": "21:51", "font_size": 28, "method": "none", "color": [90, 90, 90]},
        {"name": "nav_back", "bbox": [48, 162, 110, 230], "template": "＜", "font_size": 46, "method": "none"},
        {"name": "nav_title", "bbox": [520, 176, 740, 238], "template": "病历", "font_size": 48, "method": "none"},
        {"name": "nav_menu", "bbox": [932, 168, 1210, 238], "template": "...       ◎", "font_size": 38, "method": "none"},
        {
            "name": "title",
            "bbox": [258, 326, 390, 392],
            "template": "病历",
            "font_size": 52,
            "method": "none"
        },
        {"name": "tab2", "bbox": [730, 330, 1160, 392], "template": "生命体征及过敏史", "font_size": 42, "method": "none", "color": [95, 95, 95]},
        {"name": "section_treatment", "bbox": [102, 512, 356, 580], "template": "治疗计划", "font_size": 44, "method": "none"},
        {"name": "treatment_plan", "bbox": [106, 665, 1128, 750], "template": "{treatment_plan}", "font_size": 42, "method": "none"},
        {"name": "section_rx", "bbox": [102, 852, 230, 920], "template": "处方", "font_size": 44, "method": "none"},
        {
            "name": "patient_info",
            "bbox": [104, 918, 1128, 952],
            "template": "姓名：{name}    性别：{gender}    年龄：{age}岁    病历号：{patient_id}",
            "font_size": 22,
            "method": "none",
            "color": [120, 120, 120]
        },
        {
            "name": "diagnosis",
            "bbox": [104, 952, 1128, 986],
            "template": "临床诊断：{diagnosis}",
            "font_size": 22,
            "method": "none",
            "color": [120, 120, 120]
        },
        {
            "name": "med1",
            "bbox": [106, 1028, 1112, 1086],
            "template": "药品    {med1_display}    >",
            "font_size": 32,
            "method": "none"
        },
        {
            "name": "med1_detail",
            "bbox": [106, 1154, 1060, 1208],
            "template": "用法    {med1_usage} {med1_form}",
            "font_size": 30,
            "method": "none",
            "color": [70, 70, 70]
        },
        {"name": "med1_dose", "bbox": [106, 1240, 1060, 1294], "template": "用量    {med1_dose}，{med1_freq}", "font_size": 30, "method": "none", "color": [70, 70, 70]},
        {"name": "med1_days", "bbox": [106, 1326, 1060, 1380], "template": "疗程    {med1_days}", "font_size": 30, "method": "none", "color": [70, 70, 70]},
        {"name": "med1_total", "bbox": [106, 1412, 1060, 1466], "template": "总量    {med1_total}", "font_size": 30, "method": "none", "color": [70, 70, 70]},
        {
            "name": "med2",
            "bbox": [106, 1619, 1112, 1677],
            "template": "药品    {med2_display}    >",
            "font_size": 30,
            "method": "none"
        },
        {
            "name": "med2_detail",
            "bbox": [106, 1745, 1060, 1799],
            "template": "用法    {med2_usage} {med2_form}",
            "font_size": 28,
            "method": "none",
            "color": [70, 70, 70]
        },
        {"name": "med2_dose", "bbox": [106, 1831, 1060, 1885], "template": "用量    {med2_dose}，{med2_freq}", "font_size": 28, "method": "none", "color": [70, 70, 70]},
        {"name": "med2_days", "bbox": [106, 1917, 1060, 1971], "template": "疗程    {med2_days}", "font_size": 28, "method": "none", "color": [70, 70, 70]},
        {"name": "med2_total", "bbox": [106, 2003, 1060, 2057], "template": "总量    {med2_total}", "font_size": 28, "method": "none", "color": [70, 70, 70]},
        {
            "name": "med3",
            "bbox": [106, 2210, 1112, 2268],
            "template": "药品    {med3_display}    >",
            "font_size": 30,
            "method": "none"
        },
        {
            "name": "med3_detail",
            "bbox": [106, 2336, 1060, 2390],
            "template": "用法    {med3_usage} {med3_form}",
            "font_size": 28,
            "method": "none",
            "color": [70, 70, 70]
        },
        {"name": "med3_dose", "bbox": [106, 2422, 1060, 2476], "template": "用量    {med3_dose}，{med3_freq}", "font_size": 28, "method": "none", "color": [70, 70, 70]},
        {"name": "med3_days", "bbox": [106, 2508, 1060, 2562], "template": "疗程    {med3_days}    总量    {med3_total}", "font_size": 28, "method": "none", "color": [70, 70, 70]},
        {"name": "doctor", "bbox": [106, 2620, 420, 2670], "template": "医生：{doctor}", "font_size": 24, "method": "none"},
        {
            "name": "signature",
            "bbox": [1088, 2555, 1190, 2658],
            "template": "审核人",
            "font_size": 18,
            "method": "none"
        }
    ]