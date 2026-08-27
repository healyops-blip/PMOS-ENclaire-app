import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';

class AuthSubmission {
  const AuthSubmission.login({
    required this.accountName,
    required this.password,
  }) : phoneNumber = null,
       registering = false;

  const AuthSubmission.register({
    required this.accountName,
    required this.password,
    this.phoneNumber,
  }) : registering = true;

  final String accountName;
  final String password;
  final String? phoneNumber;
  final bool registering;
}

enum _AuthView { login, register }

class LoginPage extends StatefulWidget {
  const LoginPage({required this.onSubmit, super.key});

  final Future<void> Function(AuthSubmission submission) onSubmit;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _accountController = TextEditingController(text: 'pomi_existing');
  final _passwordController = TextEditingController(text: 'Pomi2026!');
  final _registerAccountController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _optionalPhoneController = TextEditingController();

  _AuthView _view = _AuthView.login;
  DemoAccount _selectedAccount = DemoAccount.existingUser;
  bool _submitting = false;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    _registerAccountController.dispose();
    _registerPasswordController.dispose();
    _confirmPasswordController.dispose();
    _optionalPhoneController.dispose();
    super.dispose();
  }

  void _switchView(_AuthView view) {
    if (_view != view) setState(() => _view = view);
  }

  void _selectDemo(DemoAccount account) {
    setState(() {
      _selectedAccount = account;
      _view = _AuthView.login;
      _accountController.text = account == DemoAccount.newUser
          ? 'pomi_new'
          : 'pomi_existing';
      _passwordController.text = 'Pomi2026!';
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    late final AuthSubmission submission;
    if (_view == _AuthView.register) {
      final accountName = _registerAccountController.text.trim();
      final password = _registerPasswordController.text;
      if (accountName.length < 3) return _message('账号名至少需要 3 个字符');
      if (password.length < 8) return _message('密码至少需要 8 个字符');
      if (password != _confirmPasswordController.text) {
        return _message('两次输入的密码不一致');
      }
      submission = AuthSubmission.register(
        accountName: accountName,
        password: password,
        phoneNumber: _optionalPhoneController.text.trim().isEmpty
            ? null
            : _optionalPhoneController.text.trim(),
      );
    } else {
      if (_accountController.text.trim().isEmpty ||
          _passwordController.text.isEmpty) {
        return _message('请输入账号名和密码');
      }
      submission = AuthSubmission.login(
        accountName: _accountController.text.trim(),
        password: _passwordController.text,
      );
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(submission);
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('login-page'),
      backgroundColor: const Color(0xFFF3EEF5),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final framed = constraints.maxWidth >= 560;
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: framed ? 32 : 0,
                vertical: framed ? 28 : 0,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: framed ? 820 : constraints.maxHeight,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(framed ? 42 : 0),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF65438F),
                        Color(0xFF8264A8),
                        Color(0xFFA98EC2),
                        Color(0xFFD2C1DC),
                      ],
                    ),
                    boxShadow: framed
                        ? const [
                            BoxShadow(
                              color: Color(0x332D183D),
                              blurRadius: 48,
                              offset: Offset(0, 20),
                            ),
                          ]
                        : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      const Positioned(
                        right: -55,
                        top: 110,
                        child: _Orb(color: Color(0x66F0CFF2), size: 190),
                      ),
                      const Positioned(
                        left: -75,
                        bottom: 110,
                        child: _Orb(color: Color(0x44FFFFFF), size: 230),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const _PomiMark(),
                              const SizedBox(height: 26),
                              _GlassCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _AuthTabs(
                                      view: _view,
                                      onChanged: _switchView,
                                    ),
                                    const SizedBox(height: 22),
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 240,
                                      ),
                                      child: _view == _AuthView.login
                                          ? _LoginFields(
                                              key: const ValueKey('login'),
                                              accountController:
                                                  _accountController,
                                              passwordController:
                                                  _passwordController,
                                              onForgot: () =>
                                                  _message('演示阶段请联系管理员重置密码'),
                                            )
                                          : _RegisterFields(
                                              key: const ValueKey('register'),
                                              accountController:
                                                  _registerAccountController,
                                              passwordController:
                                                  _registerPasswordController,
                                              confirmController:
                                                  _confirmPasswordController,
                                              phoneController:
                                                  _optionalPhoneController,
                                            ),
                                    ),
                                    const SizedBox(height: 20),
                                    _PrimaryAction(
                                      label: _submitting
                                          ? '请稍候…'
                                          : _view == _AuthView.login
                                          ? '登录'
                                          : '创建账号',
                                      onPressed: _submitting ? null : _submit,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              _DemoAccess(
                                selected: _selectedAccount,
                                onSelected: _selectDemo,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '公开演示账户 · 不发送短信验证码\n模拟医疗数据，不构成诊断或治疗建议',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xCFFFFFFF),
                                  fontSize: 10,
                                  height: 1.55,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PomiMark extends StatelessWidget {
  const _PomiMark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            color: Color(0xFFF8F5F8),
            borderRadius: BorderRadius.all(Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x260E0717),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: SizedBox.square(
              dimension: 108,
              child: Transform.scale(
                scale: 1.34,
                child: Image.asset(
                  'assets/images/pomi_logo.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  semanticLabel: 'POMI 品牌标志',
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 17),
        const Text(
          '戳戳 Pomi，翻译你的身体',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _AuthTabs extends StatelessWidget {
  const _AuthTabs({required this.view, required this.onChanged});

  final _AuthView view;
  final ValueChanged<_AuthView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AuthTab(
          key: const Key('auth-login-tab'),
          label: '登录',
          selected: view == _AuthView.login,
          onTap: () => onChanged(_AuthView.login),
        ),
        const SizedBox(width: 20),
        _AuthTab(
          key: const Key('auth-register-tab'),
          label: '注册',
          selected: view == _AuthView.register,
          onTap: () => onChanged(_AuthView.register),
        ),
      ],
    );
  }
}

class _AuthTab extends StatelessWidget {
  const _AuthTab({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xBFFFFFFF),
            fontSize: selected ? 22 : 15,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _LoginFields extends StatelessWidget {
  const _LoginFields({
    required this.accountController,
    required this.passwordController,
    required this.onForgot,
    super.key,
  });

  final TextEditingController accountController;
  final TextEditingController passwordController;
  final VoidCallback onForgot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GlassTextField(
          key: const Key('auth-identifier-field'),
          label: '账号名',
          hintText: '输入唯一账号名',
          controller: accountController,
          icon: Icons.alternate_email_rounded,
        ),
        const SizedBox(height: 14),
        _GlassTextField(
          key: const Key('auth-password-field'),
          label: '密码',
          hintText: '输入密码',
          controller: passwordController,
          icon: Icons.key_rounded,
          obscureText: true,
          trailing: TextButton(onPressed: onForgot, child: const Text('忘记密码')),
        ),
      ],
    );
  }
}

class _RegisterFields extends StatelessWidget {
  const _RegisterFields({
    required this.accountController,
    required this.passwordController,
    required this.confirmController,
    required this.phoneController,
    super.key,
  });

  final TextEditingController accountController;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final TextEditingController phoneController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GlassTextField(
          key: const Key('auth-register-account-field'),
          label: '账号名',
          hintText: '至少 3 个字符，注册后不可重复',
          controller: accountController,
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 12),
        _GlassTextField(
          key: const Key('auth-register-password-field'),
          label: '密码',
          hintText: '至少 8 个字符',
          controller: passwordController,
          icon: Icons.key_rounded,
          obscureText: true,
        ),
        const SizedBox(height: 12),
        _GlassTextField(
          key: const Key('auth-register-confirm-field'),
          label: '确认密码',
          hintText: '再次输入密码',
          controller: confirmController,
          icon: Icons.verified_user_outlined,
          obscureText: true,
        ),
        const SizedBox(height: 12),
        _GlassTextField(
          key: const Key('auth-register-phone-field'),
          label: '手机号（选填，不验证）',
          hintText: '仅作为账号资料，当前不能用于登录',
          controller: phoneController,
          icon: Icons.phone_iphone_rounded,
          keyboardType: TextInputType.phone,
        ),
      ],
    );
  }
}

class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.icon,
    this.obscureText = false,
    this.trailing,
    this.keyboardType,
    super.key,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final IconData icon;
  final bool obscureText;
  final Widget? trailing;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 3, bottom: 7),
          child: Text(
            label,
            style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
            prefixIcon: Icon(icon, color: Colors.white, size: 20),
            suffixIcon: trailing,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.12),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: _border(const Color(0x66FFFFFF)),
            enabledBorder: _border(const Color(0x55FFFFFF)),
            focusedBorder: _border(Colors.white, width: 1.4),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        key: const Key('demo-login-button'),
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFDFBFD),
          foregroundColor: PomiColors.primary,
          shape: const StadiumBorder(),
          elevation: 8,
          shadowColor: const Color(0x552C173E),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _DemoAccess extends StatelessWidget {
  const _DemoAccess({required this.selected, required this.onSelected});

  final DemoAccount selected;
  final ValueChanged<DemoAccount> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final account in DemoAccount.values)
          _DemoChip(
            key: Key('account-${account.uid}'),
            account: account,
            selected: account.uid == selected.uid,
            onTap: () => onSelected(account),
          ),
      ],
    );
  }
}

class _DemoChip extends StatelessWidget {
  const _DemoChip({
    required this.account,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final DemoAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.26)
          : Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.account_circle_outlined,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                account.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
