import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/app_theme.dart';
import 'motion.dart';

class FigmaIcon extends StatelessWidget {
  const FigmaIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });
  final String name;
  final double size;
  final double? width;
  final double? height;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) =>
      name == 'shutter' || name == 'location_marker'
      ? SizedBox(
          width: width ?? size,
          height: height ?? size,
          child: CustomPaint(painter: _FigmaCircleIconPainter(name)),
        )
      : SvgPicture.asset(
          'assets/figma/$name.svg',
          width: width ?? size,
          height: height ?? size,
          fit: fit,
          excludeFromSemantics: true,
        );
}

/// Exact circle geometry and shadow values from the bundled Figma SVGs.
/// flutter_svg does not render their SVG filters. Native vector painting keeps
/// the original shadows and stays sharp on high-density mobile displays.
class _FigmaCircleIconPainter extends CustomPainter {
  const _FigmaCircleIconPainter(this.name);
  final String name;

  @override
  void paint(Canvas canvas, Size size) {
    final shutter = name == 'shutter';
    final extent = shutter ? 92.0 : 36.0;
    final scale = math.min(size.width, size.height) / extent;
    canvas.translate(
      (size.width - extent * scale) / 2,
      (size.height - extent * scale) / 2,
    );
    canvas.scale(scale);
    final center = shutter ? const Offset(46, 46) : const Offset(18, 16);
    final radius = shutter ? 31.0 : 13.0;
    canvas.drawCircle(
      center + const Offset(0, 2),
      radius,
      Paint()
        ..color = shutter ? const Color(0x30000000) : const Color(0x3D082E29)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = shutter ? Colors.white : AppColors.primary,
    );
    canvas.drawCircle(
      center,
      shutter ? 40 : 11,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
  }

  @override
  bool shouldRepaint(_FigmaCircleIconPainter oldDelegate) =>
      name != oldDelegate.name;
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 4,
        height: 22,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 10),
      Flexible(child: Text('شباب البلد', style: AppType.section)),
    ],
  );
}

/// A natural, scrollable column. Figma's top/bottom insets already include
/// system chrome; use the larger of those and the device safe inset.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.children,
    this.bottom = 40,
    this.onBack,
    this.backEnabled = true,
  });
  final List<Widget> children;
  final double bottom;
  final VoidCallback? onBack;
  final bool backEnabled;
  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              math.max(24, safe.left),
              math.max(46, safe.top + 12),
              math.max(24, safe.right),
              math.max(bottom, safe.bottom + 12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onBack == null)
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: BrandHeader(),
                  )
                else
                  Row(
                    children: [
                      IconButton(
                        key: const ValueKey('onboarding-back'),
                        tooltip: 'رجوع',
                        visualDensity: VisualDensity.compact,
                        onPressed: backEnabled ? onBack : null,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      ),
                      const SizedBox(width: 6),
                      const BrandHeader(),
                    ],
                  ),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(
    this.title, {
    super.key,
    this.size = 27,
    this.align = TextAlign.start,
    this.color = AppColors.textPrimary,
  });
  final String title;
  final double size;
  final TextAlign align;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    title,
    textAlign: align,
    style: AppType.text(
      size,
      weight: FontWeight.w700,
      height: 44,
      color: color,
    ),
  );
}

/// Preserves Figma's copy-block rhythm but grows for large text and wrapping.
class CopyBlock extends StatelessWidget {
  const CopyBlock(
    this.text, {
    super.key,
    required this.minHeight,
    this.style,
    this.center = false,
  });
  final String text;
  final double minHeight;
  final TextStyle? style;
  final bool center;
  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minHeight: minHeight),
    alignment: center ? Alignment.center : AlignmentDirectional.centerStart,
    child: Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: style ?? AppType.muted,
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = 20,
    this.radius = 18,
    this.warning = false,
    this.shadow = false,
  });
  final Widget child;
  final double padding;
  final double radius;
  final bool warning;
  final bool shadow;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(padding),
    decoration: BoxDecoration(
      color: warning ? AppColors.warningSurface : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: warning
            ? AppColors.warning.withValues(alpha: 0.35)
            : AppColors.outline,
      ),
      boxShadow: shadow
          ? [
              const BoxShadow(
                color: Color(0x120A261F),
                blurRadius: 16,
                offset: Offset(0, 5),
              ),
            ]
          : null,
    ),
    child: child,
  );
}

class IllustrationBadge extends StatelessWidget {
  const IllustrationBadge(
    this.asset, {
    super.key,
    this.size = 112,
    this.iconSize = 58,
    this.radius = 32,
  });
  final String asset;
  final double size;
  final double iconSize;
  final double radius;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: FigmaIcon(asset, size: iconSize),
    ),
  );
}

class AppButton extends StatefulWidget {
  const AppButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.secondary = false,
    this.busy = false,
    this.emergency = false,
    this.minHeight = 56,
    this.fontSize = 17,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final bool busy;
  final bool emergency;
  final double minHeight;
  final double fontSize;
  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final color = widget.emergency ? AppColors.emergency : AppColors.primary;
    final radius = BorderRadius.circular(widget.emergency ? 18 : 16);
    return AnimatedScale(
      scale: _pressed && !AppMotion.reduced(context) ? 0.98 : 1,
      duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.press,
      curve: Curves.easeOut,
      child: Semantics(
        button: true,
        enabled: enabled,
        child: Material(
          color: widget.secondary ? Colors.transparent : color,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: widget.secondary
                ? BorderSide(color: color.withValues(alpha: 0.65))
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: radius,
            onHighlightChanged: (value) {
              if (mounted) setState(() => _pressed = value);
            },
            onTap: enabled
                ? () {
                    if (widget.emergency) {
                      HapticFeedback.mediumImpact();
                    } else {
                      HapticFeedback.selectionClick();
                    }
                    widget.onPressed!();
                  }
                : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: widget.minHeight,
                minWidth: double.infinity,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: math.min(10, (widget.minHeight - 28) / 2),
                ),
                child: AnimatedOpacity(
                  opacity: enabled || widget.busy ? 1 : 0.5,
                  duration: AppMotion.press,
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: AppType.text(
                      widget.fontSize,
                      weight: widget.secondary
                          ? FontWeight.w500
                          : FontWeight.w700,
                      height: 28,
                      color: widget.secondary ? color : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InlineMessage extends StatelessWidget {
  const InlineMessage(this.message, {super.key});
  final String? message;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              message!,
              style: AppType.text(14, color: AppColors.warning),
            ),
          ),
        );
}

void showFeedback(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
