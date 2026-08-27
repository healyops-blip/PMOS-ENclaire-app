# Issue #29：不可变报告三层查看与来源追溯

## 边界

`GET /api/reports/{report_id}` 只返回该 `report_snapshot.snapshot_json` 中冻结的
`summary`、`trends`、`records` 和逐点结构化原值。接口不会用当前化验、用药、经期、
体重或病历行替换历史值。`has_updates` 仅表示当前确认数据的摘要发生变化，不修改报告。

来源按快照中的 `node_id + source_number` 与不可变 `report_source` 对齐。只有文件的当前
可用状态会在读取时检查：可用时返回仍需 Bearer Session 的明确修订下载路径；删除、缺失
或尚未就绪时返回 `unavailable`，同时保留来源编号、修订标识和快照结构化原值。报告与
材料查询都限定为当前 Session UID 所属患者。

Flutter 页面固定为三层：

1. 60 秒摘要：患者资料、自述原文或明确空状态、当前用药、最新指标、缺失/新鲜度提示、
   模拟标识和免责声明。
2. 完整趋势：单点、双点对比、三点以上趋势线和不连线的不可比散点；12 个月前数据默认
   折叠；经期、体重和本月用药记录也可追溯。
3. 来源：原值/归一化值、单位、参考范围、日期来源、新鲜度、可比性、业务记录、材料、
   明确修订和会话保护原件。

页面使用同一 Stateful/Restoration 状态保存报告 ID、层级、指标、来源、三层滚动位置和
图表变换。打开全屏原件后返回不会重新请求另一报告版本。

## 本地认证演示边界

来源层仅用 `CertificationRepository.read(document_id, revision_id)` 读取本机状态。只有
状态为 `succeeded` 才在原件区域叠加“本地认证演示 · 非真实认证”水印。该状态不写入
FastAPI、报告快照、来源响应或后续 PDF；手工记录永远不会显示医院材料或认证水印。

## 可复现验收

自动化覆盖：

- `320 × 568 @1x` 小屏：摘要、三种图形规则、历史折叠、不可比散点、手工来源、原件和
  水印路径，无 overflow 异常。
- `390 × 844 @1x` 常规逻辑屏：Dashboard → 报告 → 趋势 → 来源黄金路径。
- FastAPI：冻结值不受当前业务行变化影响、文件不可用降级、跨 UID 报告和文件拒绝访问。

执行命令：

```powershell
flutter test --no-pub test/features/reports/report_viewer_page_test.dart
flutter test --no-pub test/main_app_test.dart
$env:PYTHONPATH=(Resolve-Path backend/src).Path
python -m pytest backend/tests/test_reports_api.py -q
flutter build apk --debug --no-pub
```

真机人工检查（需要连接 Android 真机，当前自动化环境未执行，不声明通过）：

1. `flutter devices` 记录设备型号和 Android 版本。
2. `flutter run -d <device-id>` 登录演示账号，进入“复诊报告”。
3. 从摘要任一指标进入趋势，点击正常点与不可比点，打开/关闭原件后逐层返回。
4. 锁屏再解锁，确认仍是同一报告版本、指标和滚动位置。
5. 在本机认证 `succeeded` 与非成功状态各检查一次水印；截图中明确保留“演示”字样。
