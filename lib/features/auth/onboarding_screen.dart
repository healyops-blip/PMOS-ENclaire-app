import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';

const _onboardingContentPadding = EdgeInsets.all(16);
const _onboardingFieldSlotHeight = 76.0;
const _onboardingSectionGap = 16.0;
const _onboardingLabelGap = 8.0;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _birthYear = TextEditingController(text: '1997');
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _diagnosisYear = TextEditingController(text: '2023');
  final _lastPeriod = TextEditingController();
  final _nextVisit = TextEditingController();
  final Set<String> _medications = {};
  final List<String> _customCycleRanges = [];
  final List<String> _customMedicationOptions = [];
  int _step = 0;
  String _cycleRange = '35-45 天';
  bool _saving = false;

  static const _cycleOptions = ['21-28 天', '28-35 天', '35-45 天', '45 天以上'];

  static const _medicationOptions = {
    '二甲双胍': '按当前医嘱',
    '复方口服避孕药': '按当前医嘱',
    '肌醇': '按产品说明',
    '维生素 D3': '按产品说明',
    '叶酸': '按产品说明',
  };

  Future<void> _addCycleRange() async {
    final value = await showDialog<String>(
      context: context,
      builder:
          (context) => const _AddItemDialog(
            title: '添加月经周期',
            label: '周期长度',
            hint: '例如：30-40 天',
          ),
    );
    if (value == null) return;
    var normalized = value.trim();
    if (!normalized.contains('天')) normalized = '$normalized 天';
    if (!_cycleOptions.contains(normalized) &&
        !_customCycleRanges.contains(normalized)) {
      _customCycleRanges.add(normalized);
    }
    setState(() => _cycleRange = normalized);
  }

  Future<void> _addMedication() async {
    final value = await showDialog<String>(
      context: context,
      builder:
          (context) => const _AddItemDialog(
            title: '添加药品或补剂',
            label: '名称',
            hint: '输入药品或补剂名称',
          ),
    );
    if (value == null) return;
    final normalized = value.trim();
    if (!_medicationOptions.containsKey(normalized) &&
        !_customMedicationOptions.contains(normalized)) {
      _customMedicationOptions.add(normalized);
    }
    setState(() => _medications.add(normalized));
  }

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
    final today = DateTime(now.year, now.month, now.day);
    final minimumDate = future ? today : DateTime(2000);
    final maximumDate =
        future ? DateTime(now.year + 3, now.month, now.day) : today;
    final parsedDate = DateTime.tryParse(controller.text);
    final selectedDate =
        parsedDate != null &&
                !parsedDate.isBefore(minimumDate) &&
                !parsedDate.isAfter(maximumDate)
            ? parsedDate
            : future
            ? today.add(const Duration(days: 14))
            : today;

    final picked = await showDialog<DateTime>(
      context: context,
      builder:
          (context) => _DatePickerCard(
            title: future ? '选择就诊日期' : '选择经期日期',
            initialDate: selectedDate,
            minimumDate: minimumDate,
            maximumDate: maximumDate,
          ),
    );
    if (picked != null) {
      controller.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _chooseYear(
    TextEditingController controller, {
    required int fallbackYear,
  }) async {
    final currentYear = DateTime.now().year;
    const firstYear = 1940;
    final initialYear =
        (int.tryParse(controller.text) ?? fallbackYear)
            .clamp(firstYear, currentYear)
            .toInt();
    var selectedYear = initialYear;
    final scrollController = FixedExtentScrollController(
      initialItem: initialYear - firstYear,
    );

    final picked = await showDialog<int>(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 276),
              child: SizedBox(
                height: 330,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          const Text(
                            '选择年份',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextButton(
                            onPressed:
                                () => Navigator.pop(context, selectedYear),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: scrollController,
                        itemExtent: 44,
                        useMagnifier: true,
                        magnification: 1.08,
                        selectionOverlay: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: pomiLavender.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: pomiLine),
                          ),
                        ),
                        onSelectedItemChanged:
                            (index) => selectedYear = firstYear + index,
                        children: [
                          for (
                            var year = firstYear;
                            year <= currentYear;
                            year++
                          )
                            Center(child: Text('$year 年')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
    scrollController.dispose();
    if (picked != null) setState(() => controller.text = '$picked');
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
            'dosage_text': _medicationOptions[name] ?? '用户自定义',
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
                  _OnboardingHeader(
                    step: _step,
                    onBack:
                        _step == 0 || _saving
                            ? null
                            : () => setState(() => _step -= 1),
                  ),
                  Expanded(
                    child: Form(
                      key: _formKey,
                      child: Align(
                        alignment: Alignment.topCenter,
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
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
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
    padding: _onboardingContentPadding,
    children: [
      const Text('最近经期', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: _onboardingLabelGap),
      _validationSlot(
        TextFormField(
          controller: _nickname,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            labelText: '昵称',
            helperText: '\u00A0',
            helperStyle: TextStyle(fontSize: 12, height: 1),
            errorStyle: TextStyle(fontSize: 12, height: 1),
            floatingLabelAlignment: FloatingLabelAlignment.start,
          ),
          validator:
              (value) => value == null || value.trim().isEmpty ? '请输入昵称' : null,
        ),
      ),
      Row(
        children: [
          Expanded(
            child: _validationSlot(
              TextFormField(
                controller: _birthYear,
                readOnly: true,
                onTap: () => _chooseYear(_birthYear, fallbackYear: 1997),
                textAlign: TextAlign.left,
                decoration: const InputDecoration(
                  labelText: '出生年份',
                  helperText: '\u00A0',
                  helperStyle: TextStyle(fontSize: 12, height: 1),
                  errorStyle: TextStyle(fontSize: 12, height: 1),
                  floatingLabelAlignment: FloatingLabelAlignment.start,
                ),
                validator: _yearValidator,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _validationSlot(
              TextFormField(
                controller: _diagnosisYear,
                readOnly: true,
                onTap: () => _chooseYear(_diagnosisYear, fallbackYear: 2023),
                textAlign: TextAlign.left,
                decoration: const InputDecoration(
                  labelText: '确诊年份',
                  helperText: '\u00A0',
                  helperStyle: TextStyle(fontSize: 12, height: 1),
                  errorStyle: TextStyle(fontSize: 12, height: 1),
                  floatingLabelAlignment: FloatingLabelAlignment.start,
                ),
                validator: _yearValidator,
              ),
            ),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: _validationSlot(
              TextFormField(
                controller: _height,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: '身高（选填）',
                  suffixText: 'cm',
                  helperText: '\u00A0',
                  helperStyle: TextStyle(fontSize: 12, height: 1),
                  errorStyle: TextStyle(fontSize: 12, height: 1),
                  floatingLabelAlignment: FloatingLabelAlignment.start,
                ),
                validator: (value) {
                  final normalized = value?.trim() ?? '';
                  if (normalized.isEmpty) return null;
                  final height = double.tryParse(normalized);
                  return height == null || height < 100 || height > 230
                      ? '请输入 100–230 cm'
                      : null;
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _validationSlot(
              TextFormField(
                controller: _weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: '体重（选填）',
                  suffixText: 'kg',
                  helperText: '\u00A0',
                  helperStyle: TextStyle(fontSize: 12, height: 1),
                  errorStyle: TextStyle(fontSize: 12, height: 1),
                  floatingLabelAlignment: FloatingLabelAlignment.start,
                ),
                validator: _weightValidator,
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _validationSlot(Widget child) =>
      SizedBox(height: _onboardingFieldSlotHeight, child: child);

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
    showFrame: false,
    padding: _onboardingContentPadding,
    children: [
      _validationSlot(
        TextFormField(
          controller: _lastPeriod,
          readOnly: true,
          onTap: () => _chooseDate(_lastPeriod),
          decoration: const InputDecoration(
            labelText: '开始日期（选填）',
            suffixIcon: Icon(Icons.calendar_today_outlined),
            helperText: '\u00A0',
            helperStyle: TextStyle(fontSize: 12, height: 1),
            errorStyle: TextStyle(fontSize: 12, height: 1),
          ),
        ),
      ),
      const SizedBox(height: _onboardingSectionGap),
      const Text('月经周期', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: _onboardingLabelGap),
      Wrap(
        spacing: _onboardingLabelGap,
        runSpacing: _onboardingLabelGap,
        children:
            [..._cycleOptions, ..._customCycleRanges]
                .map<Widget>(
                  (value) => ChoiceChip(
                    label: Text(value),
                    selected: _cycleRange == value,
                    showCheckmark: false,
                    backgroundColor: Colors.white,
                    selectedColor: pomiLavender,
                    shape: const StadiumBorder(),
                    side: const BorderSide(color: pomiLine),
                    onSelected: (_) => setState(() => _cycleRange = value),
                  ),
                )
                .toList()
              ..add(
                _RoundAddButton(tooltip: '添加新的月经周期', onPressed: _addCycleRange),
              ),
      ),
      const SizedBox(height: _onboardingSectionGap),
      _validationSlot(
        TextFormField(
          controller: _nextVisit,
          readOnly: true,
          onTap: () => _chooseDate(_nextVisit, future: true),
          decoration: const InputDecoration(
            labelText: '下次就诊（选填）',
            suffixIcon: Icon(Icons.event_available_outlined),
            helperText: '\u00A0',
            helperStyle: TextStyle(fontSize: 12, height: 1),
            errorStyle: TextStyle(fontSize: 12, height: 1),
          ),
        ),
      ),
    ],
  );

  Widget _medicationStep() => _StepCard(
    showFrame: false,
    padding: _onboardingContentPadding,
    children: [
      const Text(
        '选择当前正在使用的药品或补剂',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: _onboardingLabelGap),
      const Text(
        '未列出的项目可点击 + 手动添加。',
        style: TextStyle(color: pomiMuted, fontSize: 12),
      ),
      const SizedBox(height: _onboardingSectionGap),
      Wrap(
        spacing: _onboardingLabelGap,
        runSpacing: _onboardingLabelGap,
        children:
            [..._medicationOptions.keys, ..._customMedicationOptions]
                .map<Widget>(
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
                .toList()
              ..add(
                _RoundAddButton(tooltip: '添加药品或补剂', onPressed: _addMedication),
              ),
      ),
    ],
  );
}

class _RoundAddButton extends StatelessWidget {
  const _RoundAddButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: const Icon(Icons.add_rounded, size: 20),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(40),
        foregroundColor: pomiPurple,
        backgroundColor: Colors.white,
        side: const BorderSide(color: pomiLine),
        shape: const CircleBorder(),
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({
    required this.title,
    required this.label,
    required this.hint,
  });

  final String title;
  final String label;
  final String hint;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = '请输入内容');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: _onboardingSectionGap),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 24,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: widget.hint,
                  errorText: _errorText,
                  counterText: '',
                ),
              ),
              const SizedBox(height: _onboardingLabelGap),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: _onboardingLabelGap),
                  FilledButton(onPressed: _submit, child: const Text('添加')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatePickerCard extends StatefulWidget {
  const _DatePickerCard({
    required this.title,
    required this.initialDate,
    required this.minimumDate,
    required this.maximumDate,
  });

  final String title;
  final DateTime initialDate;
  final DateTime minimumDate;
  final DateTime maximumDate;

  @override
  State<_DatePickerCard> createState() => _DatePickerCardState();
}

class _DatePickerCardState extends State<_DatePickerCard> {
  late int _year;
  late int _month;
  late int _day;
  late final FixedExtentScrollController _yearController;
  late final FixedExtentScrollController _monthController;
  late final FixedExtentScrollController _dayController;

  List<int> get _years => [
    for (
      var year = widget.minimumDate.year;
      year <= widget.maximumDate.year;
      year++
    )
      year,
  ];

  List<int> get _months {
    final firstMonth =
        _year == widget.minimumDate.year ? widget.minimumDate.month : 1;
    final lastMonth =
        _year == widget.maximumDate.year ? widget.maximumDate.month : 12;
    return [for (var month = firstMonth; month <= lastMonth; month++) month];
  }

  List<int> get _days {
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final firstDay =
        _year == widget.minimumDate.year && _month == widget.minimumDate.month
            ? widget.minimumDate.day
            : 1;
    final lastDay =
        _year == widget.maximumDate.year && _month == widget.maximumDate.month
            ? widget.maximumDate.day
            : daysInMonth;
    return [for (var day = firstDay; day <= lastDay; day++) day];
  }

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year;
    _month = widget.initialDate.month;
    _day = widget.initialDate.day;
    _yearController = FixedExtentScrollController(
      initialItem: _years.indexOf(_year),
    );
    _monthController = FixedExtentScrollController(
      initialItem: _months.indexOf(_month),
    );
    _dayController = FixedExtentScrollController(
      initialItem: _days.indexOf(_day),
    );
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  void _syncMonthAndDay() {
    final months = _months;
    _month = _month.clamp(months.first, months.last).toInt();
    final days = _days;
    _day = _day.clamp(days.first, days.last).toInt();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_monthController.hasClients) {
        _monthController.jumpToItem(_months.indexOf(_month));
      }
      if (_dayController.hasClients) {
        _dayController.jumpToItem(_days.indexOf(_day));
      }
    });
  }

  void _selectYear(int index) {
    setState(() {
      _year = _years[index];
      _syncMonthAndDay();
    });
  }

  void _selectMonth(int index) {
    setState(() {
      _month = _months[index];
      final days = _days;
      _day = _day.clamp(days.first, days.last).toInt();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dayController.hasClients) {
          _dayController.jumpToItem(_days.indexOf(_day));
        }
      });
    });
  }

  Widget _picker({
    required List<int> values,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onSelectedItemChanged,
  }) => CupertinoPicker(
    scrollController: controller,
    itemExtent: 44,
    useMagnifier: true,
    magnification: 1.06,
    backgroundColor: Colors.transparent,
    selectionOverlay: null,
    onSelectedItemChanged: onSelectedItemChanged,
    children: [
      for (final value in values)
        Center(child: Text('$value', textAlign: TextAlign.center)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: SizedBox(
          height: 350,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextButton(
                      onPressed:
                          () => Navigator.pop(
                            context,
                            DateTime(_year, _month, _day),
                          ),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 0),
                child: Row(
                  children: [
                    Expanded(child: Text('年', textAlign: TextAlign.center)),
                    Expanded(child: Text('月', textAlign: TextAlign.center)),
                    Expanded(child: Text('日', textAlign: TextAlign.center)),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 44,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: pomiLavender.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: pomiLine),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _picker(
                            values: _years,
                            controller: _yearController,
                            onSelectedItemChanged: _selectYear,
                          ),
                        ),
                        Expanded(
                          child: _picker(
                            values: _months,
                            controller: _monthController,
                            onSelectedItemChanged: _selectMonth,
                          ),
                        ),
                        Expanded(
                          child: _picker(
                            values: _days,
                            controller: _dayController,
                            onSelectedItemChanged: (index) {
                              setState(() => _day = _days[index]);
                            },
                          ),
                        ),
                      ],
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

class _OnboardingHeader extends StatelessWidget {
  const _OnboardingHeader({required this.step, this.onBack});
  final int step;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    const titles = ['基本信息', '经期情况', '当前用药'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
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
                      color:
                          index <= step ? pomiPurple : const Color(0xFFD8D1DC),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(titles[step], style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          if (step > 0)
            Positioned(
              left: -12,
              top: -12,
              child: IconButton(
                onPressed: onBack,
                tooltip: '返回上一步',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.children,
    this.showFrame = true,
    this.padding = const EdgeInsets.all(16),
  });
  final List<Widget> children;
  final bool showFrame;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    return showFrame ? Card(child: content) : content;
  }
}
