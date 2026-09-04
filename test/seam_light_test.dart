import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seam/seam.dart';

void main() {
  _sustainedTests();
  testWidgets('the ticker runs and the phase advances while a bone is lit',
      (WidgetTester t) async {
    late SeamController controller;

    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SeamScope(
          schedule: const SeamSchedule.always(),
          child: Builder(
            builder: (BuildContext context) {
              controller = SeamScope.of(context);
              return Center(
                child: SizedBox(
                  width: 300,
                  child: SeamSlot<String>(
                    id: 'x',
                    value: const SeamValue<String>.absent(),
                    fallbackHeight: 20,
                    builder: (BuildContext c, String v) => Text(v),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(SeamBone), findsOneWidget);

    await t.pump(const Duration(milliseconds: 16));
    final double first = controller.phase;
    await t.pump(const Duration(milliseconds: 400));
    final double second = controller.phase;

    expect(second, isNot(first), reason: 'the light never moved');
  });

  testWidgets('the scope reports a non-zero size', (WidgetTester t) async {
    late SeamController controller;
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SeamScope(
          schedule: const SeamSchedule.always(),
          child: Builder(
            builder: (BuildContext context) {
              controller = SeamScope.of(context);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(controller.scopeSize, isNot(Size.zero),
        reason: 'luminanceAt returns 0 for an empty scope, so bones stay flat');
  });
}

void _sustainedTests() {
  testWidgets('the light keeps moving for the whole load', (WidgetTester t) async {
    late SeamController controller;
    await t.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SeamScope(
          schedule: const SeamSchedule.always(),
          child: Builder(
            builder: (BuildContext context) {
              controller = SeamScope.of(context);
              return Center(
                child: SizedBox(
                  width: 300,
                  child: SeamSlot<String>(
                    id: 'x',
                    value: const SeamValue<String>.absent(),
                    fallbackHeight: 20,
                    builder: (BuildContext c, String v) => Text(v),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final List<double> samples = <double>[];
    for (int i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 300));
      samples.add(controller.phase);
    }

    final int distinct = samples.toSet().length;
    // 12 samples across 3.6s of a 1.9s period should all be different.
    expect(distinct, greaterThan(8),
        reason: 'phase samples were $samples — the ticker stalls');
  });
}
