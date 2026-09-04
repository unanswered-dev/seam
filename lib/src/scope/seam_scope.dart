import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../light/seam_light.dart';
import '../light/seam_palette.dart';
import '../memory/seam_memory.dart';
import '../schedule/seam_schedule.dart';

/// The single ticker, memory and light shared by every slot beneath a
/// [SeamScope].
///
/// Bones do not listen to this in order to rebuild. They listen in order to
/// repaint: a render object marks itself dirty for paint only, so a screen of
/// a hundred bones costs a hundred fills and zero widget rebuilds.
///
/// The ticker only runs while at least one bone is attached and actually lit.
/// A screen whose content has arrived stops animating, which is the difference
/// between an effect and a battery drain.
class SeamController extends ChangeNotifier {
  /// Creates a controller. Prefer [SeamScope], which owns one for you.
  SeamController({
    required TickerProvider vsync,
    SeamLight light = const SeamLight.ambient(),
    SeamSchedule schedule = const SeamSchedule.nng(),
    SeamMemory? memory,
    SeamPalette? palette,
  })  : _light = light,
        _schedule = schedule,
        _palette = palette,
        _memory = memory ?? SeamMemory.inMemory() {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;

  SeamLight _light;

  /// The light model every bone in this scope is lit by.
  SeamLight get light => _light;
  set light(SeamLight value) {
    if (_light == value) return;
    _light = value;
    notifyListeners();
  }

  SeamSchedule _schedule;

  /// When the effect is permitted to run.
  SeamSchedule get schedule => _schedule;
  set schedule(SeamSchedule value) {
    if (_schedule == value) return;
    _schedule = value;
    notifyListeners();
  }

  SeamPalette? _palette;

  /// The colours every bone in this scope is painted between.
  ///
  /// Null means each slot falls back to the platform brightness default. A
  /// slot's own `baseColor`/`highlightColor` still win over this.
  SeamPalette? get palette => _palette;
  set palette(SeamPalette? value) {
    if (_palette == value) return;
    _palette = value;
    notifyListeners();
  }

  SeamMemory _memory;

  /// Where measured slot geometry is kept.
  SeamMemory get memory => _memory;
  set memory(SeamMemory value) {
    if (identical(_memory, value)) return;
    _memory = value;
  }

  Size _scopeSize = Size.zero;

  /// The size of the scope, in whose coordinate space bones are lit.
  Size get scopeSize => _scopeSize;
  set scopeSize(Size value) {
    if (_scopeSize == value) return;
    _scopeSize = value;
    notifyListeners();
  }

  /// The render object bones measure their position against.
  ///
  /// Bones ask for their centre relative to this, so a bone's brightness
  /// depends on where it sits on screen rather than where it sits inside its
  /// own parent. Null before the scope has laid out, or when a slot is used
  /// without a scope.
  RenderObject? scopeRenderObject;

  double _phase = 0;

  /// The light's position through its period, 0..1.
  double get phase => _phase;

  final Set<Object> _litBones = <Object>{};
  final Map<Object, double> _progress = <Object, double>{};

  /// The mean resolved fraction across every slot currently resolving, 0..1.
  ///
  /// This is what lets the effect encode real progress instead of looping
  /// blindly: the scope knows how many of its fields have landed.
  double get progress {
    if (_progress.isEmpty) return 1;
    double total = 0;
    for (final double v in _progress.values) {
      total += v;
    }
    return (total / _progress.length).clamp(0.0, 1.0);
  }

  /// The number of slots currently resolving.
  int get resolvingCount => _progress.length;

  /// Registers that [key] is painting a lit bone, starting the ticker.
  void attachBone(Object key) {
    if (_litBones.add(key) && !_ticker.isActive && _litBones.isNotEmpty) {
      _ticker.start();
    }
  }

  /// Unregisters [key], stopping the ticker when nothing is left to animate.
  void detachBone(Object key) {
    if (_litBones.remove(key) && _litBones.isEmpty && _ticker.isActive) {
      _ticker.stop();
    }
  }

  /// Reports how far the slot identified by [key] has resolved.
  void reportProgress(Object key, double fraction) {
    final double clamped = fraction.clamp(0.0, 1.0);
    if (_progress[key] == clamped) return;
    _progress[key] = clamped;
  }

  /// Drops [key] from progress accounting.
  void clearProgress(Object key) => _progress.remove(key);

  void _onTick(Duration elapsed) {
    final int periodMs = _light.period.inMilliseconds;
    if (periodMs <= 0) return;
    _phase = (elapsed.inMilliseconds % periodMs) / periodMs;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _litBones.clear();
    _progress.clear();
    super.dispose();
  }
}

/// Owns the ticker, memory and light for everything beneath it.
///
/// Place one near the root of the app:
///
/// ```dart
/// SeamScope(
///   memory: SeamMemory.inMemory(),
///   child: MaterialApp(home: Home()),
/// )
/// ```
///
/// A scope is not mandatory. A [SeamSlot] with no scope above it falls back to
/// its own private controller with default settings, so adopting Seam never
/// starts with a root-level edit. The scope is the upgrade: it is what lets
/// every bone on the screen share one light and one ticker.
class SeamScope extends StatefulWidget {
  /// Creates a scope.
  const SeamScope({
    super.key,
    required this.child,
    this.light = const SeamLight.ambient(),
    this.schedule = const SeamSchedule.nng(),
    this.memory,
    this.palette,
  });

  /// The subtree whose slots share this scope.
  final Widget child;

  /// The light model for every bone below.
  final SeamLight light;

  /// When the effect may run.
  final SeamSchedule schedule;

  /// Where measured geometry is kept. Defaults to [SeamMemory.inMemory].
  final SeamMemory? memory;

  /// The colours every bone below is painted between.
  ///
  /// Null follows the platform brightness. Individual slots may still override
  /// it with their own `baseColor` and `highlightColor`.
  ///
  /// ```dart
  /// SeamScope(
  ///   palette: SeamPalette.from(const Color(0xFFB0741C)),
  ///   child: MyApp(),
  /// )
  /// ```
  final SeamPalette? palette;

  /// The nearest controller, or null when there is no scope above [context].
  static SeamController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SeamScopeMarker>()
        ?.controller;
  }

  /// The nearest controller. Throws when there is no scope above [context].
  static SeamController of(BuildContext context) {
    final SeamController? controller = maybeOf(context);
    assert(controller != null, 'No SeamScope found above this widget.');
    return controller!;
  }

  @override
  State<SeamScope> createState() => _SeamScopeState();
}

class _SeamScopeState extends State<SeamScope>
    with SingleTickerProviderStateMixin {
  late final SeamController _controller = SeamController(
    vsync: this,
    light: widget.light,
    schedule: widget.schedule,
    memory: widget.memory,
    palette: widget.palette,
  );

  @override
  void didUpdateWidget(SeamScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller
      ..light = widget.light
      ..schedule = widget.schedule
      ..palette = widget.palette;
    if (widget.memory != null) _controller.memory = widget.memory!;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SeamScopeMarker(
      controller: _controller,
      child: _ScopeSizeReporter(
        controller: _controller,
        child: widget.child,
      ),
    );
  }
}

class _SeamScopeMarker extends InheritedWidget {
  const _SeamScopeMarker({required this.controller, required super.child});

  final SeamController controller;

  @override
  bool updateShouldNotify(_SeamScopeMarker oldWidget) =>
      !identical(oldWidget.controller, controller);
}

/// Reports the scope's laid-out size to the controller, so bones can be lit in
/// scope coordinates rather than their own.
class _ScopeSizeReporter extends SingleChildRenderObjectWidget {
  const _ScopeSizeReporter({required this.controller, required super.child});

  final SeamController controller;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScopeSizeReporter(controller);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderScopeSizeReporter renderObject,
  ) {
    renderObject.controller = controller;
  }
}

class _RenderScopeSizeReporter extends RenderProxyBox {
  _RenderScopeSizeReporter(this.controller);

  SeamController controller;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    controller.scopeRenderObject = this;
  }

  @override
  void detach() {
    if (identical(controller.scopeRenderObject, this)) {
      controller.scopeRenderObject = null;
    }
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    // Deferred: notifying listeners mid-layout would mark descendants dirty
    // during a layout pass that has already visited them.
    final Size measured = size;
    if (controller.scopeSize != measured) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        controller.scopeSize = measured;
      });
    }
  }
}
