"""影像文字报告 - 数据生成器"""
import random
from datetime import datetime, timedelta
from .names import get_patient_name


def generate_data():
    """生成影像文字报告的泛化数据"""
    now = datetime.now()

    data = {
        # 患者信息
        "exam_date": (now - timedelta(days=random.randint(1, 30))).strftime("%Y-%m-%d"),
        "patient_id": f"P{random.randint(100000, 999999)}",
        # 姓名统一由 report_types.names 生成（中性、好听，避免“女”旁与过度男性化字）
        "name": get_patient_name(gender="女"),
        "age": random.randint(20, 55),
        "gender": "女",
        "doctor": random.choice([
            "张医生", "李医生", "王医生", "刘医生", "赵医生", "陈医生",
            "周医生", "吴医生", "郑医生", "孙医生"
        ]),

        # 右卵巢
        "right_ovary_length": random.randint(25, 40),
        "right_ovary_width": random.randint(15, 25),
        "right_ovary_height": random.randint(20, 35),
        "follicle_count_right": random.randint(5, 30),

        # 左卵巢
        "left_ovary_length": random.randint(25, 40),
        "left_ovary_width": random.randint(15, 25),
        "left_ovary_height": random.randint(20, 35),
        "follicle_count_left": random.randint(5, 30),

        # 其他
        "pelvic_effusion": random.choice(["无", "少量", "中等量", "大量"]),
        # 影像印象（严格限定为PCOS相关）
        "impression": random.choice([
            "双侧卵巢多囊样改变",
            "右侧卵巢多囊样改变",
            "左侧卵巢多囊样改变",
        ]),
        # 建议（限定为PCOS管理相关）
        "recommendation": random.choice([
            "建议结合临床与性激素水平评估PCOS情况，必要时复查",
            "建议内分泌与妇科联合随诊，进行PCOS相关管理",
            "建议规律作息、控制体重，开展生活方式干预（饮食+运动）",
            "建议3-6个月后复查超声及相关激素，动态评估PCOS",
            "建议计划妊娠者提前评估PCOS相关风险并制定方案",
            "建议记录月经周期变化，如异常及时就诊，评估PCOS进展",
            "建议必要时完善性激素六项、胰岛素抵抗评估，完善PCOS诊疗",
        ]),
    }
    refresh_text_lines(data)
    return data


def refresh_text_lines(data):
    """根据当前数值重建影像报告的完整句/完整行文本。"""
    data["right_ovary_line"] = (
        f"右卵巢：呈多囊样改变，大小测量（mm）:"
        f"{data['right_ovary_length']}*{data['right_ovary_width']}*{data['right_ovary_height']}。"
        f"基础卵泡数目:>{data['follicle_count_right']}个。"
    )
    data["right_follicle_line"] = "卵泡：未见优势卵泡。"
    data["left_ovary_line"] = (
        f"左卵巢：呈多囊样改变，大小测量（mm）:"
        f"{data['left_ovary_length']}*{data['left_ovary_width']}*{data['left_ovary_height']}。"
        f"基础卵泡数目:>{data['follicle_count_left']}个。"
    )
    data["left_follicle_line"] = "卵泡：未见优势卵泡。"
    data["pelvic_effusion_line"] = f"子宫直肠陷窝积液：{data['pelvic_effusion']}"
    data["impression_line"] = f"超声提示：{data['impression']}。"
    data["recommendation_line"] = data["recommendation"]
    return data


def get_fields():
    """返回字段定义列表"""
    return [
        {
            "name": "hospital_name",
            "bbox": [56, 30, 860, 68],
            "template": "{hospital}",
            "font_size": 24,
            "color": [28, 88, 145]
        },
        {
            "name": "title",
            "bbox": [56, 76, 560, 124],
            "template": "超声影像文字报告",
            "font_size": 34,
            "color": [28, 88, 145]
        },
        {
            "name": "exam_date",
            "bbox": [780, 145, 1195, 176],
            "template": "检查日期：{exam_date}",
            "font_size": 20
        },
        {
            "name": "patient_id",
            "bbox": [810, 230, 1195, 266],
            "template": "病历号：{patient_id}",
            "font_size": 20
        },
        {
            "name": "name",
            "bbox": [76, 228, 780, 266],
            "template": "姓名：{name}        性别：{gender}        年龄：{age}岁",
            "font_size": 20
        },
        {
            "name": "doctor",
            "bbox": [76, 296, 1180, 332],
            "template": "申请医生：{doctor}        科室：生殖科        检查项目：妇科超声",
            "font_size": 20
        },
        {
            "name": "section_findings",
            "bbox": [76, 416, 400, 454],
            "template": "超声所见",
            "font_size": 22,
            "color": [28, 88, 145]
        },
        {
            "name": "uterus_line",
            "bbox": [76, 780, 1120, 820],
            "template": "子宫：前位，形态规则，肌层回声尚均匀，内膜线居中。",
            "font_size": 22
        },
        {
            "name": "adnexa_line",
            "bbox": [76, 825, 1120, 865],
            "template": "附件区：双侧附件区未见明显异常包块回声。",
            "font_size": 22
        },
        {
            "name": "right_ovary_line",
            # 整句覆盖，不做数字级贴片，避免旧句残留/新数字错位。
            "bbox": [76, 880, 1165, 920],
            "template": "{right_ovary_line}",
            "font_size": 22
        },
        {
            "name": "right_follicle_line",
            "bbox": [76, 925, 800, 965],
            "template": "{right_follicle_line}",
            "font_size": 22
        },
        {
            "name": "left_ovary_line",
            # 整句覆盖，不做数字级贴片，避免旧句残留/新数字错位。
            "bbox": [76, 980, 1165, 1020],
            "template": "{left_ovary_line}",
            "font_size": 22
        },
        {
            "name": "left_follicle_line",
            "bbox": [76, 1025, 800, 1065],
            "template": "{left_follicle_line}",
            "font_size": 22
        },
        {
            "name": "pelvic_effusion_line",
            "bbox": [760, 1025, 1165, 1065],
            "template": "{pelvic_effusion_line}",
            "font_size": 22
        },
        {
            "name": "section_result",
            "bbox": [76, 1151, 400, 1189],
            "template": "超声提示与建议",
            "font_size": 22,
            "color": [28, 88, 145]
        },
        {
            "name": "impression_line",
            "bbox": [76, 1200, 1120, 1238],
            "template": "{impression_line}",
            "font_size": 22
        },
        {
            "name": "recommendation_line",
            "bbox": [76, 1258, 1165, 1298],
            "template": "{recommendation_line}",
            "font_size": 21
        },
        {
            "name": "footer_doctor",
            "bbox": [76, 1410, 520, 1452],
            "template": "报告医师：{doctor}",
            "font_size": 20
        },
        {
            "name": "footer_date",
            "bbox": [760, 1410, 1180, 1452],
            "template": "报告时间：{exam_date}",
            "font_size": 20
        },
        {
            "name": "footer_note",
            "bbox": [56, 1650, 1180, 1690],
            "template": "本报告仅供临床参考，请结合病史、体征及其他检查综合判断。",
            "font_size": 18,
            "color": [45, 88, 130]
        }
    ]