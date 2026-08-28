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

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({this.onOpenRecords, super.key});

  final VoidCallback? onOpenRecords;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _darkMode = true;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
        data: (data) {
          final nickname = data['nickname']?.toString() ?? '未设置称呼';
          final birthYear = data['birth_year'] as int?;
          final age =
              birthYear == null ? null : DateTime.now().year - birthYear;
          final diagnosisYear = data['diagnosis_year'] as int?;
          final diagnosedYears =
              diagnosisYear == null
                  ? null
                  : DateTime.now().year - diagnosisYear;
          final profileSummary = [
            if (smokeMode) '模拟患者',
            if (age != null) '$age 岁',
            if (diagnosedYears != null) '已确诊 PCOS $diagnosedYears 年',
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
            children: [
              Text('我的', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [pomiPurple, pomiPurpleSoft],
                        ),
                      ),
                      child: Text(
                        nickname.characters.first,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => _showComingSoon(context, '头像修改'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: pomiPurple,
                        side: BorderSide(
                          color: pomiPurple.withValues(alpha: .20),
                        ),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('修改头像'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nickname,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    if (profileSummary.isNotEmpty)
                      Text(
                        profileSummary.join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _ProfileSettingsCard(
                children: [
                  _ProfileSettingsRow(
                    title: '个人信息',
                    subtitle: '身高 / 下次就诊日期等',
                    onTap: () => _editProfile(context, ref, data),
                  ),
                  _ProfileSettingsRow(
                    title: '全部就诊记录',
                    onTap: widget.onOpenRecords,
                  ),
                  const _ProfileSettingsDivider(sectionBreak: true),
                  _ProfileSettingsRow(
                    title: '账户安全',
                    subtitle: '密码 / 人脸 / 设备',
                    onTap: () => _showComingSoon(context, '账户安全'),
                  ),
                  _ProfileSettingsRow(
                    title: '通知',
                    subtitle: '用药提醒 / 就诊提醒',
                    onTap: () => _showComingSoon(context, '通知设置'),
                  ),
                  _ProfileSettingsRow(
                    title: '设置语言',
                    subtitle: '简体中文',
                    onTap: () => _showComingSoon(context, '语言设置'),
                  ),
                  _ProfileSettingsRow(
                    title: '夜间模式',
                    subtitle: '深色配色（即将上线）',
                    trailing: Switch(
                      value: _darkMode,
                      onChanged: (value) => setState(() => _darkMode = value),
                      activeTrackColor: pomiMint,
                      activeThumbColor: Colors.white,
                    ),
                  ),
                  const _ProfileSettingsDivider(sectionBreak: true),
                  _ProfileSettingsRow(
                    title: '隐私与数据管理',
                    onTap: () => _showComingSoon(context, '隐私与数据管理'),
                  ),
                  _ProfileSettingsRow(
                    title: '存证与签署',
                    subtitle: '文件版本存证 + 材料签署',
                    onTap: () => _showComingSoon(context, '存证与签署'),
                  ),
                  _ProfileSettingsRow(
                    title: '关于 Pomi',
                    subtitle: 'PCOS 就诊准备工具',
                    onTap: () => _showComingSoon(context, '关于 Pomi'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: () => _logout(context, ref),
                icon: const Icon(Icons.logout),
                label: const Text('退出登录'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$feature即将上线')));
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
      text: profile['birth_year']?.toString(),
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
                                    'birth_year': int.tryParse(
                                      birth.text.trim(),
                                    ),
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
                                    'updated_at': profile['updated_at'],
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

class _ProfileSettingsCard extends StatelessWidget {
  const _ProfileSettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return PomiGlassCard(
      borderRadius: 22,
      backgroundOpacity: .30,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1 &&
                children[index] is! _ProfileSettingsDivider &&
                children[index + 1] is! _ProfileSettingsDivider)
              const Divider(height: 1, color: pomiLine),
          ],
        ],
      ),
    );
  }
}

class _ProfileSettingsDivider extends StatelessWidget {
  const _ProfileSettingsDivider({this.sectionBreak = false});

  final bool sectionBreak;

  @override
  Widget build(BuildContext context) => Container(
    height: sectionBreak ? 14 : 1,
    color: sectionBreak ? Colors.transparent : pomiLine,
    alignment: Alignment.center,
    child:
        sectionBreak
            ? const Divider(height: 1, color: pomiLine)
            : const SizedBox.shrink(),
  );
}

class _ProfileSettingsRow extends StatelessWidget {
  const _ProfileSettingsRow({
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Text(title, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(width: 12),
            if (subtitle != null)
              Expanded(
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 8),
            trailing ??
                const Icon(
                  Icons.chevron_right,
                  color: pomiSecondaryText,
                  size: 19,
                ),
          ],
        ),
      ),
    );
  }
}
