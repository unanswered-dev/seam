import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seam/seam.dart';

const Color kBrand = Color(0xFFB0741C);
const Color kSlotBase = Color(0xFF112233);
const Color kSlotHi = Color(0xFF445566);

Widget harness({SeamPalette? scopePalette, Color? slotBase, Color? slotHi}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: SeamScope(
      palette: scopePalette,
      schedule: const SeamSchedule.always(),
      child: Center(
        child: SizedBox(
          width: 300,
          child: SeamSlot<String>(
            id: 'body',
            value: const SeamValue<String>.absent(),
            baseColor: slotBase,
            highlightColor: slotHi,
            builder: (BuildContext context, String v) => Text(v),
          ),
        ),
      ),
    ),
  );
}

SeamBone bone(WidgetTester t) => t.widget<SeamBone>(find.byType(SeamBone));

void main() {
  group('SeamPalette', () {
    test('from() lifts the seed toward white', () {
      final SeamPalette p = SeamPalette.from(kBrand);
      expect(p.base, kBrand);
      expect(p.highlight, isNot(kBrand));
      // Lifted toward white, so every channel rises.
      expect(p.highlight.r, greaterThan(p.base.r));
      expect(p.highlight.g, greaterThan(p.base.g));
      expect(p.highlight.b, greaterThan(p.base.b));
    });

    test('from() with zero lift is a flat palette', () {
      final SeamPalette p = SeamPalette.from(kBrand, lift: 0);
      expect(p.highlight, p.base);
    });

    test('from() can lift toward a colour other than white', () {
      final SeamPalette p =
          SeamPalette.from(kBrand, lift: 1, toward: const Color(0xFF000000));
      expect(p.highlight, const Color(0xFF000000));
    });

    test('rejects an out-of-range lift', () {
      expect(() => SeamPalette.from(kBrand, lift: 2), throwsAssertionError);
    });

    test('copyWith replaces one end', () {
      const SeamPalette p = SeamPalette.light();
      expect(p.copyWith(base: kBrand).base, kBrand);
      expect(p.copyWith(base: kBrand).highlight, p.highlight);
    });

    test('lerp interpolates and tolerates nulls', () {
      expect(SeamPalette.lerp(null, null, 0.5), isNull);
      expect(SeamPalette.lerp(const SeamPalette.light(), null, 0.5),
          const SeamPalette.light());
      final SeamPalette? mid = SeamPalette.lerp(
        const SeamPalette(base: Color(0xFF000000), highlight: Color(0xFF000000)),
        const SeamPalette(base: Color(0xFFFFFFFF), highlight: Color(0xFFFFFFFF)),
        0.5,
      );
      expect(mid!.base.r, closeTo(0.5, 0.01));
    });

    test('equal palettes compare equal', () {
      expect(const SeamPalette.light(), const SeamPalette.light());
      expect(const SeamPalette.light() == const SeamPalette.dark(), isFalse);
    });
  });

  group('resolution order', () {
    testWidgets('falls back to platform brightness with nothing set',
        (WidgetTester t) async {
      await t.pumpWidget(harness());
      expect(bone(t).base, const SeamPalette.light().base);
    });

    testWidgets('the scope palette themes every bone', (WidgetTester t) async {
      await t.pumpWidget(harness(scopePalette: SeamPalette.from(kBrand)));
      expect(bone(t).base, kBrand);
    });

    testWidgets('a slot overrides the scope', (WidgetTester t) async {
      await t.pumpWidget(harness(
        scopePalette: SeamPalette.from(kBrand),
        slotBase: kSlotBase,
        slotHi: kSlotHi,
      ));
      expect(bone(t).base, kSlotBase);
      expect(bone(t).highlight, kSlotHi);
    });

    testWidgets('a slot may override just one end', (WidgetTester t) async {
      final SeamPalette scope = SeamPalette.from(kBrand);
      await t.pumpWidget(harness(scopePalette: scope, slotBase: kSlotBase));
      expect(bone(t).base, kSlotBase);
      expect(bone(t).highlight, scope.highlight);
    });

    testWidgets('changing the scope palette repaints existing bones',
        (WidgetTester t) async {
      await t.pumpWidget(harness(scopePalette: const SeamPalette.light()));
      expect(bone(t).base, const SeamPalette.light().base);

      await t.pumpWidget(harness(scopePalette: SeamPalette.from(kBrand)));
      await t.pump();
      expect(bone(t).base, kBrand);
    });
  });
}
