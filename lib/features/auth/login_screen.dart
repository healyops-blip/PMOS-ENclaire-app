import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _agreedToTerms = false;
  bool _isRegisterMode = false;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先阅读并同意相关服务条款和隐私政策')));
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(authControllerProvider.notifier);
    if (_isRegisterMode) {
      await controller.register(_account.text.trim(), _password.text);
    } else {
      await controller.login(_account.text.trim(), _password.text);
    }
    if (!mounted) return;
    final state = ref.read(authControllerProvider);
    if (state.hasError) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 18, 32, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        child: Container(
                          width: 96,
                          height: 96,
                          margin: const EdgeInsets.only(bottom: 12),
                          color: Colors.transparent,
                          child: Opacity(
                            opacity: 0.7,
                            child: SvgPicture.asset(
                              'assets/brand/POMI-logo-mark.svg',
                              fit: BoxFit.contain,
                              semanticsLabel: 'POMI Logo',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '戳戳POMI，翻译你的身体',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: pomiInk,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _GlassField(
                            controller: _account,
                            hint: '账   号',
                            textInputAction: TextInputAction.next,
                            validator: _validateAccountName,
                          ),
                          const SizedBox(height: 24),
                          _GlassField(
                            controller: _password,
                            hint: '密   码',
                            obscureText: true,
                            onSubmitted: (_) => _submit(),
                            validator: _validatePassword,
                          ),
                          const SizedBox(height: 14),
                          _AgreementRow(
                            value: _agreedToTerms,
                            registering: _isRegisterMode,
                            onChanged:
                                (value) => setState(
                                  () => _agreedToTerms = value ?? false,
                                ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: pomiPurple,
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: auth.isLoading ? null : _submit,
                            child:
                                auth.isLoading
                                    ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : Text(
                                      _isRegisterMode ? '注册并登录' : '登录',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: TextButton(
                              onPressed:
                                  auth.isLoading
                                      ? null
                                      : () => setState(
                                        () =>
                                            _isRegisterMode = !_isRegisterMode,
                                      ),
                              child: Text(
                                _isRegisterMode ? '已有账号？直接登录' : '还没有账号？注册新账号',
                                style: const TextStyle(
                                  color: pomiMuted,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateAccountName(String? value) {
    final accountName = value?.trim().toLowerCase() ?? '';
    if (accountName.length < 3 || accountName.length > 64) {
      return '账号长度需为 3～64 个字符';
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9_.-]*$').hasMatch(accountName)) {
      return '仅支持小写字母、数字、点、下划线和短横线';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return '请输入密码';
    if (!_isRegisterMode) return null;
    if (password.length < 8 || password.length > 128) {
      return '密码长度需为 8～128 个字符';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return '密码至少包含一个字母和一个数字';
    }
    return null;
  }
}

class _AgreementRow extends StatelessWidget {
  const _AgreementRow({
    required this.value,
    required this.registering,
    required this.onChanged,
  });

  final bool value;
  final bool registering;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    const normalStyle = TextStyle(color: pomiInk, fontSize: 10, height: 1.55);
    const policyStyle = TextStyle(
      color: pomiPurple,
      fontSize: 10,
      height: 1.55,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: pomiPurple,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: const BorderSide(color: pomiMuted, width: 1.4),
              checkColor: Colors.white,
              fillColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.selected)
                        ? pomiMuted
                        : Colors.transparent,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: normalStyle,
                children: [
                  TextSpan(text: '  您已阅读并同意'),
                  TextSpan(text: '《服务条款》', style: policyStyle),
                  TextSpan(text: '《囊搭基本功能隐私政策》', style: policyStyle),
                  TextSpan(text: '《囊搭账号服务个人信息处理规则》', style: policyStyle),
                  TextSpan(text: '《模型数据采集条款》', style: policyStyle),
                  TextSpan(text: registering ? '；注册成功后将自动登录' : ''),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  const _GlassField({
    required this.controller,
    required this.hint,
    required this.validator,
    this.textInputAction,
    this.obscureText = false,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String hint;
  final String? Function(String?) validator;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: TextFormField(
        controller: controller,
        textInputAction: textInputAction,
        obscureText: obscureText,
        onFieldSubmitted: onSubmitted,
        autocorrect: false,
        textAlign: TextAlign.center,
        style: const TextStyle(color: pomiInk, fontWeight: FontWeight.w700),
        cursorColor: pomiPurple,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: pomiMuted,
            fontWeight: FontWeight.w700,
          ),
          filled: true,
          fillColor: pomiPaper,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: pomiLine),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: pomiPurple, width: 1.4),
          ),
          errorStyle: const TextStyle(
            color: Color(0xFFC62828),
            fontSize: 10,
            height: 1.1,
          ),
          errorMaxLines: 1,
        ),
        validator: validator,
      ),
    );
  }
}
