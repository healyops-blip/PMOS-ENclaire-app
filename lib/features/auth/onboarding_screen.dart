import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _birthYear = TextEditingController(text: '1997');
  final _height = TextEditingController(text: '162');
  final _weight = TextEditingController();
  final _diagnosisYear = TextEditingController(text: '2023');
  final _lastPeriod = TextEditingController();
  final _nextVisit = TextEditingController();
  final Set<String> _medications = {};
  int _step = 0;
  String _cycleRange = '35-45 天';
  bool _saving = false;

  static const _medicationOptions = {
    '二甲双胍': '按当前医嘱',
    '复方口服避孕药': '按当前医嘱',
    '肌醇': '按产品说明',
    '维生素 D3': '按产品说明',
    '叶酸': '按产品说明',
  };

  @override
  void dispose() {
    for (final controller in [
      _nickname,
      _birthYear,
      _height,
      _weight,
      _diagnosisYear,
      _lastPeriod,
      _nextVisit,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseDate(
    TextEditingController controller, {
    bool future = false,
  }) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: future ? now : DateTime(2000),
      lastDate: future ? DateTime(now.year + 3) : now,
      initialDate: future ? now.add(const Duration(days: 14)) : now,
    );
    if (picked != null) {
      controller.text = picked.toIso8601String().substring(0, 10);
    }
  }

  void _next() {
    if (_step == 0 && !_formKey.currentState!.validate()) return;
    setState(() => _step += 1);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.put(
        '/api/patient/profile',
        data: {
          'nickname': _nickname.text.trim(),
          'birth_date': '${_birthYear.text.trim()}-01-01',
          'height_cm': double.tryParse(_height.text),
          'diagnosis_year': int.tryParse(_diagnosisYear.text),
          'next_visit_date': _nextVisit.text.isEmpty ? null : _nextVisit.text,
          'health_goal': '整理复诊资料，并与医生高效沟通',
          'external_ocr_notice_accepted': true,
        },
      );
      final weight = double.tryParse(_weight.text.trim());
      if (weight != null) {
        await api.post(
          '/api/weights',
          data: {
            'measured_at': DateTime.now().toUtc().toIso8601String(),
            'weight_kg': weight,
            'note': '初始化资料',
          },
        );
      }
      if (_lastPeriod.text.isNotEmpty) {
        await api.post(
          '/api/cycles',
          data: {
            'start_date': _lastPeriod.text,
            'end_date': null,
            'flow_level': 'medium',
            'symptoms': <String>[],
            'note': '初始化记录 · 通常周期 $_cycleRange',
          },
        );
      }
      for (final name in _medications) {
        await api.post(
          '/api/medications',
          data: {
            'drug_name': name,
            'dosage_text': _medicationOptions[name],
            'frequency': null,
            'current_status': 'active',
          },
        );
      }
      if (mounted) context.go('/home');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [pomiLavender, Color(0xFFFAF8FC), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  _OnboardingHeader(step: _step),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: SingleChildScrollView(
                          key: ValueKey(_step),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          child:
                              [
                                _basicStep(),
                                _cycleStep(),
                                _medicationStep(),
                              ][_step],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed:
                              _saving ? null : (_step == 2 ? _save : _next),
                          child:
                              _saving
                                  ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : Text(_step == 2 ? '完成，进入首页' : '下一步'),
                        ),
                        if (_step > 0)
                          TextButton(
                            onPressed:
                                _saving
                                    ? null
                                    : () => setState(() => _step -= 1),
                            child: const Text(
                              '返回上一步',
                              style: TextStyle(color: pomiMuted),
                            ),
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
    );
  }

  Widget _basicStep() => _StepCard(
    showFrame: false,
    children: [
      TextFormField(
        controller: _nickname,
        decoration: const InputDecoration(labelText: '昵称'),
        validator:
            (value) => value == null || value.trim().isEmpty ? '请输入称呼' : null,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _birthYear,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '出生年份'),
              validator: _yearValidator,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _diagnosisYear,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '确诊年份'),
              validator: _yearValidator,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _height,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '身高',
                suffixText: 'cm',
              ),
              validator: (value) {
                final height = double.tryParse(value ?? '');
                return height == null || height < 100 || height > 230
                    ? '请输入 100–230 cm'
                    : null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '体重',
                suffixText: 'kg',
              ),
              validator: _weightValidator,
            ),
          ),
        ],
      ),
    ],
  );

  String? _yearValidator(String? value) {
    final year = int.tryParse(value ?? '');
    return year == null || year < 1940 || year > DateTime.now().year
        ? '年份不正确'
        : null;
  }

  String? _weightValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final weight = double.tryParse(value);
    return weight == null || weight < 20 || weight > 300
        ? '请输入 20–300 kg'
        : null;
  }

  Widget _cycleStep() => _StepCard(
    children: [
      TextFormField(
        controller: _lastPeriod,
        readOnly: true,
        onTap: () => _chooseDate(_lastPeriod),
        decoration: const InputDecoration(
          labelText: '最近一次经期开始日期（选填）',
          suffixIcon: Icon(Icons.calendar_today_outlined),
        ),
      ),
      const SizedBox(height: 18),
      const Text('通常周期长度', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children:
            ['21-28 天', '28-35 天', '35-45 天', '45 天以上']
                .map(
                  (value) => ChoiceChip(
                    label: Text(value),
                    selected: _cycleRange == value,
                    onSelected: (_) => setState(() => _cycleRange = value),
                  ),
                )
                .toList(),
      ),
      const SizedBox(height: 18),
      TextFormField(
        controller: _nextVisit,
        readOnly: true,
        onTap: () => _chooseDate(_nextVisit, future: true),
        decoration: const InputDecoration(
          labelText: '预计下次就诊日期（选填）',
          suffixIcon: Icon(Icons.event_available_outlined),
        ),
      ),
    ],
  );

  Widget _medicationStep() => _StepCard(
    children: [
      const Text(
        '选择当前正在使用的药品或补剂',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 6),
      const Text(
        '未列出的项目可以进入首页后手动添加。',
        style: TextStyle(color: pomiMuted, fontSize: 12),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children:
            _medicationOptions.keys
                .map(
                  (name) => FilterChip(
                    label: Text(name),
                    selected: _medications.contains(name),
                    onSelected:
                        (selected) => setState(() {
                          if (selected) {
                            _medications.add(name);
                          } else {
                            _medications.remove(name);
                          }
                        }),
                  ),
                )
                .toList(),
      ),
    ],
  );
}

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({required this.step});
  final int step;
  @override
  Widget build(BuildContext context) {
    const titles = ['基本信息', '经期情况', '当前用药'];
    const subtitles = ['', '帮助整理周期和就诊倒计时', '帮助定制日常用药管理'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              3,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: index == step ? 26 : 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: index <= step ? pomiPurple : const Color(0xFFD8D1DC),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(titles[step], style: Theme.of(context).textTheme.titleLarge),
          if (subtitles[step].isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitles[step],
              style: const TextStyle(color: pomiMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.children, this.showFrame = true});
  final List<Widget> children;
  final bool showFrame;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    return showFrame ? Card(child: content) : content;
  }
}
