"""化验_检测报告 - 数据生成器"""
import random
from datetime import datetime, timedelta
from .names import get_patient_name


def generate_data():
    """生成化验检测报告的泛化数据"""
    now = datetime.now()

    return {
        # 患者信息
        "exam_date": (now - timedelta(days=random.randint(1, 30))).strftime("%Y-%m-%d"),
        "patient_id": f"LA{random.randint(10000, 99999)}",
        # 姓名统一由 report_types.names 生成
        "name": get_patient_name(gender="女"),
        "age": random.randint(20, 55),
        "gender": "女",
        "doctor": random.choice([
            "张医生", "李医生", "王医生", "刘医生", "赵医生", "陈医生",
            "周医生", "吴医生", "郑医生", "孙医生"
        ]),

        # 检测项目数值
        "wbc": random.randint(4, 12),           # 白细胞
        "rbc": random.randint(4, 6),            # 红细胞
        "hgb": random.randint(110, 180),        # 血红蛋白
        "plt": random.randint(100, 350),        # 血小板
        "alt": random.randint(5, 45),           # 谷丙转氨酶
        "ast": random.randint(5, 45),           # 谷草转氨酶
        "tbil": random.randint(3, 25),          # 总胆红素
        "dbil": random.randint(0, 10),          # 直接胆红素
        "bun": random.randint(2, 8),            # 尿素氮
        "crea": random.randint(40, 120),        # 肌酐
        "glu": random.randint(3, 8),            # 空腹血糖
        "cho": random.randint(3, 6),            # 总胆固醇
        "tg": round(random.uniform(0.5, 2.5), 1),         # 甘油三酯
        "hdl": round(random.uniform(0.8, 2.0), 1),        # 高密度脂蛋白
        "ldl": round(random.uniform(2, 4), 1),            # 低密度脂蛋白
        "ca": round(random.uniform(2, 3), 1),             # 钙
        "k": round(random.uniform(3.5, 5.5), 1),          # 钾
        "na": random.randint(130, 150),         # 钠
        "cl": random.randint(95, 110),          # 氯
        "tsh": round(random.uniform(0.2, 5.0), 2),        # 促甲状腺激素
        "ft3": round(random.uniform(2.0, 5.0), 1),        # 游离T3
        "ft4": round(random.uniform(10, 25), 1),          # 游离T4

        # 备注/建议（PCOS 相关文本，便于下游 truth 的 medical_advice 使用）
        "advice": random.choice([
            "备注：建议结合PCOS（多囊卵巢综合征）相关评估，按需随访",
            "备注：建议结合临床，评估PCOS相关代谢与激素水平，定期复查",
            "备注：如为PCOS管理阶段，建议记录月经周期并按医嘱复诊",
            "备注：建议生活方式干预（饮食+运动），必要时与内分泌科联合随访",
        ]),
    }


def get_fields():
    """返回字段定义列表"""
    left = 56
    top = 388
    header_h = 48
    row_h = 60
    cols = [left, 120, 430, 590, 745, 930, 1200]

    lab_items = [
        ("wbc", "白细胞计数", "WBC", "{wbc}", "×10^9/L", "4-12"),
        ("rbc", "红细胞计数", "RBC", "{rbc}", "×10^12/L", "4-6"),
        ("hgb", "血红蛋白", "HGB", "{hgb}", "g/L", "110-180"),
        ("plt", "血小板计数", "PLT", "{plt}", "×10^9/L", "100-350"),
        ("alt", "谷丙转氨酶", "ALT", "{alt}", "U/L", "5-45"),
        ("ast", "谷草转氨酶", "AST", "{ast}", "U/L", "5-45"),
        ("tbil", "总胆红素", "TBIL", "{tbil}", "μmol/L", "3-25"),
        ("crea", "肌酐", "CREA", "{crea}", "μmol/L", "40-120"),
        ("glu", "空腹血糖", "GLU", "{glu}", "mmol/L", "3-8"),
        ("cho", "总胆固醇", "CHO", "{cho}", "mmol/L", "3-6"),
        ("tg", "甘油三酯", "TG", "{tg}", "mmol/L", "0.5-2.5"),
        ("hdl", "高密度脂蛋白", "HDL", "{hdl}", "mmol/L", "0.8-2.0"),
        ("ldl", "低密度脂蛋白", "LDL", "{ldl}", "mmol/L", "2-4"),
    ]

    fields = [
        {
            "name": "title",
            "bbox": [56, 28, 720, 92],
            "template": "检验报告单",
            "font_size": 34,
            "color": [30, 96, 150]
        },
        {
            "name": "exam_date",
            "bbox": [780, 118, 1195, 160],
            "template": "报告日期：{exam_date}",
            "font_size": 20
        },
        {
            "name": "patient_info",
            "bbox": [76, 218, 1180, 260],
            "template": "姓名：{name}        性别：{gender}        年龄：{age}岁        病历号：{patient_id}",
            "font_size": 20
        },
        {
            "name": "doctor",
            "bbox": [76, 283, 1180, 322],
            "template": "申请医生：{doctor}        标本类型：血液        检验科室：生化/内分泌实验室",
            "font_size": 20
        },
        {"name": "table_header_no", "bbox": [cols[0] + 10, top + 7, cols[1] - 8, top + header_h - 7], "template": "序号", "font_size": 18},
        {"name": "table_header_item", "bbox": [cols[1] + 16, top + 7, cols[2] - 8, top + header_h - 7], "template": "项目名称", "font_size": 18},
        {"name": "table_header_code", "bbox": [cols[2] + 16, top + 7, cols[3] - 8, top + header_h - 7], "template": "英文缩写", "font_size": 18},
        {"name": "table_header_result", "bbox": [cols[3] + 16, top + 7, cols[4] - 8, top + header_h - 7], "template": "结果", "font_size": 18},
        {"name": "table_header_unit", "bbox": [cols[4] + 16, top + 7, cols[5] - 8, top + header_h - 7], "template": "单位", "font_size": 18},
        {"name": "table_header_ref", "bbox": [cols[5] + 16, top + 7, cols[6] - 8, top + header_h - 7], "template": "参考范围", "font_size": 18},
        {
            "name": "advice",
            "bbox": [76, 1255, 1180, 1328],
            "template": "{advice}",
            "font_size": 18
        }
    ]

    for idx, (key, item_name, code, value_template, unit, ref) in enumerate(lab_items, 1):
        y1 = top + header_h + (idx - 1) * row_h + 10
        y2 = y1 + 38
        fields.extend([
            {"name": f"{key}_no", "bbox": [cols[0] + 18, y1, cols[1] - 8, y2], "template": f"{idx}", "font_size": 18},
            {"name": f"{key}_name", "bbox": [cols[1] + 16, y1, cols[2] - 8, y2], "template": item_name, "font_size": 18},
            {"name": f"{key}_code", "bbox": [cols[2] + 16, y1, cols[3] - 8, y2], "template": code, "font_size": 18},
            {"name": key, "bbox": [cols[3] + 16, y1, cols[4] - 8, y2], "template": value_template, "font_size": 18},
            {"name": f"{key}_unit", "bbox": [cols[4] + 16, y1, cols[5] - 8, y2], "template": unit, "font_size": 18},
            {"name": f"{key}_ref", "bbox": [cols[5] + 16, y1, cols[6] - 8, y2], "template": ref, "font_size": 18},
        ])

    return fields