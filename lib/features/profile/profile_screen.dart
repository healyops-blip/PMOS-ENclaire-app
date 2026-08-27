import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../auth/auth_controller.dart';

final profileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final value = await ref.read(apiClientProvider).get('/api/patient/profile');
  return Map<String, dynamic>.from(value as Map);
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
        data: (data) {
          final nickname = data['nickname']?.toString() ?? '未设置称呼';
          final birth = DateTime.tryParse(data['birth_date']?.toString() ?? '');
          final age = birth == null ? null : DateTime.now().year - birth.year;
          final diagnosisYear = data['diagnosis_year'] as int?;
          final diagnosedYears =
              diagnosisYear == null
                  ? null
                  : DateTime.now().year - diagnosisYear;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: pomiHeroGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: Colors.white.withValues(alpha: .2),
                      foregroundColor: Colors.white,
                      child: Text(
                        nickname.characters.first,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      nickname,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        'PCOS',
                        if (age != null) '$age 岁',
                        if (diagnosedYears != null) '确诊 $diagnosedYears 年',
                      ].join(' · '),
                      style: const TextStyle(
                        color: Color(0xD9FFFFFF),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0x80FFFFFF)),
                      ),
                      onPressed: () => _editProfile(context, ref, data),
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: const Text('编辑个人信息'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _ProfileSection(
                title: '健康档案',
                children: [
                  _ProfileTile(
                    label: '出生日期',
                    value: data['birth_date']?.toString() ?? '未填写',
                  ),
                  _ProfileTile(
                    label: '身高',
                    value:
                        data['height_cm'] == null
                            ? '未填写'
                            : '${data['height_cm']} cm',
                  ),
                  _ProfileTile(
                    label: '确诊年份',
                    value: data['diagnosis_year']?.toString() ?? '未填写',
                  ),
                  _ProfileTile(
                    label: '下次就诊',
                    value: data['next_visit_date']?.toString() ?? '未安排',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ProfileSection(
                title: '设置与数据',
                children: [
                  _SettingsTile(
                    icon: Icons.notifications_none_rounded,
                    title: '通知',
                    subtitle: '用药提醒与就诊提醒将在 Android 通知模块接入',
                  ),
                  _SettingsTile(
                    icon:
                        data['external_ocr_notice_accepted_at'] == null
                            ? Icons.gpp_maybe_outlined
                            : Icons.verified_user_outlined,
                    title: '外部文档处理提示',
                    subtitle:
                        data['external_ocr_notice_accepted_at'] == null
                            ? '尚未确认，不能创建识别任务'
                            : '已确认；识别结果仍须手动核对',
                    color:
                        data['external_ocr_notice_accepted_at'] == null
                            ? pomiCoral
                            : pomiSuccess,
                  ),
                  const _SettingsTile(
                    icon: Icons.verified_outlined,
                    title: '来源存证演示',
                    subtitle: '仅保存在本机，不代表医院签发或真实上链',
                  ),
                  const _SettingsTile(
                    icon: Icons.info_outline_rounded,
                    title: '关于 Pomi',
                    subtitle: 'PCOS 就诊准备工具',
                  ),
                ],
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: () => _logout(context, ref),
                icon: const Icon(Icons.logout),
                label: const Text('退出登录'),
              ),
              const SizedBox(height: 14),
              const Text(
                'Pomi 用于整理你确认过的复诊资料，不提供诊断或治疗建议。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: pomiMuted,
                  height: 16 / 11,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> profile,
  ) async {
    final nickname = TextEditingController(
      text: profile['nickname']?.toString(),
    );
    final birth = TextEditingController(
      text: profile['birth_date']?.toString(),
    );
    final height = TextEditingController(
      text: profile['height_cm']?.toString(),
    );
    final diagnosisYear = TextEditingController(
      text: profile['diagnosis_year']?.toString(),
    );
    final nextVisit = TextEditingController(
      text: profile['next_visit_date']?.toString(),
    );
    final goal = TextEditingController(
      text: profile['health_goal']?.toString(),
    );
    var accepted = profile['external_ocr_notice_accepted_at'] != null;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (context, setSheetState) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '个人信息',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: nickname,
                          decoration: const InputDecoration(labelText: '称呼'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: birth,
                          decoration: const InputDecoration(
                            labelText: '出生日期',
                            hintText: 'YYYY-MM-DD',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: height,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '身高',
                                  suffixText: 'cm',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: diagnosisYear,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '确诊年份',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: nextVisit,
                          decoration: const InputDecoration(
                            labelText: '下次就诊日期',
                            hintText: 'YYYY-MM-DD',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: goal,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: '本次健康目标',
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: accepted,
                          onChanged:
                              accepted
                                  ? null
                                  : (value) => setSheetState(
                                    () => accepted = value ?? false,
                                  ),
                          title: const Text(
                            '同意外部文档处理提示',
                            style: TextStyle(fontSize: 13),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () async {
                            await ref
                                .read(apiClientProvider)
                                .put(
                                  '/api/patient/profile',
                                  data: {
                                    'nickname': nickname.text.trim(),
                                    'birth_date':
                                        birth.text.trim().isEmpty
                                            ? null
                                            : birth.text.trim(),
                                    'height_cm': double.tryParse(height.text),
                                    'diagnosis_year': int.tryParse(
                                      diagnosisYear.text,
                                    ),
                                    'next_visit_date':
                                        nextVisit.text.trim().isEmpty
                                            ? null
                                            : nextVisit.text.trim(),
                                    'health_goal':
                                        goal.text.trim().isEmpty
                                            ? null
                                            : goal.text.trim(),
                                    'external_ocr_notice_accepted': accepted,
                                  },
                                );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext, true);
                            }
                          },
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
    for (final controller in [
      nickname,
      birth,
      height,
      diagnosisYear,
      nextVisit,
      goal,
    ]) {
      controller.dispose();
    }
    if (saved == true) ref.invalidate(profileProvider);
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('退出登录？'),
            content: const Text('本机来源存证演示状态会保留，清除应用数据后才会重置。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('退出'),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      Card(
        child: Column(
          children: List.generate(
            children.length * 2 - 1,
            (index) => index.isOdd ? const Divider() : children[index ~/ 2],
          ),
        ),
      ),
    ],
  );
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color = pomiPurple,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: CircleAvatar(
      backgroundColor: color.withValues(alpha: .1),
      foregroundColor: color,
      child: Icon(icon, size: 20),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
  );
}
