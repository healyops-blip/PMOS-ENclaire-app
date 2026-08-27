import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';

class Account {
  const Account({
    required this.uid,
    required this.accountName,
    required this.accountType,
    required this.onboardingCompleted,
    required this.status,
    required this.phoneVerified,
    this.phoneNumber,
  });

  final String uid;
  final String accountName;
  final String accountType;
  final bool onboardingCompleted;
  final String status;
  final String? phoneNumber;
  final bool phoneVerified;

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      uid: json['uid'] as String,
      accountName: json['account_name'] as String,
      accountType: json['account_type'] as String,
      onboardingCompleted: json['onboarding_completed'] as bool,
      status: json['status'] as String,
      phoneNumber: json['phone_number'] as String?,
      phoneVerified: json['phone_verified'] as bool,
    );
  }

  DemoAccount toPresentationAccount() {
    final demoExisting = uid == 'preset-existing-user';
    final demoNew = uid == 'preset-new-user';
    return DemoAccount(
      uid: uid,
      label: demoExisting
          ? '老用户演示'
          : demoNew
          ? '新用户演示'
          : '真实账号',
      displayName: demoExisting ? '林晓晴' : accountName,
      onboardingRequired: !onboardingCompleted,
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.sessionId,
    required this.expiresAt,
    required this.account,
  });

  final String sessionId;
  final DateTime expiresAt;
  final Account account;
}

class AuthFailure implements Exception {
  const AuthFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
