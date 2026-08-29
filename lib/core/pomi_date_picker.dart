import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Shows the date selector used during cold start and throughout the app.
///
/// Keeping the selector in one place makes the year/month/day wheels, bounds,
/// and visual treatment identical for onboarding and later data entry.
Future<DateTime?> showPomiDatePicker({
  required BuildContext context,
  required String title,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final minimumDate = DateUtils.dateOnly(firstDate);
  final maximumDate = DateUtils.dateOnly(lastDate);
  final selectedDate = DateUtils.dateOnly(initialDate);
  final safeInitialDate =
      selectedDate.isBefore(minimumDate)
          ? minimumDate
          : selectedDate.isAfter(maximumDate)
          ? maximumDate
          : selectedDate;
  return showDialog<DateTime>(
    context: context,
    builder:
        (context) => _PomiDatePickerCard(
          title: title,
          initialDate: safeInitialDate,
          minimumDate: minimumDate,
          maximumDate: maximumDate,
        ),
  );
}

String pomiDateValue(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class _PomiDatePickerCard extends StatefulWidget {
  const _PomiDatePickerCard({
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
  State<_PomiDatePickerCard> createState() => _PomiDatePickerCardState();
}

class _PomiDatePickerCardState extends State<_PomiDatePickerCard> {
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
