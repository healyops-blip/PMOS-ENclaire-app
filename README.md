项目说明

本目录包含四类报告的文字生成与底图清理脚本：
- 影像文字报告
- 化验_检测报告
- 医嘱_处方
- 门诊病历_就诊记录

主要改动与特性
- 影像文字报告：增加左上角保守清理区域，移除旧院名/Logo（不影响字段）；右上角放置新 Logo。
- 统一 extra cleanup 路径：保留化验_检测报告右上表头小字清理框。
- 填充颜色支持 sample/white/gray。
- 名字与医生名称池扩充，避免重复（不再总是“张三”等）。
- 医生建议/话术多样化（影像报告/门诊病历）。
- 门诊病历体温严格限制在 37.3–37.8，jitter 范围同步限制。

运行环境
- Python 3.10+
- 依赖见 requirements.txt：
  - Pillow, numpy, opencv-python

快速开始
1) 安装依赖：
   pip install -r requirements.txt

2) 运行批量生成：
   python d:\hackathon_26\generate_all.py --emit-clean-bases --num-per-type 1 --unique-run-dir

3) 输出目录：
   d:\hackathon_26\result\<时间戳>

注意
- 字体默认使用 Windows 楷体：C:\\Windows\\Fonts\\simkai.ttf，可通过 --font-path 指定。
- 输出 result/ 目录已在 .gitignore 中忽略。
- 推送到 GitHub 分支前，请配置 SSH 公钥或使用 HTTPS + PAT。