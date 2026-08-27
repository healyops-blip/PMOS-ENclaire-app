# Pomi 药品静态数据库｜可读版 v2.0

> 供产品、医学、技术团队内部沟通与 Demo 开发使用。
>
> **重要边界：** 当前 20 条均为 Demo 候选。药品名称、别名、剂型与规格属于候选信息；参考用法仍待具体上市产品说明书和医学顾问审核，不构成用药建议。静态库不得自动生成患者实际用药方案或直接开启提醒。

## 1. 版本概览

| 项目 | 数量 |
| --- | ---: |
| 总记录 | 20 |
| PCOS 管理相关 | 9 |
| 补充剂 | 4 |
| 生育及备孕 | 3 |
| 感冒发烧常用 | 4 |

### 1.1 提醒方案的三层数据边界

| 数据层 | 包含内容 | 用途 | 提醒权限 |
| --- | --- | --- | --- |
| 静态数据库 | 标准名、别名、剂型、规格候选、参考用法 | 仅用于识别和展示 | 不能自动创建提醒 |
| 说明书参考 | 具体上市产品经核验的官方参考用法 | 供用户和团队对照 | 不能覆盖本次医嘱 |
| 患者实际方案 | 一次用量、单位、每日次数、具体时点、疗程、来源 | 来自医嘱 OCR 或手动输入 | 用户确认后才可创建提醒 |
| 维生素/补充剂 | 可展示官方标签参考，也可手动输入 | 优先保留用户实际方案 | 用户确认后才可创建提醒 |

### 1.2 用药提醒流程

识别/搜索药品 → 匹配标准 ID → 提取或填写一次用量、每日次数、时点与疗程 → 缺失项待确认 → 用户确认用药记录 → 用户另行开启提醒

## 2. 药品主表

| 药品ID | 标准通用名 | 类别 | 类型 | PCOS语境 | 剂型候选 | 规格候选 | OCR别名 | 医学/说明书审核 | 记录状态 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| med_ethinylestradiol_cyproterone_acetate | 炔雌醇环丙孕酮片 | PCOS管理相关 | 处方药 | commonly_seen | 片剂 | 炔雌醇0.035mg+醋酸环丙孕酮2mg | 达英-35；达英35；达英 | pending_official_label_and_medical_review | 活动Demo白名单 |
| med_ethinylestradiol_drospirenone | 炔雌醇屈螺酮片 | PCOS管理相关 | 处方药 | commonly_seen | 片剂 | — | 优思明；优思悦；炔雌醇屈螺酮 | pending_official_label_and_medical_review | 活动Demo白名单 |
| med_metformin_hydrochloride | 盐酸二甲双胍 | PCOS管理相关 | 处方药 | commonly_seen | 普通片；缓释片 | 0.25g；0.5g；0.85g | 二甲双胍；格华止；美迪康；二甲 | pending_official_label_and_medical_review | 活动Demo白名单 |
| med_spironolactone | 螺内酯 | PCOS管理相关 | 处方药 | contextual | 片剂 | 20mg；100mg | 螺内酯片；安体舒通；螺旋内酯 | pending_official_label_and_medical_review | 活动Demo白名单 |
| med_dydrogesterone | 地屈孕酮 | PCOS管理相关 | 处方药 | contextual | 片剂 | — | 地屈孕酮片；达芙通 | pending_official_label_and_medical_review | 活动Demo白名单 |
| med_micronized_progesterone | 黄体酮 | PCOS管理相关 | 处方药 | contextual | 胶囊剂 | — | 黄体酮胶囊；微粒化黄体酮 | pending_official_label_and_medical_review | 活动Demo白名单 |
| med_medroxyprogesterone_acetate | 醋酸甲羟孕酮 | PCOS管理相关 | 处方药 | contextual | 片剂 | — | 醋酸甲羟孕酮片；甲羟孕酮 | pending_official_label_and_medical_review | 活动Demo白名单 |
| med_semaglutide | 司美格鲁肽 | PCOS管理相关 | 处方药 | contextual | 注射剂；片剂 | — | 司美格鲁肽注射液；司美格鲁肽片 | pending_official_label_and_medical_review | 活动Demo白名单 |
| med_liraglutide | 利拉鲁肽 | PCOS管理相关 | 处方药 | contextual | 注射剂 | — | 利拉鲁肽注射液 | pending_official_label_and_medical_review | 活动Demo白名单 |
| supp_inositol | 肌醇 | 补充剂 | 补充剂 | commonly_seen | 粉剂；胶囊剂；片剂 | — | 肌醇粉；Myo-inositol；D-chiro-inositol；MI；DCI | pending_medical_and_product_review | 活动Demo白名单 |
| supp_vitamin_d3 | 维生素D3 | 补充剂 | 补充剂 | uncertain | 片剂；胶囊剂；滴剂 | — | 维D3；VD3；胆钙化醇；维生素D滴剂 | pending_official_nutrition_reference_and_product_review | 活动Demo白名单 |
| supp_vitamin_b12 | 维生素B12 | 补充剂 | 补充剂 | uncertain | 片剂；胶囊剂 | — | 维B12；VB12；钴胺素 | pending_official_nutrition_reference_and_product_review | 活动Demo白名单 |
| supp_calcium_vitamin_d3 | 钙维生素D复方制剂 | 补充剂 | 补充剂 | uncertain | 片剂；咀嚼片；颗粒剂 | — | 钙片；钙D；碳酸钙D3；钙加维D | pending_product_label_and_medical_review | 活动Demo白名单 |
| med_letrozole | 来曲唑 | 生育及备孕 | 处方药 | contextual | 片剂 | 2.5mg | 来曲唑片；弗隆 | pending_official_label_and_medical_review | 活动Demo白名单 |
| med_clomiphene_citrate | 枸橼酸氯米芬 | 生育及备孕 | 处方药 | contextual | 片剂 | 50mg | 氯米芬；克罗米芬；舒经芬；CC | pending_official_label_and_medical_review | 活动Demo白名单 |
| supp_folic_acid | 叶酸 | 生育及备孕 | 补充剂 | contextual | 片剂 | — | 叶酸片；维生素B9；VB9 | pending_official_preconception_reference_and_medical_review | 活动Demo白名单 |
| otc_paracetamol | 对乙酰氨基酚 | 感冒发烧常用 | 非处方药 | unrelated | 片剂；缓释片；混悬液 | — | 对乙酰氨基酚片；扑热息痛；泰诺林 | pending_specific_product_label_review | 活动Demo白名单 |
| otc_ibuprofen | 布洛芬 | 感冒发烧常用 | 非处方药 | unrelated | 片剂；缓释胶囊；混悬液 | — | 布洛芬片；布洛芬缓释胶囊；芬必得；美林 | pending_specific_product_label_review | 活动Demo白名单 |
| otc_compound_paracetamol_amantadine | 复方氨酚烷胺制剂 | 感冒发烧常用 | 非处方药 | unrelated | 片剂；胶囊剂 | — | 复方氨酚烷胺片；复方氨酚烷胺胶囊；感康；快克 | pending_specific_product_label_review | 活动Demo白名单 |
| otc_dextromethorphan | 右美沙芬 | 感冒发烧常用 | 非处方药 | unrelated | 片剂；口服液；糖浆剂 | — | 氢溴酸右美沙芬；右美沙芬片；右美沙芬糖浆 | pending_specific_product_label_review | 活动Demo白名单 |

## 3. 用法与提醒

| 药品ID | 标准通用名 | 类别 | 给药途径 | 参考使用方法 | 一次用量 | 每日次数 | 实际方案来源 | 允许手动修改 | 静态库可自动建提醒 | 审核状态 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| med_ethinylestradiol_cyproterone_acetate | 炔雌醇环丙孕酮片 | PCOS管理相关 | 口服 | 按医生处方中的周期、每日次数和每次片数录入；不得由静态库自动生成疗程。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_required | 是 | 否 | pending_official_label_and_medical_review |
| med_ethinylestradiol_drospirenone | 炔雌醇屈螺酮片 | PCOS管理相关 | 口服 | 不同产品的成分规格和服用周期可能不同，必须读取具体医嘱或具体产品说明书。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_or_product_label_required | 是 | 否 | pending_official_label_and_medical_review |
| med_metformin_hydrochloride | 盐酸二甲双胍 | PCOS管理相关 | 口服 | 普通片与缓释片的次数和服用时点可能不同；必须按医嘱分别录入剂型、每次剂量和每日次数。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_required | 是 | 否 | pending_official_label_and_medical_review |
| med_spironolactone | 螺内酯 | PCOS管理相关 | 口服 | 具体每次剂量和每日次数依适应证与医生处方而定，静态库不提供默认提醒方案。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_required | 是 | 否 | pending_official_label_and_medical_review |
| med_dydrogesterone | 地屈孕酮 | PCOS管理相关 | 口服 | 服用起止日、每日次数和每次片数依具体医嘱而定，必须保存周期性方案。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_required | 是 | 否 | pending_official_label_and_medical_review |
| med_micronized_progesterone | 黄体酮 | PCOS管理相关 | 按具体制剂和医嘱确认 | 不同制剂的给药途径和方案可能不同，药名匹配后仍必须确认剂型、途径、次数和每次用量。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_required | 是 | 否 | pending_official_label_and_medical_review |
| med_medroxyprogesterone_acetate | 醋酸甲羟孕酮 | PCOS管理相关 | 口服 | 具体疗程、每日次数和每次片数必须来自医嘱，不设置通用提醒默认值。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_required | 是 | 否 | pending_official_label_and_medical_review |
| med_semaglutide | 司美格鲁肽 | PCOS管理相关 | 按具体制剂确认 | 不同制剂的途径和给药频率不同，必须匹配到具体产品与医嘱后才能创建提醒。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_and_specific_product_required | 是 | 否 | pending_official_label_and_medical_review |
| med_liraglutide | 利拉鲁肽 | PCOS管理相关 | 皮下注射 | 具体剂量、递增方案和频率必须来自医生处方；静态库仅记录给药途径候选。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_required | 是 | 否 | pending_official_label_and_medical_review |
| supp_inositol | 肌醇 | 补充剂 | 口服 | 不同产品成分比例和含量差异较大，应按具体产品说明或专业人员建议录入，允许完全手动设置。 | 待医嘱/手动输入 | 待医嘱/手动输入 | product_label_or_manual_entry | 是 | 否 | pending_medical_and_product_review |
| supp_vitamin_d3 | 维生素D3 | 补充剂 | 口服 | 可展示经审核的参考摄入信息，但具体产品单位和服用量差异较大，用户可按产品说明或医嘱手动输入。 | 待医嘱/手动输入 | 待医嘱/手动输入 | approved_reference_or_product_label_or_manual_entry | 是 | 否 | pending_official_nutrition_reference_and_product_review |
| supp_vitamin_b12 | 维生素B12 | 补充剂 | 口服 | 参考摄入量与具体产品用量不是同一概念；允许按产品说明、检测结果相关医嘱或手动输入设置。 | 待医嘱/手动输入 | 待医嘱/手动输入 | approved_reference_or_product_label_or_manual_entry | 是 | 否 | pending_official_nutrition_reference_and_product_review |
| supp_calcium_vitamin_d3 | 钙维生素D复方制剂 | 补充剂 | 口服 | 复方产品的元素钙和维生素D含量不同，应按具体产品说明或医嘱录入；支持手动输入。 | 待医嘱/手动输入 | 待医嘱/手动输入 | product_label_or_manual_entry | 是 | 否 | pending_product_label_and_medical_review |
| med_letrozole | 来曲唑 | 生育及备孕 | 口服 | 生育治疗中的开始日期、连续天数、每日次数和每次剂量必须来自医生处方。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_required | 是 | 否 | pending_official_label_and_medical_review |
| med_clomiphene_citrate | 枸橼酸氯米芬 | 生育及备孕 | 口服 | 生育治疗中的开始日期、连续天数、每日次数和每次剂量必须来自医生处方。 | 待医嘱/手动输入 | 待医嘱/手动输入 | medical_order_required | 是 | 否 | pending_official_label_and_medical_review |
| supp_folic_acid | 叶酸 | 生育及备孕 | 口服 | 可展示经审核的备孕参考信息，但不同人群和产品可能不同；用户可按医嘱或产品说明手动输入。 | 待医嘱/手动输入 | 待医嘱/手动输入 | approved_preconception_reference_or_medical_order_or_manual_entry | 是 | 否 | pending_official_preconception_reference_and_medical_review |
| otc_paracetamol | 对乙酰氨基酚 | 感冒发烧常用 | 口服 | 不同剂型、规格和人群用量不同，应按具体产品说明书录入每次量、间隔和每日上限；不可从通用名自动生成。 | 待医嘱/手动输入 | 待医嘱/手动输入 | specific_product_label_or_medical_order_required | 是 | 否 | pending_specific_product_label_review |
| otc_ibuprofen | 布洛芬 | 感冒发烧常用 | 口服 | 普通与缓释制剂、成人与儿童产品的用法不同，应按具体产品说明书或医嘱录入。 | 待医嘱/手动输入 | 待医嘱/手动输入 | specific_product_label_or_medical_order_required | 是 | 否 | pending_specific_product_label_review |
| otc_compound_paracetamol_amantadine | 复方氨酚烷胺制剂 | 感冒发烧常用 | 口服 | 复方产品成分和规格可能不同，必须识别具体商品与说明书；静态库不提供统一次数或片数。 | 待医嘱/手动输入 | 待医嘱/手动输入 | specific_product_label_required | 是 | 否 | pending_specific_product_label_review |
| otc_dextromethorphan | 右美沙芬 | 感冒发烧常用 | 口服 | 不同剂型和规格的每次用量、间隔不同，应按具体产品说明书或医嘱录入。 | 待医嘱/手动输入 | 待医嘱/手动输入 | specific_product_label_or_medical_order_required | 是 | 否 | pending_specific_product_label_review |

## 4. OCR 别名词库

| 药品ID | 标准通用名 | 识别词 | 词类型 | 类别 | 匹配状态 |
| --- | --- | --- | --- | --- | --- |
| med_ethinylestradiol_cyproterone_acetate | 炔雌醇环丙孕酮片 | 炔雌醇环丙孕酮片 | 标准名 | PCOS管理相关 | 高 |
| med_ethinylestradiol_cyproterone_acetate | 炔雌醇环丙孕酮片 | 达英-35 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_ethinylestradiol_cyproterone_acetate | 炔雌醇环丙孕酮片 | 达英35 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_ethinylestradiol_cyproterone_acetate | 炔雌醇环丙孕酮片 | 达英 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_ethinylestradiol_drospirenone | 炔雌醇屈螺酮片 | 炔雌醇屈螺酮片 | 标准名 | PCOS管理相关 | 高 |
| med_ethinylestradiol_drospirenone | 炔雌醇屈螺酮片 | 优思明 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_ethinylestradiol_drospirenone | 炔雌醇屈螺酮片 | 优思悦 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_ethinylestradiol_drospirenone | 炔雌醇屈螺酮片 | 炔雌醇屈螺酮 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_metformin_hydrochloride | 盐酸二甲双胍 | 盐酸二甲双胍 | 标准名 | PCOS管理相关 | 高 |
| med_metformin_hydrochloride | 盐酸二甲双胍 | 二甲双胍 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_metformin_hydrochloride | 盐酸二甲双胍 | 格华止 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_metformin_hydrochloride | 盐酸二甲双胍 | 美迪康 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_metformin_hydrochloride | 盐酸二甲双胍 | 二甲 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_spironolactone | 螺内酯 | 螺内酯 | 标准名 | PCOS管理相关 | 高 |
| med_spironolactone | 螺内酯 | 螺内酯片 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_spironolactone | 螺内酯 | 安体舒通 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_spironolactone | 螺内酯 | 螺旋内酯 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_dydrogesterone | 地屈孕酮 | 地屈孕酮 | 标准名 | PCOS管理相关 | 高 |
| med_dydrogesterone | 地屈孕酮 | 地屈孕酮片 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_dydrogesterone | 地屈孕酮 | 达芙通 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_micronized_progesterone | 黄体酮 | 黄体酮 | 标准名 | PCOS管理相关 | 高 |
| med_micronized_progesterone | 黄体酮 | 黄体酮胶囊 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_micronized_progesterone | 黄体酮 | 微粒化黄体酮 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_medroxyprogesterone_acetate | 醋酸甲羟孕酮 | 醋酸甲羟孕酮 | 标准名 | PCOS管理相关 | 高 |
| med_medroxyprogesterone_acetate | 醋酸甲羟孕酮 | 醋酸甲羟孕酮片 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_medroxyprogesterone_acetate | 醋酸甲羟孕酮 | 甲羟孕酮 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_semaglutide | 司美格鲁肽 | 司美格鲁肽 | 标准名 | PCOS管理相关 | 高 |
| med_semaglutide | 司美格鲁肽 | 司美格鲁肽注射液 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_semaglutide | 司美格鲁肽 | 司美格鲁肽片 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| med_liraglutide | 利拉鲁肽 | 利拉鲁肽 | 标准名 | PCOS管理相关 | 高 |
| med_liraglutide | 利拉鲁肽 | 利拉鲁肽注射液 | 别名候选 | PCOS管理相关 | 待OCR测试 |
| supp_inositol | 肌醇 | 肌醇 | 标准名 | 补充剂 | 高 |
| supp_inositol | 肌醇 | 肌醇粉 | 别名候选 | 补充剂 | 待OCR测试 |
| supp_inositol | 肌醇 | Myo-inositol | 别名候选 | 补充剂 | 待OCR测试 |
| supp_inositol | 肌醇 | D-chiro-inositol | 别名候选 | 补充剂 | 待OCR测试 |
| supp_inositol | 肌醇 | MI | 别名候选 | 补充剂 | 待OCR测试 |
| supp_inositol | 肌醇 | DCI | 别名候选 | 补充剂 | 待OCR测试 |
| supp_vitamin_d3 | 维生素D3 | 维生素D3 | 标准名 | 补充剂 | 高 |
| supp_vitamin_d3 | 维生素D3 | 维D3 | 别名候选 | 补充剂 | 待OCR测试 |
| supp_vitamin_d3 | 维生素D3 | VD3 | 别名候选 | 补充剂 | 待OCR测试 |
| supp_vitamin_d3 | 维生素D3 | 胆钙化醇 | 别名候选 | 补充剂 | 待OCR测试 |
| supp_vitamin_d3 | 维生素D3 | 维生素D滴剂 | 别名候选 | 补充剂 | 待OCR测试 |
| supp_vitamin_b12 | 维生素B12 | 维生素B12 | 标准名 | 补充剂 | 高 |
| supp_vitamin_b12 | 维生素B12 | 维B12 | 别名候选 | 补充剂 | 待OCR测试 |
| supp_vitamin_b12 | 维生素B12 | VB12 | 别名候选 | 补充剂 | 待OCR测试 |
| supp_vitamin_b12 | 维生素B12 | 钴胺素 | 别名候选 | 补充剂 | 待OCR测试 |
| supp_calcium_vitamin_d3 | 钙维生素D复方制剂 | 钙维生素D复方制剂 | 标准名 | 补充剂 | 高 |
| supp_calcium_vitamin_d3 | 钙维生素D复方制剂 | 钙片 | 别名候选 | 补充剂 | 待OCR测试 |
| supp_calcium_vitamin_d3 | 钙维生素D复方制剂 | 钙D | 别名候选 | 补充剂 | 待OCR测试 |
| supp_calcium_vitamin_d3 | 钙维生素D复方制剂 | 碳酸钙D3 | 别名候选 | 补充剂 | 待OCR测试 |
| supp_calcium_vitamin_d3 | 钙维生素D复方制剂 | 钙加维D | 别名候选 | 补充剂 | 待OCR测试 |
| med_letrozole | 来曲唑 | 来曲唑 | 标准名 | 生育及备孕 | 高 |
| med_letrozole | 来曲唑 | 来曲唑片 | 别名候选 | 生育及备孕 | 待OCR测试 |
| med_letrozole | 来曲唑 | 弗隆 | 别名候选 | 生育及备孕 | 待OCR测试 |
| med_clomiphene_citrate | 枸橼酸氯米芬 | 枸橼酸氯米芬 | 标准名 | 生育及备孕 | 高 |
| med_clomiphene_citrate | 枸橼酸氯米芬 | 氯米芬 | 别名候选 | 生育及备孕 | 待OCR测试 |
| med_clomiphene_citrate | 枸橼酸氯米芬 | 克罗米芬 | 别名候选 | 生育及备孕 | 待OCR测试 |
| med_clomiphene_citrate | 枸橼酸氯米芬 | 舒经芬 | 别名候选 | 生育及备孕 | 待OCR测试 |
| med_clomiphene_citrate | 枸橼酸氯米芬 | CC | 别名候选 | 生育及备孕 | 待OCR测试 |
| supp_folic_acid | 叶酸 | 叶酸 | 标准名 | 生育及备孕 | 高 |
| supp_folic_acid | 叶酸 | 叶酸片 | 别名候选 | 生育及备孕 | 待OCR测试 |
| supp_folic_acid | 叶酸 | 维生素B9 | 别名候选 | 生育及备孕 | 待OCR测试 |
| supp_folic_acid | 叶酸 | VB9 | 别名候选 | 生育及备孕 | 待OCR测试 |
| otc_paracetamol | 对乙酰氨基酚 | 对乙酰氨基酚 | 标准名 | 感冒发烧常用 | 高 |
| otc_paracetamol | 对乙酰氨基酚 | 对乙酰氨基酚片 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_paracetamol | 对乙酰氨基酚 | 扑热息痛 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_paracetamol | 对乙酰氨基酚 | 泰诺林 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_ibuprofen | 布洛芬 | 布洛芬 | 标准名 | 感冒发烧常用 | 高 |
| otc_ibuprofen | 布洛芬 | 布洛芬片 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_ibuprofen | 布洛芬 | 布洛芬缓释胶囊 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_ibuprofen | 布洛芬 | 芬必得 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_ibuprofen | 布洛芬 | 美林 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_compound_paracetamol_amantadine | 复方氨酚烷胺制剂 | 复方氨酚烷胺制剂 | 标准名 | 感冒发烧常用 | 高 |
| otc_compound_paracetamol_amantadine | 复方氨酚烷胺制剂 | 复方氨酚烷胺片 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_compound_paracetamol_amantadine | 复方氨酚烷胺制剂 | 复方氨酚烷胺胶囊 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_compound_paracetamol_amantadine | 复方氨酚烷胺制剂 | 感康 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_compound_paracetamol_amantadine | 复方氨酚烷胺制剂 | 快克 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_dextromethorphan | 右美沙芬 | 右美沙芬 | 标准名 | 感冒发烧常用 | 高 |
| otc_dextromethorphan | 右美沙芬 | 氢溴酸右美沙芬 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_dextromethorphan | 右美沙芬 | 右美沙芬片 | 别名候选 | 感冒发烧常用 | 待OCR测试 |
| otc_dextromethorphan | 右美沙芬 | 右美沙芬糖浆 | 别名候选 | 感冒发烧常用 | 待OCR测试 |

## 5. 审核清单

| 审核ID | 审核类型 | 对象 | 任务/决定 | 负责人 | 状态 | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| R-001 | 范围 | 四类20条 | 确认类别比例与候选药品 | 产品+医学 | 待确认 | PCOS相关9条，占比最大 |
| R-002 | 身份核验 | 全部药品 | 逐条核对中国通用名、成分、剂型、规格与批准文号 | 产品+医学 | 未开始 | 选择具体上市产品后记录来源 |
| R-003 | 参考用法 | 全部药品 | 按具体说明书补充可展示的参考用法 | 医学顾问 | 未开始 | 不能作为患者提醒默认值 |
| R-004 | 实际提醒 | 后端模型 | 支持一次用量、单位、每日次数、具体时点、疗程和来源 | 技术 | 待确认 | 确认后才能创建提醒 |
| R-005 | 补充剂 | 4条 | 确认官方标签参考与手动输入并存的交互 | 产品+医学 | 待确认 | 医嘱内容优先 |
| R-006 | OCR | 全部名称和别名 | 完成正例、误匹配、冲突词测试 | 产品+技术 | 未开始 | 别名不等于识别已确认 |
| R-007 | 复方药 | 复方感冒药 | 核对复方成分，避免重复成分提醒遗漏 | 医学顾问+技术 | 未开始 | 本版不启用相互作用自动判断 |
| R-008 | Demo医嘱 | 固定模拟患者 | 单独制作患者实际用法，不从静态库生成 | 产品+医学 | 未开始 | 保留医嘱原文与确认记录 |
| R-009 | 交互 | 导入与提醒 | 确认两个动作及待确认草稿步骤 | 产品+设计 | 待确认 | 不得静默开启提醒 |
| R-010 | 候选调整 | 吡格列酮 | 决定是否替换本版其他候选 | 产品+医学 | 待讨论 | 当前仅保留在v1/移出清单 |

## 6. 字段说明

| 字段 | 中文含义 | 运行规则 | 必需性 |
| --- | --- | --- | --- |
| medication_id | 稳定药品ID | 后端归一化与关联 | 是 |
| primary_category | 四类白名单类别 | 主数据分类，不代表患者实际用途 | 是 |
| item_type | 处方药/OTC/补充剂 | 界面与审核策略 | 是 |
| aliases | OCR别名候选 | 返回候选，仍需用户确认 | 是 |
| dosage_forms | 剂型候选 | 辅助拆分医嘱，不是默认方案 | 是 |
| strength_candidates | 规格候选 | 辅助匹配，必须与原文核对 | 是 |
| administration_reference.route | 给药途径 | 参考展示与录入 | 是 |
| administration_reference.usage_text | 参考使用方法 | 说明数据来源与使用边界 | 是 |
| dose_per_intake | 一次用量参考 | 本版为空，等待具体说明书/医嘱 | 否 |
| frequency_per_day | 每日次数参考 | 本版为空，等待具体说明书/医嘱 | 否 |
| schedule_source | 实际提醒方案来源要求 | 区分医嘱、官方标签与手动输入 | 是 |
| user_editable | 用户是否可修改实际方案 | 创建提醒前的确认与补充 | 是 |
| can_prefill_reminder | 静态库能否自动创建提醒 | 本版必须为false | 是 |
| review_status | 说明书与医学审核状态 | 未通过前不能用于自动决策 | 是 |
| relation_to_pcos | 患者实际用药与PCOS关系 | 存于患者记录，不能从主表推断 | 患者字段 |
| source_document_id | 实际用法来源材料 | 支持医嘱溯源 | 患者字段 |

## 7. 技术实施底线

- 所有 OCR 匹配结果只能作为候选，必须由用户确认。
- 静态库中的 `can_prefill_reminder` 必须为 `false`。
- 患者实际用法必须保留来源：医嘱 OCR、用户手动输入或具体产品说明书。
- 药品导入与开启提醒是两个独立动作，不得静默开启提醒。
- 未通过说明书与医学审核的字段不得用于自动决策。
- PCOS 相关性属于患者实际记录字段，不能仅根据药品主表自动推断。
