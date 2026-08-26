import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/core/widgets/pomi_surfaces.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';
import 'package:pmos_enclaire/features/certification/presentation/certification_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({required this.account, super.key});

  final DemoAccount account;

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
                            account.displayName.characters.first,
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
                              account.displayName,
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
                        onPressed: () => _showEditProfile(context),
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
                const PomiSectionCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.event_available_outlined,
                      color: PomiColors.primary,
                    ),
                    title: Text(
                      '2026-09-10',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text('距下次复诊 15 天 · 模拟医院 B'),
                    trailing: Icon(Icons.chevron_right_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                const PomiSectionTitle(title: '认证演示与隐私'),
                const SizedBox(height: 8),
                PomiSectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ProfileAction(
                        key: const Key('certification-entry'),
                        icon: Icons.verified_user_outlined,
                        title: '医院认证演示',
                        subtitle: '本地四状态 · 绑定当前材料版本',
                        badge: '仅前端',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const CertificationPage(),
                          ),
                        ),
                      ),
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
                        last: true,
                        onTap: () => _showNotReady(context),
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

  static Future<void> _showEditProfile(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('编辑患者画像', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: '林晓晴',
              decoration: const InputDecoration(labelText: '昵称'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: '162',
              decoration: const InputDecoration(labelText: '身高（cm）'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: '2026-09-10',
              decoration: const InputDecoration(labelText: '下次复诊日期'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('保存修改'),
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
    this.badge,
    this.last = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
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
            if (badge != null)
              PomiPill(label: badge!, color: PomiColors.primary),
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
