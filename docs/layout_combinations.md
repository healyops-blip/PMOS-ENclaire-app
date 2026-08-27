布局组合与可配置说明（化验_检测报告）

概览
- 解耦布局引擎文件：d:\hackathon_26\layout_engine\engine.py
- 预置布局注册：d:\hackathon_26\layout_engine\layouts.py
- 批量按组合生成脚本：d:\hackathon_26\tools\gen_combo_layouts.py
- 你可以传入“布局名称字符串”（来自 layouts.list_layouts 的键）或“自定义布局字典”给 generate_report。

核心用法
- 通过引擎渲染：
  - Python 调用：
    - from layout_engine.engine import generate_report
    - generate_report(content, layout, output_path, config)
  - 参数：
    - content：内容字典，需包含至少医院、报告类型、姓名、性别、年龄、科室、就诊号、医生、检验日期及常用检验项目等。
    - layout：布局名称字符串（如 "hospital_lab_01"）或布局字典（见下方 schema 结构）。
    - output_path：输出 JPG 绝对路径。
    - config：渲染配置，如 {"font_path": "C:/Windows/Fonts/simsun.ttc", "jpeg_quality": 95, "skip_logo": True}。

布局 schema 字段
1) 页面方向（page）
- 预设键：A4_P, A4_L, A5_P, A5_L
- 结构：{"size": (宽, 高), "margins": (左, 上, 右, 下)}
  - A4 portrait（A4_P）：(1240, 1754), 边距(36,36,36,36)
  - A4 landscape（A4_L）：(1754, 1240), 边距(36,36,36,36)
  - A5 portrait（A5_P）：(874, 1240), 边距(28,28,28,28)
  - A5 landscape（A5_L）：(1240, 874), 边距(28,28,28,28)

2) 页眉风格（header_style）
- HEADER_01：医院名称居中，下面居中显示报告类型。
- HEADER_02：左侧预留 Logo（可通过 config.skip_logo 控制绘制），医院名称居中，报告类型位于医院名称下方。
- HEADER_03：医院名称左对齐，右侧显示报告日期，下方一条粗横线。
- HEADER_04：医院名称居中，医院英文名位于中文名下方，报告类型位于右侧。

3) 患者信息布局（patient_layout）
- PATIENT_01：横向多列（姓名 | 性别 | 年龄 | 科室 | 就诊号；下一行含日期与申请医生）。
- PATIENT_02：两行网格（姓名 | 性别 | 年龄；科室 | 就诊号 | 申请医生）。
- PATIENT_03：左侧患者信息 + 右侧二维码占位（二维码方框预留，可后续接入具体二维码绘制）。
- PATIENT_04：标签式（“患者：”标题下以多行列出姓名、性别、年龄等）。

4) 主体内容结构（table_style，化验表）
- TABLE_01：传统完整网格表（横竖线全有）。
- TABLE_02：只有水平线，没有竖线（列线省略，更简洁）。
- TABLE_03：表格外框 + 内部无横线（以外框为主，内部尽量极简）。
- TABLE_04：分组表格（示例组名“生化指标”，列为“项目 | 结果 | 单位 | 参考范围”）。
- TABLE_05：左右双栏（左侧项目名称列表，右侧结果/单位列表，中心分割线）。

5) 字体风格（font_style）
- FONT_01：宋体 + 黑体（标题/页眉用黑体，正文宋体）。
- FONT_02：全宋体。
- FONT_03：黑体标题 + 宋体正文。
- FONT_04：医院打印风格小号无衬线（使用微软雅黑）。
- 实际字体选择见 d:\hackathon_26\layout_engine\engine.py 中 _choose_font_paths。

6) 信息密度（density）
- DENSITY_LOW：大字号、大行距、留白多。
- DENSITY_MEDIUM：常规医院报告风格。
- DENSITY_HIGH：小字号、小行距、表格紧凑、信息量大。
- 具体字号/行距映射见 _size_profile（engine.py）：返回 hosp/title/header/body/small 字号与 row_delta。

7) 页脚（footer_style）
- FOOTER_01：检验时间 | 报告时间 | 检验者 | 审核者。
- FOOTER_02：左侧地址 | 中间联系电话 | 右侧页码。
- FOOTER_03：底部仅检验者/审核者。

8) 组件（components）
- lab_table：控制表格绘制的参数。
  - cols：各列宽比例（适用于 TABLE_01/02/03）。
  - cols_grouped：分组表的列宽比例（TABLE_04）。
  - row_height：行高，header_height：表头高。
  - draw_outer_box：是否绘制外框。
  - draw_header_bands：是否绘制表头上下线。
  - draw_row_lines：是否绘制行线（TABLE_03 通常关闭）。
  - draw_col_lines：是否绘制列线（TABLE_01 默认开启）。
- notes：{"lines": 1/2/3} 控制备注区域预留行数（不同密度下建议减少行数避免拥挤）。

“备注：”统一去重说明
- 引擎会在绘制前对备注/建议字段进行规范化：移除任何开头的一个或多个“备注：/建议：”前缀（半角冒号/全角冒号均可），再统一加一次“备注：”。
- 正则：^((备注|建议)[:：]\s*)+
- 这可避免上游数据或模板重复加标签导致的“备注：备注：”现象。

自定义 schema 示例
- 以 A4 竖版 + HEADER_03 + PATIENT_02 + TABLE_01 + FONT_03 + DENSITY_HIGH + FOOTER_01 为例：
- Python 片段（在 d:\hackathon_26 根目录运行环境中）：
  - from layout_engine.engine import generate_report
  - from report_types import get_report_type
  - schema = {
    -   "page": {"size": (1240,1754), "margins": (36,36,36,36)},
    -   "header_style": "HEADER_03",
    -   "patient_layout": "PATIENT_02",
    -   "table_style": "TABLE_01",
    -   "font_style": "FONT_03",
    -   "density": "DENSITY_HIGH",
    -   "footer_style": "FOOTER_01",
    -   "components": {
    -       "lab_table": {"row_height": 36, "header_height": 42, "draw_outer_box": True, "draw_col_lines": True},
    -       "notes": {"lines": 2}
    -   }
  - }
  - content = get_report_type("化验_检测报告").generate_data()
  - content.update({"report_type": "化验_检测报告", "gender": "女", "title": "检验报告单", "hospital": "示例医院", "patient_id": "LA12345"})
  - generate_report(content, schema, "d:/hackathon_26/outputs/example.jpg", {"font_path": "C:/Windows/Fonts/simsun.ttc", "jpeg_quality": 95})

现有预置布局（可直接用字符串）
- 可用键见：d:\hackathon_26\layout_engine\layouts.py 中 list_layouts 返回字典的键，例如：
  - hospital_lab_01（A4_P + HEADER_01 + PATIENT_01 + TABLE_02 + FONT_02 + DENSITY_MEDIUM + FOOTER_01）
  - hospital_lab_03（A4_L + HEADER_03 + PATIENT_02 + TABLE_01 + FONT_03 + DENSITY_HIGH + FOOTER_01）
  - hospital_lab_05（A5_P + HEADER_01 + PATIENT_04 + TABLE_03 + FONT_01 + DENSITY_LOW + FOOTER_03）
  - hospital_lab_grouped（A4_P + HEADER_04 + PATIENT_03 + TABLE_04 + FONT_03 + DENSITY_MEDIUM + FOOTER_02）
  - hospital_lab_two_col（A4_P + HEADER_01 + PATIENT_01 + TABLE_05 + FONT_02 + DENSITY_HIGH + FOOTER_03）

批量生成 30 种组合
- 使用脚本：d:\hackathon_26\tools\gen_combo_layouts.py
- 命令示例：
  - python d:\hackathon_26\tools\gen_combo_layouts.py --output d:\hackathon_26\outputs\combo_30 --count 30
- 输出位置：
  - d:\hackathon_26\outputs\combo_30\化验_检测报告（包含 case_00001.jpg/.json 至 case_00030.jpg/.json）

注意事项
- 目前解耦引擎主要针对“化验_检测报告”完善了布局与表格绘制；其他报告类型将逐步补齐独立 schema。
- 字体优先使用 config.font_path；若加载失败，引擎会尝试 Windows 系统字体（微软雅黑、楷体、宋体）。
- 高密度布局（DENSITY_HIGH）会减小字号与行高（通过 row_delta），若表格拥挤可适度增大 components.lab_table.row_height/header_height。
- TABLE_05 双栏样式下，列比例由引擎内部处理（左右半宽 + 中心分割），无需传入 cols。