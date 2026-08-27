"""门诊病历_就诊记录 - 数据生成器"""
import random
from datetime import datetime, timedelta


# 症状库
SYMPTOMS = [
    "头痛", "发热", "咳嗽", "腹痛", "胸闷", "乏力", "恶心", "呕吐",
    "腹泻", "失眠", "心悸", "头晕", "皮疹", "关节痛", "咽痛", "咳痰"
]

# 诊断库
DIAGNOSES = [
    "上呼吸道感染",
    "急性胃肠炎",
    "高血压病2级",
    "2型糖尿病",
    "冠状动脉粥样硬化性心脏病",
    "脑梗死",
    "关节炎",
    "腰椎间盘突出",
    "颈椎病",
    "慢性胃炎",
    "胆囊炎",
    "尿路感染",
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
        # 中性、好听的名字，避免“女”字旁及过度男性化字
        "name": random.choice([
            "张子涵", "王语晨", "李亦然", "刘晨曦", "陈星辰", "杨景澄", "赵之远", "周清和",
            "吴清岚", "郑清扬", "孙清越", "胡清澄", "郭若溪", "何若林", "高若寒", "林子衿",
            "罗子期", "马景宁", "姜柏言", "许栩然", "傅栩宁", "曹知行", "邓知远", "崔知新",
            "冯承安", "宋承宁", "唐明安", "韩明川", "彭明溪", "蒋明远", "于明诚", "谢晨安"
        ]),
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
            "建议对症处理，短期随访观察",
            "建议门诊随访，必要时完善检查",
            "建议完善相关检查后再评估",
            "建议休息，多饮水，注意营养",
            "建议规律作息，避免劳累",
            "建议生活方式干预（饮食+运动）",
            "建议结合检查结果制定个体化方案",
            "建议按时服药，监测症状变化",
            "建议加强防护，避免受凉与感染",
            "建议如症状加重及时复诊",
            "建议必要时转专科进一步评估",
            "建议心理疏导与情绪管理",
            "建议控制体重，优化代谢指标",
            "建议复诊时携带相关检查资料",
            "建议阶段性复查，动态评估"
        ]),
        "followup_days": random.randint(1, 30),
        "advice": random.choice([
            "注意休息，清淡饮食，避免辛辣油腻",
            "避免劳累，规律作息，保持良好心情",
            "多饮水，适量运动，控制体重",
            "按时服药，出现不适及时就诊",
            "注意防寒保暖，避免受凉",
            "饮食均衡，少盐少糖，避免暴饮暴食",
            "保持作息规律，保证充足睡眠",
            "戒烟限酒，维持健康生活方式",
            "遵医嘱复诊，按时复查相关项目",
            "记录症状变化，复诊时反馈",
            "情绪管理，必要时进行心理疏导",
            "合理安排工作与生活，避免过度压力",
            "增加蔬菜水果摄入，注意纤维补充",
            "按计划随访，评估治疗效果",
            "注意个人防护，减少公共场所逗留"
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
            "bbox": [57, 274, 248, 302],
            "template": "体温：{temp}℃",
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
            "bbox": [56, 460, 282, 489],
            "template": "处理：{treatment}",
            "font_size": 20
        },
        {
            "name": "advice",
            "bbox": [57, 503, 120, 528],
            "template": "建议：{advice}",
            "font_size": 20
        },
        {
            "name": "followup",
            "bbox": [57, 539, 282, 567],
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
            "name": "doctor2",
            "bbox": [58, 772, 552, 797],
            "template": "医生意见：{advice}",
            "font_size": 20
        },
        {
            "name": "note",
            "bbox": [57, 803, 116, 831],
            "template": "注意：{advice}",
            "font_size": 20
        },
        {
            "name": "final_advice",
            "bbox": [56, 897, 135, 928],
            "template": "随访：{followup_days}天",
            "font_size": 20
        },
        {
            "name": "final_diagnosis",
            "bbox": [56, 960, 203, 988],
            "template": "诊断：{diagnosis}",
            "font_size": 20
        },
        {
            "name": "final_treatment",
            "bbox": [58, 1003, 352, 1029],
            "template": "治疗：{treatment}",
            "font_size": 20
        },
        {
            "name": "final_advice2",
            "bbox": [58, 1035, 352, 1061],
            "template": "建议：{advice}",
            "font_size": 20
        },
        {
            "name": "final_followup",
            "bbox": [56, 1075, 223, 1100],
            "template": "复诊：{followup_days}天",
            "font_size": 20
        },
        {
            "name": "final_cost",
            "bbox": [55, 1109, 1205, 1220],
            "template": "费用总计：{total_cost}元",
            "font_size": 22
        },
        {
            "name": "final_note",
            "bbox": [57, 1228, 1204, 1413],
            "template": "备注：本病历仅供一般参考，具体诊疗请遵医嘱。",
            "font_size": 20
        }
    ]