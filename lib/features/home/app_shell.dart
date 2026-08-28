import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../dashboard/dashboard_screen.dart';
import '../profile/profile_screen.dart';
import '../records/records_screen.dart';
import '../tracking/tracking_screen.dart';
import '../upload/upload_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _recordsTab = 0;
  void _openTab(int index) => setState(() => _index = index);
  void _openRecords({bool reports = false}) => setState(() {
    _recordsTab = reports ? 1 : 0;
    _index = 3;
  });

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onOpenTab: _openTab, onOpenRecords: _openRecords),
      const TrackingScreen(),
      const UploadScreen(),
      RecordsScreen(
        key: ValueKey('records-$_recordsTab'),
        initialTab: _recordsTab,
      ),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _PomiBottomNav(index: _index, onSelected: _openTab),
    );
  }
}

class _PomiBottomNav extends StatelessWidget {
  const _PomiBottomNav({required this.index, required this.onSelected});
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, '首页'),
      (Icons.calendar_month_outlined, Icons.calendar_month_rounded, '经期'),
      (Icons.add_rounded, Icons.add_rounded, '上传'),
      (Icons.folder_open_outlined, Icons.folder_rounded, '记录'),
      (Icons.person_outline_rounded, Icons.person_rounded, '我的'),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: pomiLine)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: List.generate(items.length, (itemIndex) {
              final item = items[itemIndex];
              final selected = index == itemIndex;
              if (itemIndex == 2) {
                return Expanded(
                  child: Semantics(
                    button: true,
                    label: '上传资料',
                    child: InkResponse(
                      onTap: () => onSelected(itemIndex),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: const BoxDecoration(
                              color: pomiPurple,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x556A4C93),
                                  blurRadius: 14,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Expanded(
                child: InkWell(
                  onTap: () => onSelected(itemIndex),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        selected ? item.$2 : item.$1,
                        color: selected ? pomiPurple : pomiMuted,
                        size: 23,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.$3,
                        style: TextStyle(
                          color: selected ? pomiPurple : pomiMuted,
                          fontSize: 10,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
