import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../scope/seam_scope.dart';

/// One painted placeholder shape.
///
/// A bone repaints, it never rebuilds. It listens to its scope's controller
/// and marks itself dirty for paint only, so the per-frame cost of a screen
/// full of bones is a set of rounded-rect fills — no `saveLayer`, no shader
/// mask, no offscreen buffer, and no element tree work at all.
class SeamBone extends LeafRenderObjectWidget {
  /// Creates a bone of [width] by [height].
  const SeamBone({
    super.key,
    required this.controller,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
    required this.base,
    required this.highlight,
    this.lit = true,
  });

  /// The scope controller supplying phase, light and scope size.
  final SeamController controller;

  /// Width, or null to take the incoming maximum.
  final double? width;

  /// Height, or null to take the incoming maximum.
  final double? height;

  /// Corner rounding.
  final BorderRadius borderRadius;

  /// Colour at zero luminance.
  final Color base;

  /// Colour at full luminance.
  final Color highlight;

  /// Whether to paint at all.
  ///
  /// False during the held phase: the bone still lays out, reserving the
  /// measured space, but paints nothing. That is what stops a fast load from
  /// flashing a skeleton it is about to discard.
  final bool lit;

  @override
  RenderSeamBone createRenderObject(BuildContext context) {
    return RenderSeamBone(
      controller: controller,
      preferredWidth: width,
      preferredHeight: height,
      borderRadius: borderRadius,
      base: base,
      highlight: highlight,
      lit: lit,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSeamBone renderObject) {
    renderObject
      ..controller = controller
      ..preferredWidth = width
      ..preferredHeight = height
      ..borderRadius = borderRadius
      ..base = base
      ..highlight = highlight
      ..lit = lit;
  }
}

/// The render object behind [SeamBone].
class RenderSeamBone extends RenderBox {
  /// Creates the render object.
  RenderSeamBone({
    required SeamController controller,
    required double? preferredWidth,
    required double? preferredHeight,
    required BorderRadius borderRadius,
    required Color base,
    required Color highlight,
    required bool lit,
  })  : _controller = controller,
        _preferredWidth = preferredWidth,
        _preferredHeight = preferredHeight,
        _borderRadius = borderRadius,
        _base = base,
        _highlight = highlight,
        _lit = lit;

  SeamController _controller;

  /// The scope controller this bone is lit by.
  SeamController get controller => _controller;
  set controller(SeamController value) {
    if (identical(_controller, value)) return;
    if (attached) {
      _stopListening();
      _controller = value;
      _startListening();
    } else {
      _controller = value;
    }
    markNeedsPaint();
  }

  double? _preferredWidth;

  /// Requested width, or null to fill.
  double? get preferredWidth => _preferredWidth;
  set preferredWidth(double? value) {
    if (_preferredWidth == value) return;
    _preferredWidth = value;
    markNeedsLayout();
  }

  double? _preferredHeight;

  /// Requested height, or null to fill.
  double? get preferredHeight => _preferredHeight;
  set preferredHeight(double? value) {
    if (_preferredHeight == value) return;
    _preferredHeight = value;
    markNeedsLayout();
  }

  BorderRadius _borderRadius;

  /// Corner rounding.
  BorderRadius get borderRadius => _borderRadius;
  set borderRadius(BorderRadius value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  Color _base;

  /// Colour at zero luminance.
  Color get base => _base;
  set base(Color value) {
    if (_base == value) return;
    _base = value;
    markNeedsPaint();
  }

  Color _highlight;

  /// Colour at full luminance.
  Color get highlight => _highlight;
  set highlight(Color value) {
    if (_highlight == value) return;
    _highlight = value;
    markNeedsPaint();
  }

  bool _lit;

  /// Whether the bone paints.
  bool get lit => _lit;
  set lit(bool value) {
    if (_lit == value) return;
    _lit = value;
    if (attached) {
      if (_lit) {
        _controller.attachBone(this);
      } else {
        _controller.detachBone(this);
      }
    }
    markNeedsPaint();
  }

  void _onLightChanged() => markNeedsPaint();

  void _startListening() {
    _controller.addListener(_onLightChanged);
    if (_lit) _controller.attachBone(this);
  }

  void _stopListening() {
    _controller.removeListener(_onLightChanged);
    _controller.detachBone(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _startListening();
  }

  @override
  void detach() {
    _stopListening();
    super.detach();
  }

  @override
  bool get sizedByParent => false;

  @override
  void performLayout() {
    final double width = _preferredWidth ??
        (constraints.hasBoundedWidth ? constraints.maxWidth : 0.0);
    final double height = _preferredHeight ??
        (constraints.hasBoundedHeight ? constraints.maxHeight : 0.0);
    size = constraints.constrain(Size(width, height));
  }

  @override
  double computeMinIntrinsicWidth(double height) => _preferredWidth ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) => _preferredWidth ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) => _preferredHeight ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) => _preferredHeight ?? 0;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_lit || size.isEmpty) return;

    // Light the bone by where it sits in the *scope*, not where it sits in its
    // own parent. Two bones equidistant from the source are equally bright no
    // matter how deep in the tree they live, which is what makes this read as
    // one source crossing a surface.
    final Offset center = _centerInScope(offset);
    final double luminance = _controller.light.luminanceAt(
      _controller.phase,
      center,
      _controller.scopeSize,
    );

    final Paint paint = Paint()
      ..color = _controller.light.colorAt(luminance, _base, _highlight)
      ..isAntiAlias = true;

    context.canvas.drawRRect(
      _borderRadius.toRRect(offset & size),
      paint,
    );
  }

  Offset _centerInScope(Offset offset) {
    final RenderObject? anchor = _controller.scopeRenderObject;
    final Offset localCenter = size.center(Offset.zero);
    if (anchor != null && anchor.attached && attached) {
      try {
        return localToGlobal(localCenter, ancestor: anchor);
      } catch (_) {
        // The anchor is not an ancestor of this bone — a slot outside its
        // scope, or a tree mid-reparent. Painting in layer coordinates is a
        // slightly worse light, never a broken one.
      }
    }
    return offset + localCenter;
  }
}
