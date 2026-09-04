import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seam/seam.dart';
import 'package:seam_example/main.dart';

void main() {
  testWidgets('every idea has a tab and each one renders', (WidgetTester t) async {
    await t.pumpWidget(const SeamExampleApp());
    await t.pump(const Duration(milliseconds: 100));

    for (final String label in <String>['Lattice', 'States', 'Schedule']) {
      await t.tap(find.text(label));
      await t.pump(const Duration(milliseconds: 100));
      expect(hasSeamContent(t), isTrue, reason: '$label tab is empty');
    }

    // Let every demo's timers drain so the test ends clean.
    await t.pump(const Duration(seconds: 8));
  });
}

/// A tab counts as rendering if it shows either bones or resolved content.
bool hasSeamContent(WidgetTester t) =>
    t.any(find.byType(SeamBone)) || t.any(find.byType(Card));
