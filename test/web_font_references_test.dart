import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final path in ['web/index.html', 'web/app.html']) {
    test('$path uses only the POMI web font subsets', () {
      final html = File(path).readAsStringSync();

      expect(html, contains('assets/assets/fonts/pomi_web_subset/'));
      expect(html, isNot(contains('assets/assets/fonts/NotoSansSC-')));
      expect(html, contains('font-display: swap'));
    });
  }

  test('app shell shows progress until Flutter paints its first frame', () {
    final html = File('web/app.html').readAsStringSync();

    expect(html, contains('id="pomi-loading"'));
    expect(html, contains('flutter-first-frame'));
    expect(html, contains('POMI 加载中'));
  });
}
