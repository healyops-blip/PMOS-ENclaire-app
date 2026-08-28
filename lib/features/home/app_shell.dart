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
  void _openTab(int index) {
    if (index == 2) {
      _showUploadDialog();
      return;
    }
    setState(() => _index = index);
  }

  Future<void> _showUploadDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: pomiInk.withValues(alpha: .22),
      builder:
          (dialogContext) => Dialog(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 34,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .84,
              ),
              child: const UploadScreen(modal: true),
            ),
          ),
    );
  }

  void _openRecords({bool reports = false}) => setState(() {
    _recordsTab = reports ? 1 : 0;
    _index = 3;
  });

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(onOpenTab: _openTab, onOpenRecords: _openRecords),
      const TrackingScreen(),
      const SizedBox.shrink(),
      RecordsScreen(
        key: ValueKey('records-$_recordsTab'),
        initialTab: _recordsTab,
      ),
      ProfileScreen(onOpenRecords: _openRecords),
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
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        height: 56,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            PomiGlassCard(
              borderRadius: 28,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: List.generate(items.length, (itemIndex) {
                    final item = items[itemIndex];
                    final selected = index == itemIndex;
                    if (itemIndex == 2) {
                      return const Expanded(child: SizedBox.shrink());
                    }
                    return Expanded(
                      child: Semantics(
                        button: true,
                        selected: selected,
                        label: item.$3,
                        child: InkWell(
                          onTap: () => onSelected(itemIndex),
                          child: Center(
                            child: Icon(
                              selected ? item.$2 : item.$1,
                              color: pomiSecondaryText,
                              size: 25,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.topCenter,
                child: Transform.translate(
                  offset: const Offset(0, -8),
                  child: Semantics(
                    button: true,
                    label: '上传资料',
                    child: InkResponse(
                      onTap: () => onSelected(2),
                      child: Container(
                        width: 48,
                        height: 48,
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
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
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
