import 'package:flutter/material.dart';
import '../../core/services/device_services.dart';
import '../../core/ui/components.dart';
import '../../theme/app_theme.dart';
import 'onboarding_models.dart';

/// Figma 52:2. Coordinates remain only in the in-memory session.
class LocationPermissionScreen extends StatefulWidget {
  const LocationPermissionScreen({
    super.key,
    required this.service,
    required this.onContinue,
    this.onBack,
  });
  final LocationService service;
  final ValueChanged<LocationFix?> onContinue;
  final VoidCallback? onBack;
  @override
  State<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

class _LocationPermissionScreenState extends State<LocationPermissionScreen> {
  bool _busy = false;
  LocationProblem? _problem;
  Future<void> _request() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final position = await widget.service.requestCurrentPosition();
      if (mounted) widget.onContinue(position);
    } on LocationFailure catch (error) {
      if (mounted) setState(() => _problem = error.problem);
    } catch (_) {
      if (mounted) setState(() => _problem = LocationProblem.unavailable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _settings() async {
    try {
      final opened = await widget.service.openSettings(
        locationService: _problem == LocationProblem.serviceDisabled,
      );
      if (!opened && mounted) {
        showFeedback(context, 'افتح إعدادات الجهاز لتفعيل الموقع.');
      }
    } catch (_) {
      if (mounted) {
        showFeedback(context, 'تعذّر فتح الإعدادات. افتحها من إعدادات جهازك.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: OnboardingPage(
      onBack: widget.onBack,
      backEnabled: !_busy,
      children: [
        const SizedBox(height: 50),
        Text('فعّل الوصول إلى موقعك', style: AppType.title),
        const SizedBox(height: 8),
        Text(
          'نحتاج موقعك المباشر لعرض موقعك الحالي والتنبيهات القريبة ودعم التوجيه الصحيح.',
          style: AppType.body,
        ),
        const SizedBox(height: 34),
        Center(
          child: Container(
            width: 156,
            height: 156,
            decoration: const BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const FigmaIcon('location', size: 80),
          ),
        ),
        const SizedBox(height: 26),
        SurfaceCard(
          padding: 18,
          radius: 16,
          child: Column(
            children: [
              for (final (index, text) in [
                'إظهار موقعك الحالي وتحديد البلاغ تلقائيًا',
                'التنبيهات القريبة والتوجيه الصحيح',
                'تحديد المجلس المحلي المسؤول عند الحاجة',
              ].indexed) ...[
                if (index > 0) const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FigmaIcon('location_bullet', size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        text,
                        style: AppType.text(
                          16,
                          weight: FontWeight.w500,
                          height: 27,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_problem != null) InlineMessage(locationExplanation(_problem!)),
        if (_problem == LocationProblem.permanentlyDenied ||
            _problem == LocationProblem.serviceDisabled)
          TextButton(onPressed: _settings, child: const Text('فتح الإعدادات')),
        const SizedBox(height: 32),
        AppButton(
          _busy ? 'جارٍ تحديد موقعك' : 'السماح بالوصول إلى الموقع',
          busy: _busy,
          onPressed: _request,
        ),
        const SizedBox(height: 12),
        AppButton(
          'ليس الآن',
          secondary: true,
          minHeight: 48,
          onPressed: _busy
              ? null
              : () {
                  showFeedback(
                    context,
                    'الموقع مطلوب للإبلاغ عن حريق والتنبيهات القريبة. يمكنك تفعيله لاحقًا.',
                  );
                  widget.onContinue(null);
                },
        ),
        const SizedBox(height: 12),
        Text(
          'يمكنك تغيير الإذن لاحقًا من الإعدادات',
          style: AppType.caption,
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
