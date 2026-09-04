import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Accumulates how far a subtree's height has moved across layouts.
///
/// This is the demo's stand-in for Cumulative Layout Shift: every time the
/// content changes height, whatever sits below it jumps by that much. A
/// placeholder that guessed wrong racks up pixels here; one measured from real
/// content stays at zero.
class ShiftMeter extends SingleChildRenderObjectWidget {
  /// Wraps [child], reporting each height change to [onShift].
  const ShiftMeter({super.key, required this.onShift, required Widget super.child});

  /// Called with the absolute height delta whenever the subtree resizes.
  final ValueChanged<double> onShift;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderShiftMeter(onShift);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderShiftMeter).onShift = onShift;
  }

}

class _RenderShiftMeter extends RenderProxyBox {
  _RenderShiftMeter(this.onShift);

  ValueChanged<double> onShift;
  double? _lastHeight;

  /// Forgets the baseline, so the next layout is not counted as a shift.
  void reset() => _lastHeight = null;

  @override
  void performLayout() {
    super.performLayout();
    final double h = size.height;
    final double? previous = _lastHeight;
    _lastHeight = h;
    if (previous == null || previous == h) return;

    final double delta = (h - previous).abs();
    // Reporting during layout would rebuild widgets this pass has visited.
    scheduleMicrotask(() => onShift(delta));
  }
}
