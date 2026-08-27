import 'package:flutter/material.dart';
import 'package:pmos_enclaire/core/theme/pomi_theme.dart';
import 'package:pmos_enclaire/core/widgets/demo_badge.dart';
import 'package:pmos_enclaire/features/auth/domain/demo_account.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    required this.account,
    required this.onCompleted,
    super.key,
  });

  final DemoAccount account;
  final ValueChanged<String> onCompleted;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _basicFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: '林晓晴');
  final _birthController = TextEditingController(text: '1997');
  final _diagnosisController = TextEditingController(text: '2023');
  final _heightController = TextEditingController(text: '162');
  final _lastPeriodController = TextEditingController(text: '2026-08-06');
  final _nextVisitController = TextEditingController(text: '2026-09-10');

  int _step = 0;
  String _gender = '女性';
  String _cycleLength = '35-45 天';
  String _periodLength = '4-5 天';
  String _managementGoal = '准备复诊材料';
  final Set<String> _medications = {'二甲双胍', '维生素 D3'};

  @override
  void dispose() {
    _nameController.dispose();
    _birthController.dispose();
    _diagnosisController.dispose();
    _heightController.dispose();
    _lastPeriodController.dispose();
    _nextVisitController.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && !_basicFormKey.currentState!.validate()) return;
    if (_step < 3) {
      setState(() => _step += 1);
      return;
    }
    widget.onCompleted(_nameController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['基本信息', '经期信息', '当前用药', '管理目标'];
    final subtitles = [
      '帮助医生了解你的基本情况',
      '后续可以随时修改',
      '确认目前正在使用的药品',
      '选择你最希望 Pomi 帮助的方向',
    ];

    return Scaffold(
      key: const Key('onboarding-page'),
      backgroundColor: PomiColors.primaryPale,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const DemoBadge(label: '首次使用'),
                  const Spacer(),
                  Text(
                    '${_step + 1} / 4',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: List.generate(4, (index) {
                  return Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 5,
                      margin: EdgeInsets.only(right: index == 3 ? 0 : 7),
                      decoration: BoxDecoration(
                        color: index <= _step
                            ? PomiColors.primary
                            : const Color(0xFFD3CCD6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        titles[_step],
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitles[_step],
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 20),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: switch (_step) {
                          0 => _BasicInfoStep(
                            key: const ValueKey('basic-info'),
                            formKey: _basicFormKey,
                            nameController: _nameController,
                            birthController: _birthController,
                            diagnosisController: _diagnosisController,
                            heightController: _heightController,
                            gender: _gender,
                            onGenderChanged: (value) =>
                                setState(() => _gender = value),
                          ),
                          1 => _CycleInfoStep(
                            key: const ValueKey('cycle-info'),
                            lastPeriodController: _lastPeriodController,
                            nextVisitController: _nextVisitController,
                            cycleLength: _cycleLength,
                            periodLength: _periodLength,
                            onCycleChanged: (value) =>
                                setState(() => _cycleLength = value),
                            onPeriodChanged: (value) =>
                                setState(() => _periodLength = value),
                          ),
                          2 => _MedicationStep(
                            key: const ValueKey('medication-info'),
                            selected: _medications,
                            onChanged: (name, selected) {
                              setState(() {
                                if (selected) {
                                  _medications.add(name);
                                } else {
                                  _medications.remove(name);
                                }
                              });
                            },
                          ),
                          _ => _GoalStep(
                            key: const ValueKey('management-goal'),
                            selected: _managementGoal,
                            onChanged: (value) =>
                                setState(() => _managementGoal = value),
                          ),
                        },
                      ),
                      const SizedBox(height: 12),
                      const _PrivacyNote(),
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('onboarding-next'),
                        onPressed: _next,
                        child: Text(_step == 3 ? '完成，进入首页' : '下一步'),
                      ),
                      if (_step > 0)
                        TextButton(
                          onPressed: () => setState(() => _step -= 1),
                          child: const Text('返回上一步'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BasicInfoStep extends StatelessWidget {
  const _BasicInfoStep({
    required this.formKey,
    required this.nameController,
    required this.birthController,
    required this.diagnosisController,
    required this.heightController,
    required this.gender,
    required this.onGenderChanged,
    super.key,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController birthController;
  final TextEditingController diagnosisController;
  final TextEditingController heightController;
  final String gender;
  final ValueChanged<String> onGenderChanged;

  @override
  Widget build(BuildContext context) {
    return _FormCard(
      child: Form(
        key: formKey,
        child: Column(
          children: [
            _Field(
              label: '昵称',
              controller: nameController,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写昵称' : null,
            ),
            _Field(
              label: '出生年份',
              controller: birthController,
              keyboardType: TextInputType.number,
              validator: _yearValidator,
            ),
            _Field(
              label: 'PCOS 确诊年份',
              controller: diagnosisController,
              keyboardType: TextInputType.number,
              validator: _yearValidator,
            ),
            _Field(
              label: '身高（cm）',
              controller: heightController,
              keyboardType: TextInputType.number,
              validator: (value) {
                final height = double.tryParse(value ?? '');
                return height == null || height < 100 || height > 230
                    ? '请输入有效身高'
                    : null;
              },
            ),
            const _FieldLabel('性别'),
            _ChoiceWrap(
              values: const ['女性', '男性', '其他', '暂不填写'],
              selected: gender,
              onChanged: onGenderChanged,
            ),
          ],
        ),
      ),
    );
  }

  static String? _yearValidator(String? value) {
    final year = int.tryParse(value ?? '');
    return year == null || year < 1900 || year > 2026 ? '请输入有效年份' : null;
  }
}

class _CycleInfoStep extends StatelessWidget {
  const _CycleInfoStep({
    required this.lastPeriodController,
    required this.nextVisitController,
    required this.cycleLength,
    required this.periodLength,
    required this.onCycleChanged,
    required this.onPeriodChanged,
    super.key,
  });

  final TextEditingController lastPeriodController;
  final TextEditingController nextVisitController;
  final String cycleLength;
  final String periodLength;
  final ValueChanged<String> onCycleChanged;
  final ValueChanged<String> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    return _FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(label: '最近一次经期开始日期', controller: lastPeriodController),
          const _FieldLabel('通常周期长度'),
          _ChoiceWrap(
            values: const ['21-28 天', '28-35 天', '35-45 天', '45 天以上'],
            selected: cycleLength,
            onChanged: onCycleChanged,
          ),
          const SizedBox(height: 16),
          const _FieldLabel('经期持续天数'),
          _ChoiceWrap(
            values: const ['1-3 天', '4-5 天', '6-7 天', '7 天以上'],
            selected: periodLength,
            onChanged: onPeriodChanged,
          ),
          const SizedBox(height: 16),
          _Field(
            label: '预计下次复诊日期',
            controller: nextVisitController,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _MedicationStep extends StatelessWidget {
  const _MedicationStep({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final Set<String> selected;
  final void Function(String name, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    const options = ['二甲双胍', '优思明', '维生素 D3', '肌醇', '其他药物'];
    return _FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('搜索并添加药品'),
          const TextField(
            decoration: InputDecoration(
              hintText: '例如搜索「优思明」或「二甲双胍」',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                FilterChip(
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: (value) => onChanged(option, value),
                  selectedColor: PomiColors.primary,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected.contains(option)
                        ? Colors.white
                        : PomiColors.text,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '用药按多囊用药、日常补剂和其他药分组，医生需关注全局用药。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _GoalStep extends StatelessWidget {
  const _GoalStep({required this.selected, required this.onChanged, super.key});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const goals = [
      ('准备复诊材料', '把化验、用药、周期和体重整理成医生易读的报告'),
      ('坚持日常记录', '通过轻量提醒维护用药、经期和体重数据'),
      ('看懂身体趋势', '在不提供诊断的前提下查看可追溯的变化'),
    ];
    return _FormCard(
      child: Column(
        children: [
          for (final goal in goals)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: selected == goal.$1
                    ? PomiColors.primary.withValues(alpha: 0.09)
                    : PomiColors.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => onChanged(goal.$1),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        Icon(
                          selected == goal.$1
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: selected == goal.$1
                              ? PomiColors.primary
                              : PomiColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goal.$1,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                goal.$2,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
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

class _FormCard extends StatelessWidget {
  const _FormCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x146A4C93)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A4A2E6B),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.validator,
    this.last = false,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            validator: validator,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _ChoiceWrap extends StatelessWidget {
  const _ChoiceWrap({
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(value),
            selected: value == selected,
            onSelected: (_) => onChanged(value),
            selectedColor: PomiColors.primary,
            labelStyle: TextStyle(
              color: value == selected ? Colors.white : PomiColors.textMuted,
            ),
          ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: PomiColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: PomiColors.primary, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '仅收集最小字段；画像不收集真实姓名、身份证号和地址，选填手机号仅作为账号资料。',
              style: TextStyle(color: PomiColors.textMuted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
