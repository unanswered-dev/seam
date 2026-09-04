import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../light/seam_palette.dart';
import '../memory/seam_memory.dart';
import '../schedule/seam_schedule.dart';
import '../scope/seam_scope.dart';
import '../value/seam_value.dart';
import 'seam_bone.dart';

/// Renders one field across all four of its loading states.
///
/// A slot is the unit Seam works in. It owns one piece of data, resolves
/// independently of every other slot on the screen, and remembers the shape
/// its real content took so the next skeleton is that shape rather than a
/// guess.
///
/// ```dart
/// SeamSlot<String>(
///   id: 'article.body',
///   value: vm.body,
///   builder: (context, body) => Text(body),
/// )
/// ```
///
/// Nothing above this widget coordinates it. A screen of slots lights up field
/// by field as each one's data lands, instead of holding everything back until
/// the slowest source answers.
class SeamSlot<T> extends StatefulWidget {
  /// Creates a slot for the field identified by [id].
  const SeamSlot({
    super.key,
    required this.id,
    required this.value,
    required this.builder,
    this.staleBuilder,
    this.fallbackHeight = 16.0,
    this.fallbackWidth,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    this.baseColor,
    this.highlightColor,
    this.degradeStale = true,
    this.staleOpacity = 0.62,
    this.staleSaturation = 0.35,
    this.reserveWhileResolving = true,
  });

  /// A stable key for this slot's measured geometry.
  ///
  /// Ids must be stable across builds and unique per distinct shape. Reusing
  /// one id for slots of different shapes teaches the memory a median of both,
  /// which is wrong for each. In a list, prefer one id per *kind* of row
  /// (`'feed.row.title'`), not one per item — the point is to learn the shape
  /// rows share.
  final String id;

  /// The current state of this field.
  final SeamValue<T> value;

  /// Builds the real content. Used for fresh, partial and stale values.
  final Widget Function(BuildContext context, T value) builder;

  /// Optionally builds stale content differently from fresh content — to add
  /// an "updated 6 days ago" affordance, for instance.
  ///
  /// When null, [builder] is used and the result is degraded per
  /// [degradeStale].
  final Widget Function(BuildContext context, T value, DateTime? asOf)?
      staleBuilder;

  /// Placeholder height used before anything has been measured.
  final double fallbackHeight;

  /// Placeholder width used before anything has been measured. Null fills the
  /// available width.
  final double? fallbackWidth;

  /// Corner rounding of the placeholder.
  final BorderRadius borderRadius;

  /// Placeholder colour at zero luminance.
  ///
  /// Overrides the scope's palette for this slot alone. When both are null the
  /// platform brightness decides.
  final Color? baseColor;

  /// Placeholder colour at full luminance.
  ///
  /// Overrides the scope's palette for this slot alone. When both are null the
  /// platform brightness decides.
  final Color? highlightColor;

  /// Whether stale content is dimmed and desaturated.
  ///
  /// Stale data is worth showing — it is real information the reader can act
  /// on — but it must not pass for current. Degrading it is the honest
  /// default; turn this off only if you supply your own affordance.
  final bool degradeStale;

  /// Opacity applied to stale content when [degradeStale] is true.
  final double staleOpacity;

  /// Saturation retained by stale content when [degradeStale] is true, 0..1.
  final double staleSaturation;

  /// Whether stale and partial content is held at the measured height.
  ///
  /// Streamed content arrives short and grows. Left alone it drags everything
  /// below it up the screen and then back down, which is the same reflow a
  /// measured placeholder exists to prevent — so by default a slot that has
  /// been measured keeps reserving that height until the value is fresh.
  ///
  /// Turn this off for a slot whose content legitimately changes size between
  /// loads and where a floor would leave visible dead space.
  final bool reserveWhileResolving;

  @override
  State<SeamSlot<T>> createState() => _SeamSlotState<T>();
}

class _SeamSlotState<T> extends State<SeamSlot<T>>
    with SingleTickerProviderStateMixin {
  SeamController? _scopeController;
  SeamController? _fallbackController;

  /// Boundaries further out than this are not scheduled at all.
  ///
  /// `SeamSchedule.always()` pushes escalation a day out to mean "never"; a
  /// pending day-long timer would leak and would hang every widget test in the
  /// host app. No real load crosses this, so treating it as "never" is exact
  /// in practice and cheap.
  static const Duration _maxScheduledDelay = Duration(minutes: 5);

  Timer? _timer;
  Size? _lastRecorded;
  SeamPhase _phase = SeamPhase.settled;

  SeamController get _controller =>
      _scopeController ?? (_fallbackController ??= SeamController(vsync: this));

  @override
  void initState() {
    super.initState();
    if (widget.value.isResolving) _beginResolving();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final SeamController? found = SeamScope.maybeOf(context);
    if (!identical(found, _scopeController)) {
      final bool hadNone = _scopeController == null;
      _scopeController = found;
      // A scope appeared above a slot that had been running standalone. Drop
      // the private ticker rather than animating on two clocks.
      if (found != null && _fallbackController != null) {
        _fallbackController!.dispose();
        _fallbackController = null;
      }
      // The new scope may carry a different schedule, so restart the clock
      // rather than finishing this load on the old one's thresholds.
      if (!hadNone && widget.value.isResolving) _beginResolving();
    }
  }

  @override
  void didUpdateWidget(SeamSlot<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool wasResolving = oldWidget.value.isResolving;
    final bool isResolving = widget.value.isResolving;

    if (isResolving && !wasResolving) {
      _beginResolving();
    } else if (!isResolving && wasResolving) {
      _endResolving();
    }
    if (oldWidget.id != widget.id) _lastRecorded = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.clearProgress(this);
    _fallbackController?.dispose();
    super.dispose();
  }

  /// Starts the schedule for a load that has just begun.
  ///
  /// The phase advances on timers rather than by comparing wall-clock reads.
  /// A load is a duration, not two points in time, and `DateTime.now()` can
  /// move under you when the device clock changes.
  void _beginResolving() {
    _timer?.cancel();
    final SeamSchedule schedule = _controller.schedule;

    if (schedule.suppressBefore > Duration.zero) {
      _phase = SeamPhase.held;
      _timer = Timer(schedule.suppressBefore, () => _advanceTo(SeamPhase.lit));
    } else {
      _phase = SeamPhase.lit;
      _scheduleEscalation(schedule.escalateAfter);
    }
  }

  void _endResolving() {
    _timer?.cancel();
    _timer = null;
    _phase = SeamPhase.settled;
  }

  void _advanceTo(SeamPhase next) {
    if (!mounted) return;
    setState(() => _phase = next);
    if (next == SeamPhase.lit) {
      final SeamSchedule schedule = _controller.schedule;
      _scheduleEscalation(schedule.escalateAfter - schedule.suppressBefore);
    }
  }

  void _scheduleEscalation(Duration delay) {
    _timer?.cancel();
    _timer = null;
    if (delay <= Duration.zero || delay > _maxScheduledDelay) return;
    _timer = Timer(delay, () => _advanceTo(SeamPhase.escalated));
  }

  void _record(Size size, BoxConstraints constraints) {
    if (_lastRecorded == size) return;
    _lastRecorded = size;
    _controller.memory.record(widget.id, size, constraints);
  }

  @override
  Widget build(BuildContext context) {
    final SeamController controller = _controller;
    controller.reportProgress(this, widget.value.resolvedFraction);

    return switch (widget.value) {
      // Fresh content is the only thing measured, and it is never floored —
      // its natural size is the truth everything else is reserved against.
      SeamFresh<T>(:final T value) => _MeasureBox(
          onMeasured: _record,
          child: widget.builder(context, value),
        ),
      SeamPartial<T>(:final T value) =>
        _reserve(controller, widget.builder(context, value)),
      SeamStale<T>(:final T value, :final DateTime? asOf) =>
        _reserve(controller, _buildStale(context, value, asOf)),
      SeamAbsent<T>() => _buildPlaceholder(context, controller),
    };
  }

  /// Holds [child] at no less than the height this slot was measured at.
  ///
  /// Without this, a slot that leaves `absent` for `partial` shrinks to
  /// whatever has streamed in so far, and everything below it walks up the
  /// screen as the rest arrives — reintroducing exactly the reflow the
  /// measured placeholder removed. Reserving the known height means text
  /// fills into space already held rather than pushing the page around.
  Widget _reserve(SeamController controller, Widget child) {
    if (!widget.reserveWhileResolving) return child;
    return _ReserveBox(
      memory: controller.memory,
      slotId: widget.id,
      child: child,
    );
  }

  Widget _buildStale(BuildContext context, T value, DateTime? asOf) {
    final Widget content = widget.staleBuilder != null
        ? widget.staleBuilder!(context, value, asOf)
        : widget.builder(context, value);
    if (!widget.degradeStale) return content;

    final double s = widget.staleSaturation.clamp(0.0, 1.0);
    final double a = widget.staleOpacity.clamp(0.0, 1.0);
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
        0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0, //
        0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, //
        0, 0, 0, a, 0, //
      ]),
      child: content,
    );
  }

  Widget _buildPlaceholder(BuildContext context, SeamController controller) {
    // Slot beats scope beats platform brightness.
    final SeamPalette palette = controller.palette ?? SeamPalette.of(context);

    // No LayoutBuilder here. The bone reads the memory in its own
    // performLayout, which is what lets a placeholder be measured for
    // intrinsic dimensions and sit inside IntrinsicHeight or an intrinsic
    // Table column.
    return SeamBone(
      controller: controller,
      memory: controller.memory,
      slotId: widget.id,
      width: widget.fallbackWidth,
      height: widget.fallbackHeight,
      borderRadius: widget.borderRadius,
      base: widget.baseColor ?? palette.base,
      highlight: widget.highlightColor ?? palette.highlight,
      // Held: lay out and reserve the measured space, but paint nothing.
      lit: _phase != SeamPhase.held,
    );
  }
}

/// Reports the size real content occupied, along with the constraints it was
/// laid out under.
class _MeasureBox extends SingleChildRenderObjectWidget {
  const _MeasureBox({required this.onMeasured, required super.child});

  final void Function(Size size, BoxConstraints constraints) onMeasured;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureBox(onMeasured);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureBox renderObject) {
    renderObject.onMeasured = onMeasured;
  }
}

class _RenderMeasureBox extends RenderProxyBox {
  _RenderMeasureBox(this.onMeasured);

  void Function(Size size, BoxConstraints constraints) onMeasured;

  @override
  void performLayout() {
    super.performLayout();
    // Reporting synchronously would write to the memory during layout, which
    // can mark other slots dirty in a pass that has already visited them.
    final Size measured = size;
    final BoxConstraints under = constraints;
    scheduleMicrotask(() => onMeasured(measured, under));
  }
}

/// Floors a subtree's height at the geometry recorded for [slotId].
///
/// Reads the memory during layout rather than through a `LayoutBuilder`, so it
/// stays usable inside widgets that ask for intrinsic dimensions.
class _ReserveBox extends SingleChildRenderObjectWidget {
  const _ReserveBox({
    required this.memory,
    required this.slotId,
    required Widget super.child,
  });

  final SeamMemory memory;
  final String slotId;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReserveBox(memory, slotId);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderReserveBox)
      ..memory = memory
      ..slotId = slotId;
  }
}

class _RenderReserveBox extends RenderProxyBox {
  _RenderReserveBox(this._memory, this._slotId);

  SeamMemory _memory;
  set memory(SeamMemory value) {
    if (identical(_memory, value)) return;
    _memory = value;
    markNeedsLayout();
  }

  String _slotId;
  set slotId(String value) {
    if (_slotId == value) return;
    _slotId = value;
    markNeedsLayout();
  }

  Size? _reserved(BoxConstraints constraints) =>
      _memory.reserveFor(_slotId, constraints);

  @override
  double computeMinIntrinsicHeight(double width) => math.max(
        super.computeMinIntrinsicHeight(width),
        width.isFinite
            ? (_reserved(BoxConstraints(maxWidth: width))?.height ?? 0)
            : 0,
      );

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(
        super.computeMaxIntrinsicHeight(width),
        width.isFinite
            ? (_reserved(BoxConstraints(maxWidth: width))?.height ?? 0)
            : 0,
      );

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);

    final Size? reserved = _reserved(constraints);
    final double height = reserved == null
        ? child.size.height
        : math.max(child.size.height, reserved.height);

    size = constraints.constrain(Size(child.size.width, height));
  }
}
