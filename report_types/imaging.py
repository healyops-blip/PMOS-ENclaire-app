"""影像文字报告 - 数据生成器"""
import random
from datetime import datetime, timedelta


def generate_data():
    """生成影像文字报告的泛化数据"""
    now = datetime.now()

    return {
        # 患者信息
        "exam_date": (now - timedelta(days=random.randint(1, 30))).strftime("%Y-%m-%d"),
        "patient_id": f"P{random.randint(100000, 999999)}",
        # 中性、好听的名字，避免“女”字旁及过度男性化字（伟/强/军/磊/杰/超等）
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
        "impression": random.choice([
            "双侧卵巢多囊样改变",
            "右侧卵巢多囊样改变",
            "左侧卵巢多囊样改变",
            "子宫及双侧附件未见明显异常"
        ]),
        "recommendation": random.choice([
            "建议定期复查，三个月后复诊",
            "建议结合临床与激素水平进一步评估",
            "建议妇科门诊随诊，必要时完善检查",
            "建议3-6个月后复查超声评估",
            "建议规律作息、控制体重，必要时营养指导",
            "建议监测月经周期，记录异常情况",
            "建议与内分泌科联合随访评估",
            "建议计划妊娠者提前门诊评估",
            "建议生活方式干预（饮食+运动）",
            "建议与临床症状综合判断，动态观察",
            "建议一段时间后复查盆腔超声",
            "建议如症状加重及时就诊",
            "建议必要时完善性激素六项检测",
            "建议3个月后随访，评估干预效果",
            "建议心理及生活方式支持，减轻焦虑",
            "建议个体化管理方案，按医嘱随访"
        ]),
    }


def get_fields():
    """返回字段定义列表"""
    return [
        {
            "name": "exam_date",
            "bbox": [789, 240, 1190, 265],
            "template": "检查日期：{exam_date}",
            "font_size": 20
        },
        {
            "name": "patient_id",
            "bbox": [1000, 265, 1190, 290],
            "template": "病历号：{patient_id}",
            "font_size": 18
        },
        {
            "name": "name",
            "bbox": [60, 315, 840, 350],
            "template": "姓名：{name}   年龄：{age}岁   性别：{gender}",
            "font_size": 22
        },
        {
            "name": "doctor",
            "bbox": [60, 360, 840, 395],
            "template": "医生：{doctor}",
            "font_size": 22
        },
        {
            "name": "right_ovary",
            "bbox": [55, 770, 770, 858],
            "template": "右卵巢:多囊样改变,大小:{right_ovary_length}*{right_ovary_width}*{right_ovary_height}mm,基础卵泡:{follicle_count_right}个",
            "font_size": 18
        },
        {
            "name": "left_ovary",
            "bbox": [55, 884, 800, 996],
            "template": "左卵巢:多囊样改变,大小:{left_ovary_length}*{left_ovary_width}*{left_ovary_height}mm,基础卵泡:{follicle_count_left}个",
            "font_size": 18
        },
        {
            "name": "pelvic_effusion",
            "bbox": [60, 1000, 170, 1025],
            "template": "盆腔积液：{pelvic_effusion}",
            "font_size": 18
        },
        {
            "name": "impression",
            "bbox": [60, 1275, 1010, 1350],
            "template": "印象：{impression}",
            "font_size": 22
        },
        {
            "name": "recommendation",
            "bbox": [60, 1365, 570, 1435],
            "template": "建议：{recommendation}",
            "font_size": 22
        }
    ]