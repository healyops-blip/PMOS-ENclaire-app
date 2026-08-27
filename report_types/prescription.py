"""医嘱_处方 - 数据生成器"""
import random
from datetime import datetime, timedelta


# 常用药品库
MEDICATIONS = [
    {"name": "阿莫西林", "spec": "0.25g", "freq": "每日3次", "days": "5天"},
    {"name": "头孢克洛", "spec": "0.25g", "freq": "每日2次", "days": "7天"},
    {"name": "布洛芬", "spec": "0.4g", "freq": "每日2次", "days": "3天"},
    {"name": "奥美拉唑", "spec": "20mg", "freq": "每日1次", "days": "7天"},
    {"name": "二甲双胍", "spec": "0.5g", "freq": "每日3次", "days": "长期"},
    {"name": "氨氯地平", "spec": "5mg", "freq": "每日1次", "days": "长期"},
    {"name": "阿托伐他汀", "spec": "20mg", "freq": "每晚1次", "days": "长期"},
    {"name": "氯沙坦", "spec": "50mg", "freq": "每日1次", "days": "长期"},
    {"name": "硝苯地平", "spec": "30mg", "freq": "每日1次", "days": "长期"},
    {"name": "胰岛素", "spec": "10U", "freq": "每日2次", "days": "长期"},
    {"name": "左氧氟沙星", "spec": "0.5g", "freq": "每日1次", "days": "7天"},
    {"name": "对乙酰氨基酚", "spec": "0.5g", "freq": "每日3次", "days": "3天"},
]


def generate_data():
    """生成医嘱处方的泛化数据"""
    now = datetime.now()

    # 随机选择1-3种药品
    meds = random.sample(MEDICATIONS, random.randint(1, 3))

    return {
        # 患者信息
        "exam_date": (now - timedelta(days=random.randint(1, 30))).strftime("%Y-%m-%d"),
        "patient_id": f"PR{random.randint(10000, 99999)}",
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

        # 处方药品
        "med1_name": meds[0]["name"],
        "med1_spec": meds[0]["spec"],
        "med1_freq": meds[0]["freq"],
        "med1_days": meds[0]["days"],
        "med2_name": meds[1]["name"] if len(meds) > 1 else "",
        "med2_spec": meds[1]["spec"] if len(meds) > 1 else "",
        "med2_freq": meds[1]["freq"] if len(meds) > 1 else "",
        "med2_days": meds[1]["days"] if len(meds) > 1 else "",
        "med3_name": meds[2]["name"] if len(meds) > 2 else "",
        "med3_spec": meds[2]["spec"] if len(meds) > 2 else "",
        "med3_freq": meds[2]["freq"] if len(meds) > 2 else "",
        "med3_days": meds[2]["days"] if len(meds) > 2 else "",

        # 诊断
        "diagnosis": random.choice([
            "上呼吸道感染",
            "高血压病2级",
            "2型糖尿病",
            "胃炎",
            "肺炎",
            "冠状动脉粥样硬化性心脏病",
            "脑梗死",
            "关节炎",
        ]),

        # 剂量相关
        "dose_count": random.randint(1, 4),
        "dose_unit": random.choice(["片", "粒", "支", "支"]),
        "total_amount": random.randint(1, 100),
        "usage": random.choice(["口服", "静脉滴注", "皮下注射", "肌肉注射"]),
    }


def get_fields():
    """返回字段定义列表"""
    return [
        {
            "name": "title",
            "bbox": [68, 50, 1174, 98],
            "template": "处方",
            "font_size": 36
        },
        {
            "name": "patient_info",
            "bbox": [49, 167, 1185, 236],
            "template": "姓名：{name}    性别：{gender}    年龄：{age}岁    病历号：{patient_id}",
            "font_size": 22
        },
        {
            "name": "diagnosis",
            "bbox": [256, 330, 1160, 389],
            "template": "临床诊断：{diagnosis}",
            "font_size": 22
        },
        {
            "name": "med1",
            "bbox": [99, 514, 315, 572],
            "template": "{med1_name} {med1_spec}",
            "font_size": 20
        },
        {
            "name": "med1_detail",
            "bbox": [102, 674, 305, 726],
            "template": "{med1_freq} × {med1_days}",
            "font_size": 20
        },
        {
            "name": "med2",
            "bbox": [98, 860, 208, 916],
            "template": "{med2_name}",
            "font_size": 20
        },
        {
            "name": "med2_detail",
            "bbox": [103, 1042, 1136, 1100],
            "template": "{med2_name} {med2_spec}  {med2_freq} × {med2_days}",
            "font_size": 20
        },
        {
            "name": "med3",
            "bbox": [103, 1249, 705, 1303],
            "template": "{med3_name} {med3_spec}",
            "font_size": 20
        },
        {
            "name": "med3_detail",
            "bbox": [103, 1377, 634, 1431],
            "template": "{med3_freq} × {med3_days}",
            "font_size": 20
        },
        {
            "name": "usage",
            "bbox": [102, 1508, 334, 1558],
            "template": "用法：{usage}",
            "font_size": 20
        },
        {
            "name": "doctor",
            "bbox": [103, 1633, 365, 1686],
            "template": "医生：{doctor}",
            "font_size": 20
        },
        {
            "name": "signature",
            "bbox": [1123, 2072, 1188, 2148],
            "template": "审核人",
            "font_size": 16
        }
    ]