import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/frosted_panel.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';

enum _AuthView { login, register }

enum _LoginMethod { password, code }

class LoginPage extends StatefulWidget {
  const LoginPage({required this.onLogin, super.key});

  final ValueChanged<DemoAccount> onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  DemoAccount _selected = DemoAccount.existingUser;
  _AuthView _view = _AuthView.login;
  _LoginMethod _loginMethod = _LoginMethod.password;
  bool _obscurePassword = true;
  bool _codeRequested = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _switchView(_AuthView view) {
    if (_view == view) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _view = view;
      _codeRequested = false;
    });
  }

  void _requestCode() {
    final value = _view == _AuthView.register
        ? _phoneController.text
        : _identifierController.text;
    if (value.trim().isEmpty) {
      _showMessage(_view == _AuthView.register ? '请先输入手机号' : '请先输入用户名或手机号');
      return;
    }
    setState(() => _codeRequested = true);
    _showMessage('演示验证码已发送：2026');
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    if (_view == _AuthView.register) {
      final phone = _phoneController.text.replaceAll(' ', '');
      if (phone.length != 11) {
        _showMessage('请输入 11 位手机号');
        return;
      }
      if (_codeController.text.trim().isEmpty) {
        _showMessage('请输入短信验证码');
        return;
      }
      widget.onLogin(DemoAccount.newUser);
      return;
    }
    widget.onLogin(_selected);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          width: 300,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('login-page'),
      backgroundColor: const Color(0xFFF4F0F6),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final framed = constraints.maxWidth >= 560;
          final verticalInset = framed ? 22.0 : 0.0;
          final minHeight = constraints.maxHeight - verticalInset * 2;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: framed ? 24 : 0,
              vertical: verticalInset,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(framed ? 46 : 0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minHeight),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF65438F),
                                  Color(0xFF8264A8),
                                  Color(0xFFA98EC2),
                                  Color(0xFFD2C1DC),
                                ],
                                stops: [0, 0.38, 0.72, 1],
                              ),
                            ),
                          ),
                        ),
                        const Positioned(
                          top: -70,
                          right: -70,
                          child: GlowOrb(
                            color: Color(0x55E3C9FF),
                            size: 230,
                            blur: 65,
                          ),
                        ),
                        const Positioned(
                          bottom: 40,
                          left: -100,
                          child: GlowOrb(
                            color: Color(0x55F2DCEB),
                            size: 260,
                            blur: 75,
                          ),
                        ),
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _ModeHeader(
                                  view: _view,
                                  onChanged: _switchView,
                                ),
                                const SizedBox(height: 34),
                                const _PomiMark(),
                                const SizedBox(height: 28),
                                FrostedPanel(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    20,
                                    20,
                                    18,
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                  tintOpacity: 0.16,
                                  borderOpacity: 0.3,
                                  blur: 30,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        child: _view == _AuthView.login
                                            ? _LoginFields(
                                                key: const ValueKey('login'),
                                                identifierController:
                                                    _identifierController,
                                                passwordController:
                                                    _passwordController,
                                                codeController: _codeController,
                                                method: _loginMethod,
                                                obscurePassword:
                                                    _obscurePassword,
                                                codeRequested: _codeRequested,
                                                onMethodChanged: (value) {
                                                  setState(() {
                                                    _loginMethod = value;
                                                    _codeRequested = false;
                                                  });
                                                },
                                                onTogglePassword: () =>
                                                    setState(
                                                      () => _obscurePassword =
                                                          !_obscurePassword,
                                                    ),
                                                onRequestCode: _requestCode,
                                                onForgotPassword: () =>
                                                    _showMessage(
                                                      '密码找回功能将在账号服务接入后开放',
                                                    ),
                                              )
                                            : _RegisterFields(
                                                key: const ValueKey('register'),
                                                phoneController:
                                                    _phoneController,
                                                codeController: _codeController,
                                                codeRequested: _codeRequested,
                                                onRequestCode: _requestCode,
                                              ),
                                      ),
                                      const SizedBox(height: 18),
                                      _PrimaryAction(
                                        key: const Key('demo-login-button'),
                                        label: _view == _AuthView.login
                                            ? '登录'
                                            : '注册并继续',
                                        onPressed: _submit,
                                      ),
                                      const SizedBox(height: 14),
                                      _InlineSwitch(
                                        view: _view,
                                        onChanged: _switchView,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _DemoAccess(
                                  selected: _selected,
                                  onSelected: (account) =>
                                      setState(() => _selected = account),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '公开演示账户 · 不发送真实短信 · 不建设真实账号体系\n'
                                  '模拟医疗数据，不构成诊断或治疗建议',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
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
            ),
          );
        },
      ),
    );
  }
}

class _ModeHeader extends StatelessWidget {
  const _ModeHeader({required this.view, required this.onChanged});

  final _AuthView view;
  final ValueChanged<_AuthView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Pomi',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const Spacer(),
        _HeaderAction(
          key: const Key('auth-login-tab'),
          label: '登录',
          selected: view == _AuthView.login,
          onTap: () => onChanged(_AuthView.login),
        ),
        const SizedBox(width: 8),
        _HeaderAction(
          key: const Key('auth-register-tab'),
          label: '注册',
          selected: view == _AuthView.register,
          onTap: () => onChanged(_AuthView.register),
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
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
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.2)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: selected ? 1 : 0.72),
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
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
          child: const SizedBox.square(
            dimension: 94,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  'P',
                  style: TextStyle(
                    color: Color(0xFF8A68B6),
                    fontSize: 58,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -8,
                  ),
                ),
                Positioned(
                  top: 27,
                  right: 31,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFF8F5F8),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(dimension: 7),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '戳戳 Pomi，翻译你的身体',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _LoginFields extends StatelessWidget {
  const _LoginFields({
    required this.identifierController,
    required this.passwordController,
    required this.codeController,
    required this.method,
    required this.obscurePassword,
    required this.codeRequested,
    required this.onMethodChanged,
    required this.onTogglePassword,
    required this.onRequestCode,
    required this.onForgotPassword,
    super.key,
  });

  final TextEditingController identifierController;
  final TextEditingController passwordController;
  final TextEditingController codeController;
  final _LoginMethod method;
  final bool obscurePassword;
  final bool codeRequested;
  final ValueChanged<_LoginMethod> onMethodChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onRequestCode;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '欢迎回来',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '登录后继续查看你的健康记录',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        _LoginMethodSwitch(method: method, onChanged: onMethodChanged),
        const SizedBox(height: 15),
        _GlassTextField(
          key: const Key('auth-identifier-field'),
          controller: identifierController,
          label: '用户名 / 手机号',
          hintText: '输入用户名或 11 位手机号',
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: method == _LoginMethod.password
              ? _GlassTextField(
                  key: const Key('auth-password-field'),
                  controller: passwordController,
                  label: '密码',
                  hintText: '输入登录密码',
                  icon: Icons.key_rounded,
                  obscureText: obscurePassword,
                  suffix: IconButton(
                    tooltip: obscurePassword ? '显示密码' : '隐藏密码',
                    onPressed: onTogglePassword,
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: Colors.white.withValues(alpha: 0.72),
                      size: 20,
                    ),
                  ),
                )
              : _GlassTextField(
                  key: const Key('auth-code-field'),
                  controller: codeController,
                  label: '验证码',
                  hintText: '输入短信验证码',
                  icon: Icons.shield_outlined,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  suffix: _CodeButton(
                    requested: codeRequested,
                    onPressed: onRequestCode,
                  ),
                ),
        ),
        if (method == _LoginMethod.password) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onForgotPassword,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.82),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('忘记密码？'),
            ),
          ),
        ],
      ],
    );
  }
}

class _RegisterFields extends StatelessWidget {
  const _RegisterFields({
    required this.phoneController,
    required this.codeController,
    required this.codeRequested,
    required this.onRequestCode,
    super.key,
  });

  final TextEditingController phoneController;
  final TextEditingController codeController;
  final bool codeRequested;
  final VoidCallback onRequestCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '创建账号',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '使用手机号注册，验证码仅用于身份确认',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 18),
        _GlassTextField(
          key: const Key('auth-phone-field'),
          controller: phoneController,
          label: '手机号',
          hintText: '输入 11 位手机号',
          icon: Icons.phone_iphone_rounded,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          maxLength: 11,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
        _GlassTextField(
          key: const Key('auth-register-code-field'),
          controller: codeController,
          label: '验证码',
          hintText: '输入短信验证码',
          icon: Icons.shield_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          suffix: _CodeButton(
            requested: codeRequested,
            onPressed: onRequestCode,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '注册即代表你已阅读并同意《用户协议》和《隐私政策》',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _LoginMethodSwitch extends StatelessWidget {
  const _LoginMethodSwitch({required this.method, required this.onChanged});

  final _LoginMethod method;
  final ValueChanged<_LoginMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _MethodOption(
                key: const Key('auth-password-mode'),
                label: '密码登录',
                selected: method == _LoginMethod.password,
                onTap: () => onChanged(_LoginMethod.password),
              ),
            ),
            Expanded(
              child: _MethodOption(
                key: const Key('auth-code-mode'),
                label: '验证码登录',
                selected: method == _LoginMethod.code,
                onTap: () => onChanged(_LoginMethod.code),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodOption extends StatelessWidget {
  const _MethodOption({
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
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1A2C173E),
                    blurRadius: 14,
                    offset: Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected
                ? PomiColors.primary
                : Colors.white.withValues(alpha: 0.72),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.maxLength,
    this.inputFormatters,
    this.suffix,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(19),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
    );

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      cursorColor: Colors.white,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        counterText: '',
        labelStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.82),
          fontSize: 12,
        ),
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.48),
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.82),
          size: 20,
        ),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 46),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: Colors.white, width: 1.4),
        ),
      ),
    );
  }
}

class _CodeButton extends StatelessWidget {
  const _CodeButton({required this.requested, required this.onPressed});

  final bool requested;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: const Key('request-code-button'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        requested ? '重新发送' : '获取验证码',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFDFBFD),
          foregroundColor: PomiColors.primary,
          elevation: 0,
          padding: const EdgeInsets.fromLTRB(24, 4, 7, 4),
          shape: const StadiumBorder(),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                color: PomiColors.primary,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: 44,
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineSwitch extends StatelessWidget {
  const _InlineSwitch({required this.view, required this.onChanged});

  final _AuthView view;
  final ValueChanged<_AuthView> onChanged;

  @override
  Widget build(BuildContext context) {
    final isLogin = view == _AuthView.login;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isLogin ? '还没有账号？' : '已经有账号？',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 12,
          ),
        ),
        TextButton(
          onPressed: () =>
              onChanged(isLogin ? _AuthView.register : _AuthView.login),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(
            isLogin ? '手机号注册' : '返回登录',
            style: const TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DemoAccess extends StatelessWidget {
  const _DemoAccess({required this.selected, required this.onSelected});

  final DemoAccount selected;
  final ValueChanged<DemoAccount> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '快捷体验',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var index = 0; index < DemoAccount.values.length; index++) ...[
              if (index > 0) const SizedBox(width: 10),
              Expanded(
                child: _DemoChip(
                  account: DemoAccount.values[index],
                  selected: selected.uid == DemoAccount.values[index].uid,
                  onTap: () => onSelected(DemoAccount.values[index]),
                ),
              ),
            ],
          ],
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
  });

  final DemoAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: Key('account-${account.uid}'),
      color: selected
          ? Colors.white.withValues(alpha: 0.22)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                account.onboardingRequired
                    ? Icons.auto_awesome_rounded
                    : Icons.favorite_outline_rounded,
                color: Colors.white,
                size: 15,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  account.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
