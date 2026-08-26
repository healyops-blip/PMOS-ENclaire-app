class DemoAccount {
  const DemoAccount({
    required this.uid,
    required this.label,
    required this.displayName,
    required this.onboardingRequired,
  });

  final String uid;
  final String label;
  final String displayName;
  final bool onboardingRequired;

  DemoAccount copyWith({String? displayName}) {
    return DemoAccount(
      uid: uid,
      label: label,
      displayName: displayName ?? this.displayName,
      onboardingRequired: onboardingRequired,
    );
  }

  static const newUser = DemoAccount(
    uid: 'demo-new-user',
    label: '新用户演示',
    displayName: '新朋友',
    onboardingRequired: true,
  );

  static const existingUser = DemoAccount(
    uid: 'demo-existing-user',
    label: '老用户演示',
    displayName: '林晓晴',
    onboardingRequired: false,
  );

  static const values = [newUser, existingUser];
}
