import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/frosted_panel.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({required this.onLogin, super.key});

  final ValueChanged<DemoAccount> onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  DemoAccount _selected = DemoAccount.existingUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('login-page'),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(gradient: PomiColors.heroGradient),
          ),
          const Positioned(
            right: -52,
            top: 70,
            child: GlowOrb(color: Color(0x88D250F7), size: 190, blur: 52),
          ),
          const Positioned(
            left: -70,
            bottom: 96,
            child: GlowOrb(color: Color(0x66F1E584), size: 170, blur: 58),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _PomiMark(),
                      const SizedBox(height: 34),
                      FrostedPanel(
                        padding: const EdgeInsets.all(18),
                        borderRadius: BorderRadius.circular(22),
                        tintOpacity: 0.13,
                        blur: 22,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              '选择演示身份',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '两个固定账号用于验证首次使用和日常使用路径',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 14),
                            for (final account in DemoAccount.values) ...[
                              _AccountTile(
                                account: account,
                                selected: account.uid == _selected.uid,
                                onTap: () =>
                                    setState(() => _selected = account),
                              ),
                              const SizedBox(height: 10),
                            ],
                            const SizedBox(height: 4),
                            FilledButton(
                              key: const Key('demo-login-button'),
                              onPressed: () => widget.onLogin(_selected),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: PomiColors.primary,
                              ),
                              child: Text('进入 ${_selected.label}'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '公开演示账户 · 不发送真实短信 · 不建设真实账号体系\n模拟医疗数据，不构成诊断或治疗建议',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 10,
                          height: 1.6,
                        ),
                      ),
                    ],
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

class _PomiMark extends StatelessWidget {
  const _PomiMark();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFF2ECF2),
            borderRadius: BorderRadius.all(Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: SizedBox(
            width: 96,
            height: 96,
            child: Center(
              child: Text(
                'P',
                style: TextStyle(
                  color: PomiColors.primary,
                  fontSize: 54,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -6,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 16),
        Text(
          'Pomi',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Poke the Pomi, meet your body',
          style: TextStyle(color: Color(0xDDFFFFFF), fontSize: 13),
        ),
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final DemoAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.24)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: Key('account-${account.uid}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.onboardingRequired
                          ? '首次登录 · 进入患者画像初始化'
                          : '已有画像 · 直接进入 Dashboard',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
