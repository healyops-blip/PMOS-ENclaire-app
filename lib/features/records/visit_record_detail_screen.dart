import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';

enum VisitRecordCategory { lab, order, outpatient }

enum VisitVerificationState { verified, pending, unverified, archived }

enum VisitLabStatus { normal, high, low, pending }

enum VisitOrderChange { adjusted, added, pending, continued }

class VisitRecordSummaryItem {
  const VisitRecordSummaryItem({
    required this.title,
    required this.category,
    this.trailing,
  });

  final String title;
  final VisitRecordCategory category;
  final String? trailing;
}

class VisitLabResult {
  const VisitLabResult({
    required this.name,
    required this.value,
    required this.unit,
    required this.reference,
    required this.status,
  });

  final String name;
  final String value;
  final String unit;
  final String reference;
  final VisitLabStatus status;
}

class VisitOrderItem {
  const VisitOrderItem({
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.change,
    this.note,
  });

  final String name;
  final String dosage;
  final String frequency;
  final VisitOrderChange change;
  final String? note;
}

class VisitClinicalField {
  const VisitClinicalField({required this.label, required this.value});

  final String label;
  final String value;
}

class VisitRecordDetailData {
  const VisitRecordDetailData({
    required this.id,
    required this.date,
    required this.hospital,
    required this.department,
    required this.doctor,
    required this.verificationState,
    required this.verificationLabel,
    required this.verificationTitle,
    required this.verificationDetail,
    required this.summaryItems,
    this.contextLabel,
    this.historyNote,
    this.isDemo = false,
    this.clinicalFields = const [],
    this.labs = const [],
    this.orders = const [],
    this.sampleDate,
  });

  final String id;
  final String date;
  final String hospital;
  final String department;
  final String doctor;
  final String? contextLabel;
  final VisitVerificationState verificationState;
  final String verificationLabel;
  final String verificationTitle;
  final String verificationDetail;
  final String? historyNote;
  final List<VisitRecordSummaryItem> summaryItems;

  /// 是否为演示（Smoke）数据。真实后端导入的记录为 false。
  final bool isDemo;
  final List<VisitClinicalField> clinicalFields;
  final List<VisitLabResult> labs;
  final List<VisitOrderItem> orders;
  final String? sampleDate;
}

const smokeVisitRecordDetails = <VisitRecordDetailData>[
  VisitRecordDetailData(
    id: 'visit-20260826',
    date: '2026-08-26',
    hospital: '模拟医院 B',
    department: '生殖内分泌科',
    doctor: '陈医生',
    verificationState: VisitVerificationState.verified,
    verificationLabel: '来源签署已记录｜模拟',
    verificationTitle: '就诊记录快照 · 上传后版本',
    verificationDetail: '检测单 6 · 模拟医院 B · 版本 V2 · 签署 2026-08-26 10:31',
    sampleDate: '2026-08-25',
    summaryItems: [
      VisitRecordSummaryItem(
        title: '化验单',
        category: VisitRecordCategory.lab,
        trailing: '采样 2026-08-25',
      ),
      VisitRecordSummaryItem(
        title: '医嘱',
        category: VisitRecordCategory.order,
        trailing: '2026-08-26',
      ),
    ],
    isDemo: true,
    clinicalFields: [
      VisitClinicalField(label: '就诊原因', value: '复诊评估代谢指标与当前用药'),
      VisitClinicalField(label: '医生记录', value: '结合近期检测结果调整方案，按期复查。'),
    ],
    labs: [
      VisitLabResult(
        name: '空腹血糖',
        value: '5.6',
        unit: 'mmol/L',
        reference: '3.9–6.1 mmol/L',
        status: VisitLabStatus.normal,
      ),
      VisitLabResult(
        name: 'HbA1c',
        value: '5.5',
        unit: '%',
        reference: '4.0–6.0%',
        status: VisitLabStatus.normal,
      ),
      VisitLabResult(
        name: '总睾酮',
        value: '0.9',
        unit: 'ng/mL',
        reference: '0.1–0.75 ng/mL',
        status: VisitLabStatus.high,
      ),
      VisitLabResult(
        name: '甘油三酯',
        value: '1.4',
        unit: 'mmol/L',
        reference: '0.3–1.7 mmol/L',
        status: VisitLabStatus.normal,
      ),
    ],
    orders: [
      VisitOrderItem(
        name: '二甲双胍',
        dosage: '850 mg',
        frequency: '每日 1 次',
        change: VisitOrderChange.adjusted,
        note: '随餐服用；如有明显不适请联系医生。',
      ),
      VisitOrderItem(
        name: '肌醇',
        dosage: '2 g',
        frequency: '每日 1 次',
        change: VisitOrderChange.added,
      ),
      VisitOrderItem(
        name: '维生素 D3',
        dosage: '医嘱未列',
        frequency: '待确认',
        change: VisitOrderChange.pending,
      ),
    ],
  ),
  VisitRecordDetailData(
    id: 'visit-20260712',
    date: '2026-07-12',
    hospital: '模拟医院 A',
    department: '妇科',
    doctor: '李医生',
    verificationState: VisitVerificationState.pending,
    verificationLabel: '来源核验申请中',
    verificationTitle: '医院来源核验处理中',
    verificationDetail: '门诊病历与医嘱已提交，核验结果不会改变患者原始记录。',
    summaryItems: [
      VisitRecordSummaryItem(
        title: '门诊病历',
        category: VisitRecordCategory.outpatient,
      ),
      VisitRecordSummaryItem(title: '医嘱', category: VisitRecordCategory.order),
    ],
    isDemo: true,
    clinicalFields: [
      VisitClinicalField(label: '主诉', value: '月经周期延长，近两月痤疮增多'),
      VisitClinicalField(label: '记录摘要', value: '建议完成激素与代谢相关检测后复诊。'),
      VisitClinicalField(label: '复诊安排', value: '检测完成后 4–6 周内复诊'),
    ],
    orders: [
      VisitOrderItem(
        name: '二甲双胍',
        dosage: '500 mg',
        frequency: '每日 1 次',
        change: VisitOrderChange.continued,
      ),
      VisitOrderItem(
        name: '空腹血糖、HbA1c',
        dosage: '实验室检查',
        frequency: '复诊前完成',
        change: VisitOrderChange.added,
      ),
    ],
  ),
  VisitRecordDetailData(
    id: 'visit-20260620',
    date: '2026-06-20',
    hospital: '模拟医院 A',
    department: '妇科',
    doctor: '李医生',
    contextLabel: '就诊前检测',
    verificationState: VisitVerificationState.unverified,
    verificationLabel: '患者上传｜来源未核验',
    verificationTitle: '患者上传材料',
    verificationDetail: 'OCR 内容已经患者确认，但尚未取得医院来源签署。',
    sampleDate: '2026-06-18',
    summaryItems: [
      VisitRecordSummaryItem(
        title: '化验单',
        category: VisitRecordCategory.lab,
        trailing: '采样 2026-06-18',
      ),
    ],
    isDemo: true,
    labs: [
      VisitLabResult(
        name: '促黄体生成素',
        value: '12.8',
        unit: 'IU/L',
        reference: '卵泡期 2.4–12.6 IU/L',
        status: VisitLabStatus.high,
      ),
      VisitLabResult(
        name: '促卵泡生成素',
        value: '6.2',
        unit: 'IU/L',
        reference: '卵泡期 3.5–12.5 IU/L',
        status: VisitLabStatus.normal,
      ),
      VisitLabResult(
        name: '泌乳素',
        value: '18.3',
        unit: 'ng/mL',
        reference: '4.8–23.3 ng/mL',
        status: VisitLabStatus.normal,
      ),
    ],
  ),
  VisitRecordDetailData(
    id: 'visit-20260208',
    date: '2026-02-08',
    hospital: '模拟医院 A',
    department: '妇科',
    doctor: '李医生',
    verificationState: VisitVerificationState.archived,
    verificationLabel: '历史归档｜模拟',
    verificationTitle: '历史门诊记录',
    verificationDetail: '该记录来自较早版本的门诊病历归档。',
    historyNote: '此数据超过 6 个月，仅供参考，请以近期复诊结果为准。',
    summaryItems: [
      VisitRecordSummaryItem(
        title: '门诊病历',
        category: VisitRecordCategory.outpatient,
      ),
    ],
    isDemo: true,
    clinicalFields: [
      VisitClinicalField(label: '主诉', value: '月经周期不规律'),
      VisitClinicalField(label: '记录摘要', value: '建议记录周期变化并按计划复诊。'),
      VisitClinicalField(label: '随访建议', value: '如症状变化，提前就医'),
    ],
  ),
  VisitRecordDetailData(
    id: 'visit-20251214',
    date: '2025-12-14',
    hospital: '模拟医院 C',
    department: '内分泌科',
    doctor: '周医生',
    verificationState: VisitVerificationState.archived,
    verificationLabel: '历史归档｜模拟',
    verificationTitle: '历史检测材料',
    verificationDetail: '检测结果已归档，参考范围以原始报告为准。',
    historyNote: '此数据超过 6 个月，仅供参考，请勿据此自行调整用药。',
    sampleDate: '2025-12-14',
    summaryItems: [
      VisitRecordSummaryItem(
        title: '化验单',
        category: VisitRecordCategory.lab,
        trailing: '采样 2025-12-14',
      ),
    ],
    isDemo: true,
    labs: [
      VisitLabResult(
        name: '空腹胰岛素',
        value: '14.2',
        unit: 'μIU/mL',
        reference: '2.6–24.9 μIU/mL',
        status: VisitLabStatus.normal,
      ),
      VisitLabResult(
        name: '维生素 D',
        value: '18.6',
        unit: 'ng/mL',
        reference: '≥ 20 ng/mL',
        status: VisitLabStatus.low,
      ),
      VisitLabResult(
        name: '甲状腺刺激素',
        value: '2.1',
        unit: 'mIU/L',
        reference: '0.27–4.2 mIU/L',
        status: VisitLabStatus.normal,
      ),
    ],
  ),
];

class VisitRecordDetailScreen extends StatelessWidget {
  const VisitRecordDetailScreen({required this.visit, super.key});

  final VisitRecordDetailData visit;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return PomiAppBackground(
      child: Scaffold(
        key: const ValueKey('visit-record-detail-screen'),
        appBar: AppBar(
          title: const Text('就诊详情'),
          leading: IconButton(
            tooltip: '返回就诊记录',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
        ),
        body: SafeArea(
          top: false,
          child: TweenAnimationBuilder<double>(
            duration:
                disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0, end: 1),
            builder:
                (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - value)),
                    child: child,
                  ),
                ),
            child: CustomScrollView(
              key: PageStorageKey('visit-detail-${visit.id}'),
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
                  sliver: SliverList.list(
                    children: [
                      _VisitHeroCard(visit: visit),
                      const SizedBox(height: 14),
                      _VerificationCard(visit: visit),
                      if (visit.historyNote != null) ...[
                        const SizedBox(height: 14),
                        _HistoryNotice(message: visit.historyNote!),
                      ],
                      if (visit.clinicalFields.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _ClinicalSection(fields: visit.clinicalFields),
                      ],
                      if (visit.labs.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _LabSection(visit: visit),
                      ],
                      if (visit.orders.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        _OrderSection(items: visit.orders),
                      ],
                      const SizedBox(height: 18),
                      const _MedicalDisclaimer(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VisitHeroCard extends StatelessWidget {
  const _VisitHeroCard({required this.visit});

  final VisitRecordDetailData visit;

  @override
  Widget build(BuildContext context) {
    return PomiGlassCard(
      borderRadius: 26,
      backgroundOpacity: .30,
      padding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: pomiPurple.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .68),
                      ),
                    ),
                    child: const Icon(
                      Icons.event_note_rounded,
                      color: pomiPurple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          visit.date,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          visit.isDemo ? '就诊记录 · 演示数据' : '就诊记录',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                visit.hospital,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaPill(
                    icon: Icons.local_hospital_outlined,
                    label: visit.department,
                  ),
                  _MetaPill(
                    icon: Icons.person_outline_rounded,
                    label: visit.doctor,
                  ),
                  if (visit.contextLabel != null)
                    _MetaPill(
                      icon: Icons.biotech_outlined,
                      label: visit.contextLabel!,
                    ),
                ],
              ),
            ],
          ),
          if (visit.isDemo ||
              visit.verificationState == VisitVerificationState.verified)
            Positioned(
              key: const ValueKey('pomi-verified-stamp-position'),
              right: -4,
              top: 0,
              child: Semantics(
                image: true,
                label: '该报告已核验',
                child: Opacity(
                  opacity: .88,
                  child: Transform.rotate(
                    key: const ValueKey('pomi-verified-stamp-rotation'),
                    angle: -math.pi / 4,
                    child: Image.asset(
                      'assets/images/pomi_verified_stamp.png',
                      key: const ValueKey('pomi-verified-stamp'),
                      width: 132,
                      height: 132,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .35),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withValues(alpha: .55)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: pomiSecondaryText),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.visit});

  final VisitRecordDetailData visit;

  @override
  Widget build(BuildContext context) {
    final style = _verificationStyle(visit.verificationState);
    return PomiGlassCard(
      borderRadius: 22,
      backgroundOpacity: .27,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: style.background,
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, color: style.foreground, size: 24),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visit.verificationTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  visit.verificationDetail,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: style.background,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    visit.verificationLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: style.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryNotice extends StatelessWidget {
  const _HistoryNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => PomiGlassCard(
    borderRadius: 20,
    backgroundOpacity: .24,
    padding: const EdgeInsets.all(15),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.history_toggle_off_rounded,
          color: Color(0xFFB47314),
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF7A561B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.caption,
  });

  final IconData icon;
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(3, 0, 3, 10),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: pomiPurple.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: pomiPurple),
        ),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Spacer(),
        Text(caption, style: Theme.of(context).textTheme.labelSmall),
      ],
    ),
  );
}

class _ClinicalSection extends StatelessWidget {
  const _ClinicalSection({required this.fields});

  final List<VisitClinicalField> fields;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _SectionTitle(
        icon: Icons.assignment_ind_outlined,
        title: '门诊记录',
        caption: '患者可见摘要',
      ),
      PomiGlassCard(
        borderRadius: 22,
        backgroundOpacity: .30,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        child: Column(
          children: [
            for (var index = 0; index < fields.length; index++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(
                        fields[index].label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        fields[index].value,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              if (index != fields.length - 1)
                Divider(color: pomiLine.withValues(alpha: .75), height: 1),
            ],
          ],
        ),
      ),
    ],
  );
}

class _LabSection extends StatelessWidget {
  const _LabSection({required this.visit});

  final VisitRecordDetailData visit;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SectionTitle(
        icon: Icons.science_outlined,
        title: '化验结果',
        caption:
            visit.sampleDate == null
                ? '${visit.labs.length} 项'
                : '采样 ${visit.sampleDate}',
      ),
      PomiGlassCard(
        borderRadius: 22,
        backgroundOpacity: .30,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        child: Column(
          children: [
            for (var index = 0; index < visit.labs.length; index++) ...[
              _LabResultRow(result: visit.labs[index]),
              if (index != visit.labs.length - 1)
                Divider(color: pomiLine.withValues(alpha: .75), height: 1),
            ],
          ],
        ),
      ),
    ],
  );
}

class _LabResultRow extends StatelessWidget {
  const _LabResultRow({required this.result});

  final VisitLabResult result;

  @override
  Widget build(BuildContext context) {
    final status = _labStatusStyle(result.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final value = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: result.value,
                      style: TextStyle(
                        color: status.valueColor,
                        fontSize: 18,
                        height: 24 / 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: ' ${result.unit}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                key: ValueKey('lab-value-${result.name}'),
                maxLines: 1,
              ),
              const SizedBox(height: 4),
              _ReferenceLabel(
                icon: status.icon,
                label: '参考 ${result.reference}',
                color: status.valueColor,
                resultName: result.name,
              ),
            ],
          );
          final name = Text(
            result.name,
            style: Theme.of(context).textTheme.titleMedium,
          );
          if (constraints.maxWidth < 300) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [name, const SizedBox(height: 10), value],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: name),
              const SizedBox(width: 12),
              SizedBox(width: 148, child: value),
            ],
          );
        },
      ),
    );
  }
}

class _ReferenceLabel extends StatelessWidget {
  const _ReferenceLabel({
    required this.icon,
    required this.label,
    required this.color,
    required this.resultName,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String resultName;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          label,
          key: ValueKey('lab-reference-$resultName'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _OrderSection extends StatelessWidget {
  const _OrderSection({required this.items});

  final List<VisitOrderItem> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SectionTitle(
        icon: Icons.medication_outlined,
        title: '医嘱与处方',
        caption: '${items.length} 项记录',
      ),
      PomiGlassCard(
        borderRadius: 22,
        backgroundOpacity: .30,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        child: Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              _OrderRow(item: items[index]),
              if (index != items.length - 1)
                Divider(color: pomiLine.withValues(alpha: .75), height: 1),
            ],
          ],
        ),
      ),
    ],
  );
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.item});

  final VisitOrderItem item;

  @override
  Widget build(BuildContext context) {
    final style = _orderStyle(item.change);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: style.background,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  style.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: style.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${item.dosage} · ${item.frequency}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (item.note != null) ...[
            const SizedBox(height: 4),
            Text(item.note!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _MedicalDisclaimer extends StatelessWidget {
  const _MedicalDisclaimer();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: pomiMuted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            '演示记录仅用于产品功能展示，不构成诊断或治疗建议；正式结果请以医疗机构原始材料为准。',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    ),
  );
}

({Color background, Color foreground, IconData icon}) _verificationStyle(
  VisitVerificationState state,
) => switch (state) {
  VisitVerificationState.verified => (
    background: pomiMint.withValues(alpha: .14),
    foreground: const Color(0xFF118E82),
    icon: Icons.verified_user_outlined,
  ),
  VisitVerificationState.pending => (
    background: const Color(0xFFE6F2FF),
    foreground: const Color(0xFF2F79B7),
    icon: Icons.hourglass_top_rounded,
  ),
  VisitVerificationState.unverified => (
    background: const Color(0xFFF0EEF2),
    foreground: pomiSecondaryText,
    icon: Icons.person_outline_rounded,
  ),
  VisitVerificationState.archived => (
    background: pomiPurple.withValues(alpha: .10),
    foreground: pomiPurple,
    icon: Icons.inventory_2_outlined,
  ),
};

({Color valueColor, IconData icon}) _labStatusStyle(VisitLabStatus status) =>
    switch (status) {
      VisitLabStatus.normal => (
        valueColor: pomiSuccess,
        icon: Icons.check_circle_outline_rounded,
      ),
      VisitLabStatus.high => (
        valueColor: const Color(0xFFD24A54),
        icon: Icons.arrow_upward_rounded,
      ),
      VisitLabStatus.low => (
        valueColor: const Color(0xFFC77A16),
        icon: Icons.arrow_downward_rounded,
      ),
      VisitLabStatus.pending => (
        valueColor: pomiSecondaryText,
        icon: Icons.schedule_rounded,
      ),
    };

({String label, Color background, Color foreground}) _orderStyle(
  VisitOrderChange change,
) => switch (change) {
  VisitOrderChange.adjusted => (
    label: '调整',
    background: const Color(0xFFFFF1D9),
    foreground: const Color(0xFFB56E10),
  ),
  VisitOrderChange.added => (
    label: '新增',
    background: pomiMint.withValues(alpha: .13),
    foreground: const Color(0xFF118E82),
  ),
  VisitOrderChange.pending => (
    label: '待确认',
    background: const Color(0xFFFFEAE6),
    foreground: const Color(0xFFC35442),
  ),
  VisitOrderChange.continued => (
    label: '继续',
    background: pomiPurple.withValues(alpha: .09),
    foreground: pomiPurple,
  ),
};
