"""报告类型注册表"""
from . import imaging
from . import lab
from . import prescription
from . import medical_record

REPORT_TYPES = {
    "影像文字报告": imaging,
    "化验_检测报告": lab,
    "医嘱_处方": prescription,
    "门诊病历_就诊记录": medical_record,
}


def get_report_type(name):
    """根据名称获取报告类型模块"""
    if name not in REPORT_TYPES:
        available = ", ".join(REPORT_TYPES.keys())
        raise ValueError(f"未知的报告类型: {name}\n可用类型: {available}")
    return REPORT_TYPES[name]


def list_report_types():
    """列出所有可用的报告类型"""
    return list(REPORT_TYPES.keys())