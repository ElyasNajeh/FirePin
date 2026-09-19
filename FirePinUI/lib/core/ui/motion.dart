import 'dart:math' as math;
import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const entrance = Duration(milliseconds: 260);
  static const press = Duration(milliseconds: 120);
  static const selection = Duration(milliseconds: 190);
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  static PageRoute<T> route<T>(BuildContext context, Widget page, String name) {
    final reduce = reduced(context);
    return PageRouteBuilder<T>(
      settings: RouteSettings(name: name),
      transitionDuration: reduce ? Duration.zero : entrance,
      reverseTransitionDuration: reduce ? Duration.zero : entrance,
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
        child: AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (_, child) => Transform.translate(
            offset: Offset(
              0,
              12 * (1 - Curves.easeOutCubic.transform(animation.value)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// One controller per reveal, no delayed callbacks or timers to leak.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.entrance,
    this.scale = false,
  });
  final Widget child;
  final Duration delay;
  final Duration duration;
  final bool scale;
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (_, child) {
      final start =
          widget.delay.inMilliseconds /
          (widget.delay + widget.duration).inMilliseconds;
      final t = ((_controller.value - start) / (1 - start)).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);
      return Opacity(
        opacity: eased,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - eased)),
          child: Transform.scale(
            scale: widget.scale
                ? 0.9 + 0.1 * Curves.easeOutBack.transform(t)
                : 1,
            child: child,
          ),
        ),
      );
    },
  );
}

/// Used only for live camera/map/pending states. Stops for reduced motion.
class Breathe extends StatefulWidget {
  const Breathe({
    super.key,
    required this.child,
    this.scale = 1.025,
    this.opacity = 0.65,
    this.enabled = true,
  });
  final Widget child;
  final double scale;
  final double opacity;
  final bool enabled;
  @override
  State<Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<Breathe> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  void _sync() {
    if (!widget.enabled ||
        AppMotion.reduced(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Breathe oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (_, child) {
        final value = Curves.easeInOut.transform(_controller.value);
        return Opacity(
          opacity: widget.opacity + (1 - widget.opacity) * value,
          child: Transform.scale(
            scale: 1 + (widget.scale - 1) * value,
            child: child,
          ),
        );
      },
    ),
  );
}

class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});
  final int trigger;
  final Widget child;
  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  @override
  void didUpdateWidget(Shake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && !AppMotion.reduced(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (_, child) => Transform.translate(
      offset: Offset(
        math.sin(_controller.value * math.pi * 6) * 5 * (1 - _controller.value),
        0,
      ),
      child: child,
    ),
  );
}
