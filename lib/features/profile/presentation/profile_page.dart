import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/profile/data/patient_profile_repository.dart';

String nextVisitStatus(DateTime visit, {DateTime? today}) {
  final current = today ?? DateTime.now();
  final currentDate = DateTime.utc(current.year, current.month, current.day);
  final visitDate = DateTime.utc(visit.year, visit.month, visit.day);
  final days = visitDate.difference(currentDate).inDays;
  if (days > 0) return '还有 $days 天';
  if (days == 0) return '已到复诊日期';
  return '已超过 ${days.abs()} 天';
}

DateTime? parseProfileDate(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(normalized);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

String? validateProfileDate(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty || parseProfileDate(normalized) != null) return null;
  return '请输入有效日期（YYYY-MM-DD）';
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    required this.account,
    required this.repository,
    this.onLogout,
    super.key,
  });

  final DemoAccount account;
  final PatientProfileRepository repository;
  final Future<void> Function()? onLogout;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<PatientProfile> _profile = widget.repository.get();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('profile-page'),
      color: PomiColors.surfaceMuted,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 126),
        children: [
          PomiPageHeader(
            title: '我的',
            subtitle: '患者画像、授权与认证记录',
            trailing: const DemoBadge(label: '演示账号'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: PomiColors.heroGradient,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x66FFFFFF)),
                        ),
                        child: Center(
                          child: Text(
                            widget.account.displayName.characters.first,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.account.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              '29 岁 · PCOS 3 年 · 162 cm',
                              style: TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const DemoBadge(label: 'ICD-10 E28.2'),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const Key('profile-edit-button'),
                        onPressed: () async {
                          final saved = await _showEditProfile(
                            context,
                            widget.repository,
                          );
                          if (saved && mounted) {
                            setState(() {
                              _profile = widget.repository.get();
                            });
                          }
                        },
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(
                      child: _ProfileMetric(value: '3', label: '就诊记录'),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _ProfileMetric(value: '7', label: '医疗材料'),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: _ProfileMetric(value: '2', label: '认证记录'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const PomiSectionTitle(title: '复诊安排'),
                const SizedBox(height: 8),
                PomiSectionCard(
                  child: FutureBuilder<PatientProfile>(
                    future: _profile,
                    builder: (context, snapshot) {
                      final visit = snapshot.data?.nextVisitDate;
                      final label = visit == null
                          ? '尚未设置复诊日期'
                          : '${visit.year.toString().padLeft(4, '0')}-'
                                '${visit.month.toString().padLeft(2, '0')}-'
                                '${visit.day.toString().padLeft(2, '0')}';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.event_available_outlined,
                          color: PomiColors.primary,
                        ),
                        title: Text(
                          label,
                          key: const Key('profile-next-visit'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          visit == null ? '复诊日期由你手动维护' : nextVisitStatus(visit),
                          key: const Key('profile-next-visit-status'),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                const PomiSectionTitle(title: '隐私与说明'),
                const SizedBox(height: 8),
                PomiSectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ProfileAction(
                        icon: Icons.share_outlined,
                        title: '跨院授权记录（P1）',
                        subtitle: '后续独立开发，当前不连接跨院服务',
                        onTap: () => _showNotReady(context),
                      ),
                      _ProfileAction(
                        icon: Icons.security_outlined,
                        title: '数据与隐私',
                        subtitle: '最小化采集 · 授权访问 · 审计记录',
                        last: true,
                        onTap: () => _showNotReady(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const PomiSectionTitle(title: '应用'),
                const SizedBox(height: 8),
                PomiSectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ProfileAction(
                        icon: Icons.notifications_outlined,
                        title: '提醒设置',
                        subtitle: '用药与复诊提醒',
                        onTap: () => _showNotReady(context),
                      ),
                      _ProfileAction(
                        icon: Icons.info_outline_rounded,
                        title: '关于 Pomi',
                        subtitle: '版本 0.1.0 · 演示环境',
                        onTap: () => _showNotReady(context),
                      ),
                      _ProfileAction(
                        key: const Key('logout-button'),
                        icon: Icons.logout_rounded,
                        title: '退出登录',
                        subtitle: '清除本账号的离线首页与报告缓存',
                        last: true,
                        onTap: widget.onLogout == null
                            ? () => _showNotReady(context)
                            : () => widget.onLogout!(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _showNotReady(BuildContext context) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('该设置将在后端接入阶段启用')));
  }

  static Future<bool> _showEditProfile(
    BuildContext context,
    PatientProfileRepository repository,
  ) async {
    final profile = await repository.get();
    if (!context.mounted) return false;
    return await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) =>
              _EditProfileSheet(profile: profile, repository: repository),
        ) ??
        false;
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.profile, required this.repository});

  final PatientProfile profile;
  final PatientProfileRepository repository;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nickname;
  late final TextEditingController _height;
  late final TextEditingController _nextVisit;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _nickname = TextEditingController(text: profile.nickname ?? '');
    _height = TextEditingController(text: profile.heightCm?.toString() ?? '');
    _nextVisit = TextEditingController(
      text: profile.nextVisitDate == null
          ? ''
          : '${profile.nextVisitDate!.year.toString().padLeft(4, '0')}-'
                '${profile.nextVisitDate!.month.toString().padLeft(2, '0')}-'
                '${profile.nextVisitDate!.day.toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    _nickname.dispose();
    _height.dispose();
    _nextVisit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    final profile = widget.profile;
    try {
      await widget.repository.update(
        PatientProfileInput(
          nickname: _nickname.text.trim(),
          birthDate: profile.birthDate,
          gender: profile.gender,
          heightCm: double.tryParse(_height.text.trim()),
          diagnosisYear: profile.diagnosisYear,
          primaryCondition: profile.primaryCondition,
          nextVisitDate: parseProfileDate(_nextVisit.text),
          healthGoal: profile.healthGoal,
          completeOnboarding: false,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        0,
        18,
        18 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('编辑患者画像', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nickname,
              decoration: const InputDecoration(labelText: '昵称'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _height,
              decoration: const InputDecoration(labelText: '身高（cm）'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              key: const Key('profile-next-visit-input'),
              controller: _nextVisit,
              decoration: const InputDecoration(
                labelText: '下次复诊日期',
                hintText: 'YYYY-MM-DD',
              ),
              validator: validateProfileDate,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                key: const Key('profile-save-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('profile-save-button'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存修改'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return PomiSectionCard(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: PomiColors.primary,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.last = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Color(0x126A4C93))),
        ),
        child: Row(
          children: [
            Icon(icon, color: PomiColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: PomiColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
