"""化验_检测报告 - 数据生成器"""
import random
from datetime import datetime, timedelta


def generate_data():
    """生成化验检测报告的泛化数据"""
    now = datetime.now()

    return {
        # 患者信息
        "exam_date": (now - timedelta(days=random.randint(1, 30))).strftime("%Y-%m-%d"),
        "patient_id": f"LA{random.randint(10000, 99999)}",
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
    }


def get_fields():
    """返回字段定义列表"""
    return [
        {
            "name": "title",
            "bbox": [30, 0, 1120, 99],
            "template": "检验报告单",
            "font_size": 32
        },
        {
            "name": "exam_date",
            "bbox": [464, 119, 1151, 180],
            "template": "报告日期：{exam_date}",
            "font_size": 22
        },
        {
            "name": "patient_info",
            "bbox": [38, 205, 959, 338],
            "template": "姓名：{name}    性别：{gender}    年龄：{age}岁    病历号：{patient_id}",
            "font_size": 20
        },
        {
            "name": "doctor",
            "bbox": [133, 377, 1079, 416],
            "template": "医生：{doctor}",
            "font_size": 20
        },
        {
            "name": "wbc",
            "bbox": [28, 442, 1201, 555],
            "template": "白细胞计数(WBC): {wbc} × 10^9/L",
            "font_size": 18
        },
        {
            "name": "rbc",
            "bbox": [28, 585, 1194, 675],
            "template": "红细胞计数(RBC): {rbc} × 10^12/L",
            "font_size": 18
        },
        {
            "name": "hgb",
            "bbox": [29, 683, 1178, 796],
            "template": "血红蛋白(HGB): {hgb} g/L",
            "font_size": 18
        },
        {
            "name": "plt",
            "bbox": [28, 804, 1191, 960],
            "template": "血小板计数(PLT): {plt} × 10^9/L",
            "font_size": 18
        },
        {
            "name": "alt",
            "bbox": [29, 968, 993, 1014],
            "template": "谷丙转氨酶(ALT): {alt} U/L",
            "font_size": 18
        },
        {
            "name": "ast",
            "bbox": [28, 1023, 1196, 1092],
            "template": "谷草转氨酶(AST): {ast} U/L",
            "font_size": 18
        },
        {
            "name": "tbil",
            "bbox": [31, 1463, 241, 1491],
            "template": "总胆红素(TBIL): {tbil} μmol/L",
            "font_size": 18
        },
        {
            "name": "crea",
            "bbox": [31, 1495, 681, 1524],
            "template": "肌酐(CREA): {crea} μmol/L",
            "font_size": 18
        },
        {
            "name": "glu",
            "bbox": [492, 1532, 695, 1560],
            "template": "血糖(GLU): {glu} mmol/L",
            "font_size": 18
        },
        {
            "name": "cho",
            "bbox": [33, 1569, 450, 1596],
            "template": "总胆固醇(CHO): {cho} mmol/L",
            "font_size": 18
        },
        {
            "name": "tg",
            "bbox": [32, 1604, 1066, 1632],
            "template": "甘油三酯(TG): {tg} mmol/L",
            "font_size": 18
        },
        {
            "name": "hdl",
            "bbox": [32, 1639, 1008, 1674],
            "template": "高密度脂蛋白(HDL): {hdl} mmol/L",
            "font_size": 18
        },
        {
            "name": "ldl",
            "bbox": [31, 1689, 1196, 1733],
            "template": "低密度脂蛋白(LDL): {ldl} mmol/L",
            "font_size": 18
        }
    ]