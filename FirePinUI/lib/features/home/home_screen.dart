import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/ui/components.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';

/// Figma 59:2. Bundled reference map; no map provider or network access.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.hasLocation,
    required this.onReport,
  });
  final bool hasLocation;
  final VoidCallback onReport;
  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    return Scaffold(
      bottomNavigationBar: Container(
        constraints: const BoxConstraints(minHeight: 90),
        padding: EdgeInsets.fromLTRB(30, 10, 30, math.max(12, safe.bottom)),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.outline)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _NavItem(
                'الرئيسية',
                'nav_home',
                selected: true,
                onTap: () {},
              ),
            ),
            Expanded(
              child: _NavItem(
                'التنبيهات',
                'nav_alerts',
                onTap: () => showFeedback(context, 'لا توجد تنبيهات جديدة.'),
              ),
            ),
            Expanded(
              child: _NavItem(
                'الحساب',
                'nav_account',
                onTap: () =>
                    showFeedback(context, 'إعدادات الحساب ستتوفر قريبًا.'),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(top: math.max(46, safe.top + 12), bottom: 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    const Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: BrandHeader(),
                      ),
                    ),
                    _HeaderAction(
                      'الحساب',
                      'account',
                      () => showFeedback(
                        context,
                        'إعدادات الحساب ستتوفر قريبًا.',
                      ),
                    ),
                    const SizedBox(width: 10),
                    _HeaderAction(
                      'الإشعارات',
                      'notification',
                      () => showFeedback(context, 'لا توجد إشعارات جديدة.'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ReferenceMap(hasLocation: hasLocation),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AppButton(
                '🔥 إبلاغ عن حريق',
                emergency: true,
                minHeight: 72,
                fontSize: 21,
                onPressed: onReport,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                hasLocation
                    ? 'سيتم تحديد موقع البلاغ تلقائيًا'
                    : 'فعّل الموقع لتحديد مكان البلاغ عند الإرسال',
                style: AppType.caption,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceMap extends StatelessWidget {
  const _ReferenceMap({required this.hasLocation});
  final bool hasLocation;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'خريطة توضيحية. ليست خريطة جغرافية متصلة.',
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F142E24),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 350 / 404,
          child: LayoutBuilder(
            builder: (_, constraints) {
              final scale = constraints.maxWidth / 350;
              return Stack(
                fit: StackFit.expand,
                children: [
                  const FigmaIcon(
                    'basemap',
                    width: 350,
                    height: 404,
                    fit: BoxFit.fill,
                  ),
                  Positioned(
                    left: 134 * scale,
                    top: 150 * scale,
                    width: 80 * scale,
                    height: 80 * scale,
                    child: Breathe(
                      enabled: hasLocation,
                      scale: 1.06,
                      opacity: 0.8,
                      child: const FigmaIcon('location_halo', size: 80),
                    ),
                  ),
                  Positioned(
                    left: 156 * scale,
                    top: 174 * scale,
                    width: 36 * scale,
                    height: 36 * scale,
                    child: const FigmaIcon('location_marker', size: 36),
                  ),
                  Positioned(
                    left: 110 * scale,
                    top: 224 * scale,
                    child: _MapChip(
                      width: 128 * scale,
                      child: Text(
                        hasLocation ? 'موقعك الحالي' : 'الموقع غير مفعّل',
                        style: AppType.text(
                          14,
                          weight: FontWeight.w500,
                          height: 24,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16 * scale,
                    top: 16 * scale,
                    child: _MapChip(
                      width: 94,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Breathe(
                            scale: 1,
                            child: const FigmaIcon('live_dot', size: 8),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'مباشر',
                            style: AppType.text(13, weight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.child, required this.width});
  final Widget child;
  final double width;
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    constraints: const BoxConstraints(minHeight: 34),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: AppColors.outline),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1F1C332B),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction(this.label, this.asset, this.onTap);
  final String label;
  final String asset;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: AppColors.outline)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(child: FigmaIcon(asset, size: 22)),
        ),
      ),
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem(
    this.label,
    this.asset, {
    this.selected = false,
    required this.onTap,
  });
  final String label;
  final String asset;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FigmaIcon(asset, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppType.text(
                13,
                height: 25,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
