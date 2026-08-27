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

修复说明（“备注：备注：”重复问题）
- 背景：部分报告出现“备注：备注：”重复标签。
- 处理：
  - 数据侧（report_types/lab.py）：advice 存储为“原始内容”，不再包含“备注：”。
  - 模板/渲染侧：
    - 单体生成（case_generalize.py 与 report_types/lab.py 模板）只在模板中添加一次“备注：”。
    - 解耦引擎（layout_engine/engine.py）在绘制前会移除传入内容开头的一个或多个“备注：/建议：”前缀，再统一加一次“备注：”。
  - 自检工具：新增 tools/check_remarks_dup.py 校验若组合输出存在“备注：备注：”则报错。

当前示例输出位置
- 解耦引擎渲染（仅支持化验_检测报告）：
  - 图片与 sidecar JSON：d:\\hackathon_26\\tmp_check\\化验_检测报告
- 单体生成：
  - 图片与 truth JSON：d:\\hackathon_26\\tmp_check_mono\\化验_检测报告

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

单体生成（指定类型）
- 例：生成 1 份化验_检测报告（图片+truth JSON）：
  python d:\\hackathon_26\\case_generalize.py --type 化验_检测报告 --output d:\\hackathon_26\\tmp_check_mono --num 1

解耦引擎渲染（仅化验_检测报告）
- 可用布局：运行查看 list_available_layouts()
- 例：
  python d:\\hackathon_26\\render_decoupled.py --type 化验_检测报告 --layout hospital_lab_01 --output d:\\hackathon_26\\tmp_check --num 2

去重校验（防“备注：备注：”）
- 运行：python d:\\hackathon_26\\tools\\check_remarks_dup.py
- 通过时输出：Prefix normalization tests passed.

注意
- 字体默认使用 Windows 楷体：C:\\Windows\\Fonts\\simkai.ttf，可通过 --font-path 指定。
- 输出 result/ 目录已在 .gitignore 中忽略。
- 推送到 GitHub 分支前，请配置 SSH 公钥或使用 HTTPS + PAT。