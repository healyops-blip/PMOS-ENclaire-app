import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/pomi_date_picker.dart';
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
  bool _medicationNotifications = true;
  bool _visitNotifications = true;
  bool _biometricLogin = false;
  Color _avatarColor = pomiPurple;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text(error.toString())),
        data: (data) {
          final rawNickname = data['nickname']?.toString().trim();
          final nickname =
              rawNickname == null || rawNickname.isEmpty
                  ? '未设置称呼'
                  : rawNickname;
          final birthYear = data['birth_year'] as int?;
          final age =
              birthYear == null ? null : DateTime.now().year - birthYear;
          final profileSummary = [
            if (age != null) '$age 岁',
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_avatarColor, pomiPurpleSoft],
                        ),
                      ),
                      child: Text(
                        nickname.characters.first,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          height: 36 / 30,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => _editAvatar(context, nickname),
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
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        children:
                            profileSummary
                                .map(
                                  (item) => Text(
                                    item,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                )
                                .toList(),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _ProfileSettingsCard(
                children: [
                  _ProfileSettingsRow(
                    title: '个人信息',
                    onTap: () => _editProfile(context, ref, data),
                  ),
                  _ProfileSettingsRow(
                    title: '全部就诊记录',
                    onTap: widget.onOpenRecords,
                  ),
                  const _ProfileSettingsDivider(sectionBreak: true),
                  _ProfileSettingsRow(
                    title: '账户安全',
                    onTap: () => _showSecuritySheet(context),
                  ),
                  _ProfileSettingsRow(
                    title: '通知',
                    onTap: () => _showNotificationSheet(context),
                  ),
                  _ProfileSettingsRow(
                    title: '设置语言',
                    onTap: () => _showLanguageSheet(context),
                  ),
                  _ProfileSettingsRow(
                    title: '夜间模式',
                    trailing: Switch(
                      value: _darkMode,
                      onChanged: (value) {
                        setState(() => _darkMode = value);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(value ? '已记录深色配色偏好' : '已记录浅色配色偏好'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      activeTrackColor: pomiMint,
                      activeThumbColor: Colors.white,
                    ),
                  ),
                  const _ProfileSettingsDivider(sectionBreak: true),
                  _ProfileSettingsRow(
                    title: '隐私与数据管理',
                    onTap: () => _showPrivacySheet(context),
                  ),
                  _ProfileSettingsRow(
                    title: '存证与签署',
                    onTap: () => _showEvidenceSheet(context),
                  ),
                  _ProfileSettingsRow(
                    title: '关于 Pomi',
                    onTap: () => _showAboutSheet(context),
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

  Future<void> _editAvatar(BuildContext context, String nickname) async {
    final colors = [
      pomiPurple,
      const Color(0xFF2F81C5),
      pomiMint,
      const Color(0xFFC78519),
    ];
    final selected = await showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '修改头像',
                  style: TextStyle(
                    fontSize: 18,
                    height: 26 / 18,
                    fontWeight: FontWeight.w800,
                    color: pomiInk,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '当前使用姓名首字作为头像，不上传个人照片。',
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                CircleAvatar(
                  radius: 34,
                  backgroundColor: _avatarColor,
                  child: Text(
                    nickname.characters.first,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      height: 34 / 28,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 14,
                  children: [
                    for (final color in colors)
                      InkWell(
                        onTap: () => Navigator.pop(sheetContext, color),
                        borderRadius: BorderRadius.circular(24),
                        child: CircleAvatar(backgroundColor: color, radius: 20),
                      ),
                  ],
                ),
              ],
            ),
          ),
    );
    if (selected != null) setState(() => _avatarColor = selected);
  }

  Future<void> _showSecuritySheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (context, setSheetState) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '账户安全',
                        style: TextStyle(
                          fontSize: 18,
                          height: 26 / 18,
                          fontWeight: FontWeight.w800,
                          color: pomiInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '管理登录方式和设备访问权限。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('修改密码'),
                        subtitle: const Text('定期更新密码，保护账户安全'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap:
                            () => _showLocalNotice(context, '修改密码需要连接账户安全服务'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('生物识别登录'),
                        subtitle: const Text('在支持的设备上快速验证身份'),
                        value: _biometricLogin,
                        onChanged: (value) {
                          setSheetState(() => _biometricLogin = value);
                          setState(() {});
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('登录设备'),
                        subtitle: const Text('当前设备 · 最近活跃'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showLocalNotice(context, '当前仅显示本设备登录状态'),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Future<void> _showNotificationSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => StatefulBuilder(
            builder:
                (context, setSheetState) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '通知设置',
                        style: TextStyle(
                          fontSize: 18,
                          height: 26 / 18,
                          fontWeight: FontWeight.w800,
                          color: pomiInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '只接收你需要的提醒。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('用药提醒'),
                        subtitle: const Text('在设定时间提醒记录每日状态'),
                        value: _medicationNotifications,
                        onChanged: (value) {
                          setSheetState(() => _medicationNotifications = value);
                          setState(() {});
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('就诊提醒'),
                        subtitle: const Text('在下次就诊前提醒准备资料'),
                        value: _visitNotifications,
                        onChanged: (value) {
                          setSheetState(() => _visitNotifications = value);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Future<void> _showLanguageSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '设置语言',
                  style: TextStyle(
                    fontSize: 18,
                    height: 26 / 18,
                    fontWeight: FontWeight.w800,
                    color: pomiInk,
                  ),
                ),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: 'zh-CN',
                  onChanged: (_) => Navigator.pop(sheetContext),
                  child: const Column(
                    children: [
                      RadioListTile<String>(
                        value: 'zh-CN',
                        title: Text('简体中文'),
                        subtitle: Text('当前应用语言'),
                      ),
                      RadioListTile<String>(
                        value: 'en-US',
                        title: Text('English'),
                        subtitle: Text('即将支持'),
                        enabled: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _showPrivacySheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '隐私与数据管理',
                  style: TextStyle(
                    fontSize: 18,
                    height: 26 / 18,
                    fontWeight: FontWeight.w800,
                    color: pomiInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '你的健康数据仅用于生成个人化就诊准备内容。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('导出我的数据'),
                  subtitle: const Text('下载可读的资料副本'),
                  onTap: () => _showLocalNotice(context, '数据导出功能将在接口接通后可用'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('清除本机缓存'),
                  subtitle: const Text('不会删除服务器上的健康记录'),
                  onTap: () => _showLocalNotice(context, '本机缓存已保持安全，不需要立即清除'),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _showEvidenceSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '存证与签署',
                  style: TextStyle(
                    fontSize: 18,
                    height: 26 / 18,
                    fontWeight: FontWeight.w800,
                    color: pomiInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '查看原件版本、来源编号和本机签署状态。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.verified_outlined, color: pomiMint),
                  title: Text('本机来源存证演示'),
                  subtitle: Text('已完成 · 不代表医院签发或真实上链'),
                ),
                FilledButton.icon(
                  onPressed:
                      widget.onOpenRecords == null
                          ? null
                          : () {
                            Navigator.pop(sheetContext);
                            widget.onOpenRecords!();
                          },
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('查看资料来源'),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _showAboutSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: pomiPurple,
                  child: Text(
                    'P',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pomi',
                  style: TextStyle(
                    fontSize: 18,
                    height: 26 / 18,
                    fontWeight: FontWeight.w800,
                    color: pomiInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'PCOS 就诊准备工具 · v0.1.0',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Text(
                  '帮助你整理资料、追踪指标，并更从容地准备下一次就诊。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('知道了'),
                ),
              ],
            ),
          ),
    );
  }

  void _showLocalNotice(BuildContext context, String message) {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
    var saving = false;
    final pageContext = context;
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
                        Text(
                          '个人信息',
                          style: Theme.of(context).textTheme.titleLarge,
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
                            labelText: '出生年份',
                            hintText: 'YYYY',
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
                          readOnly: true,
                          onTap:
                              () => _chooseDate(
                                context,
                                nextVisit,
                                title: '选择就诊日期',
                                firstDate: DateTime(2000),
                                lastDate: DateTime(
                                  DateTime.now().year + 3,
                                  DateTime.now().month,
                                  DateTime.now().day,
                                ),
                              ),
                          decoration: const InputDecoration(
                            labelText: '下次就诊日期',
                            hintText: 'YYYY-MM-DD',
                            suffixIcon: Icon(Icons.calendar_today_outlined),
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
                          title: Text(
                            '同意外部文档处理提示',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () async {
                            setSheetState(() => saving = true);
                            try {
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
                            } catch (_) {
                              if (sheetContext.mounted) {
                                setSheetState(() => saving = false);
                                ScaffoldMessenger.of(pageContext).showSnackBar(
                                  const SnackBar(
                                    content: Text('保存失败，请检查网络后重试'),
                                  ),
                                );
                              }
                            }
                          },
                          child:
                              saving
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Text('保存'),
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

  Future<void> _chooseDate(
    BuildContext context,
    TextEditingController controller, {
    required String title,
    required DateTime firstDate,
    required DateTime lastDate,
  }) async {
    final first = DateUtils.dateOnly(firstDate);
    final last = DateUtils.dateOnly(lastDate);
    final parsed = DateTime.tryParse(controller.text.trim());
    final initial = parsed ?? DateTime.now();
    final picked = await showPomiDatePicker(
      context: context,
      title: title,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) controller.text = pomiDateValue(picked);
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
    this.onTap,
    this.trailing,
  });

  final String title;
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
            Text(title, style: Theme.of(context).textTheme.titleMedium),
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
