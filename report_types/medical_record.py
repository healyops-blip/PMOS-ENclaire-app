"""门诊病历_就诊记录 - 数据生成器"""
import random
from datetime import datetime, timedelta
from .names import get_patient_name


# 症状库
# 症状库（严格限制为PCOS相关症状与表现）
SYMPTOMS = [
    "月经不调", "稀发月经", "闭经", "排卵异常", "不孕",
    "痤疮", "多毛", "体重增加", "胰岛素抵抗", "雄激素增高",
]

# 诊断库
DIAGNOSES = [
    "多囊卵巢综合征",
    "多囊卵巢综合征（不排卵型）",
    "多囊卵巢综合征（高雄激素型）",
    "多囊卵巢综合征（代谢异常需评估）",
]


def generate_data():
    """生成门诊病历的泛化数据"""
    now = datetime.now()

    # 随机选择2-5个症状
    symptom_count = random.randint(2, 5)
    symptoms = random.sample(SYMPTOMS, symptom_count)

    return {
        # 患者信息
        "exam_date": (now - timedelta(days=random.randint(1, 30))).strftime("%Y-%m-%d"),
        "patient_id": f"MR{random.randint(10000, 99999)}",
        # 姓名统一由 report_types.names 生成
        "name": get_patient_name(gender="女"),
        "age": random.randint(20, 55),
        "gender": "女",
        "doctor": random.choice([
            "张医生", "李医生", "王医生", "刘医生", "赵医生", "陈医生",
            "周医生", "吴医生", "郑医生", "孙医生"
        ]),

        # 症状
        "symptom1": symptoms[0],
        "symptom2": symptoms[1],
        "symptom3": symptoms[2] if len(symptoms) > 2 else "",
        "symptom4": symptoms[3] if len(symptoms) > 3 else "",
        "symptom5": symptoms[4] if len(symptoms) > 4 else "",

        # 诊断
        "diagnosis": random.choice(DIAGNOSES),

        # 体征 - 按要求将体温严格控制在 37.3~37.8 范围，保留1位小数
        "temp": round(random.uniform(37.3, 37.8), 1),
        "hr": random.randint(50, 120),
        "bp": f"{random.randint(90, 150)}/{random.randint(50, 100)}",
        "rr": random.randint(12, 25),

        # 处理
        "treatment": random.choice([
            "建议生活方式干预（饮食+运动），体重管理，评估PCOS相关风险",
            "建议完善性激素六项与胰岛素抵抗评估，规范随诊管理PCOS",
            "建议规律作息，记录月经周期，按需评估排卵情况",
            "建议内分泌与妇科联合随诊，必要时药物治疗",
            "建议计划妊娠者进行孕前评估与个体化方案制定（PCOS）",
            "建议阶段性复查超声及激素水平，动态评估PCOS管理效果",
        ]),
        "followup_days": random.randint(1, 30),
        "advice": random.choice([
            "注意记录月经周期与症状变化，按计划复诊，评估PCOS管理效果",
            "建议控制体重与生活方式干预，如有异常及时就诊（PCOS）",
            "建议定期复查激素与超声，评估排卵与代谢情况（PCOS）",
            "建议心理与生活方式支持，缓解焦虑，持续管理PCOS",
            "遵医嘱服药与随访，出现不适或周期异常及时复诊（PCOS）",
        ]),

        # 费用
        "total_cost": random.randint(50, 5000),
    }


def get_fields():
    """返回字段定义列表"""
    return [
        {
            "name": "title",
            "bbox": [55, 43, 1202, 151],
            "template": "门诊病历",
            "font_size": 36
        },
        {
            "name": "patient_info",
            "bbox": [58, 159, 1200, 186],
            "template": "姓名：{name}    性别：{gender}    年龄：{age}岁    病历号：{patient_id}",
            "font_size": 22
        },
        {
            "name": "exam_date",
            "bbox": [57, 194, 845, 220],
            "template": "就诊日期：{exam_date}",
            "font_size": 22
        },
        {
            "name": "doctor",
            "bbox": [56, 232, 886, 258],
            "template": "医生：{doctor}",
            "font_size": 22
        },
        {
            "name": "vital_signs",
            "bbox": [57, 274, 1205, 302],
            "template": "体温：{temp}℃    心率：{hr}次/分    血压：{bp}mmHg    呼吸：{rr}次/分",
            "font_size": 20
        },
        {
            "name": "symptoms",
            "bbox": [55, 310, 1205, 345],
            "template": "主诉：{symptom1}、{symptom2}、{symptom3}",
            "font_size": 22
        },
        {
            "name": "history",
            "bbox": [55, 344, 1205, 412],
            "template": "现病史：患者因{symptom1}、{symptom2}就诊，病程约{age}天。",
            "font_size": 20
        },
        {
            "name": "diagnosis",
            "bbox": [55, 411, 1205, 455],
            "template": "诊断：{diagnosis}",
            "font_size": 22
        },
        {
            "name": "treatment",
            "bbox": [56, 460, 1205, 489],
            "template": "处理：{treatment}",
            "font_size": 20
        },
        {
            "name": "advice",
            "bbox": [57, 503, 1205, 528],
            "template": "建议：{advice}",
            "font_size": 20
        },
        {
            "name": "followup",
            "bbox": [57, 539, 1205, 567],
            "template": "复诊：{followup_days}天后",
            "font_size": 20
        },
        {
            "name": "cost",
            "bbox": [58, 678, 178, 703],
            "template": "费用：{total_cost}元",
            "font_size": 20
        },
        {
            "name": "final_note",
            "bbox": [57, 1228, 1204, 1413],
            "template": "备注：本病历仅供一般参考，具体诊疗请遵医嘱。",
            "font_size": 20
        }
    ]