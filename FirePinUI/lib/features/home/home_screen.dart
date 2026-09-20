import 'package:flutter/material.dart';

import '../../core/ui/app_shell.dart';
import '../../core/ui/components.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';
import '../account/account_screen.dart';
import '../onboarding/onboarding_models.dart';
import '../report/fire_report_repository.dart';
import '../report/fire_reports_screen.dart';
import '../../core/services/device_services.dart';

/// Authenticated user shell backed entirely by the FirePin API.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.hasLocation,
    required this.onReport,
    required this.session,
    required this.onLogout,
    required this.reportRepository,
    required this.location,
    this.onApplyVolunteer,
  });

  final bool hasLocation;
  final VoidCallback onReport;
  final OnboardingSession session;
  final Future<void> Function() onLogout;
  final VoidCallback? onApplyVolunteer;
  final FireReportRepository reportRepository;
  final LocationService location;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppSection _section = AppSection.home;

  void _changeSection(AppSection section) => setState(() => _section = section);

  @override
  Widget build(BuildContext context) => AppShell(
    section: _section,
    onSectionChanged: _changeSection,
    child: AnimatedSwitcher(
      duration: AppMotion.reduced(context)
          ? Duration.zero
          : AppMotion.selection,
      child: switch (_section) {
        AppSection.home => _buildHome(),
        AppSection.alerts => FireReportsScreen(
          key: const ValueKey('real-reports'),
          role: widget.session.role,
          repository: widget.reportRepository,
          location: widget.location,
          viewerUserId: widget.session.accountId,
        ),
        AppSection.account => AccountScreen(
          key: const ValueKey('account'),
          session: widget.session,
          onLogout: widget.onLogout,
          onApplyVolunteer: widget.onApplyVolunteer,
        ),
      },
    ),
  );

  Widget _buildHome() {
    return widget.session.role == UsageRole.volunteer
        ? _VolunteerReadyContent(
            key: const ValueKey('volunteer-ready'),
            hasLocation: widget.hasLocation,
            onOpenAlerts: () => _changeSection(AppSection.alerts),
          )
        : _CitizenHomeContent(
            key: const ValueKey('home'),
            hasLocation: widget.hasLocation,
            onReport: widget.onReport,
          );
  }
}

class _CitizenHomeContent extends StatelessWidget {
  const _CitizenHomeContent({
    super.key,
    required this.hasLocation,
    required this.onReport,
  });
  final bool hasLocation;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _LocationStatusCard(hasLocation: hasLocation),
      const SizedBox(height: 24),
      AppButton(
        '🔥 إبلاغ عن حريق',
        emergency: true,
        minHeight: 72,
        fontSize: 21,
        onPressed: onReport,
      ),
      const SizedBox(height: 10),
      Text(
        hasLocation
            ? 'سيتم تحديد موقع البلاغ تلقائيًا'
            : 'فعّل الموقع لتحديد مكان البلاغ عند الإرسال',
        style: AppType.caption,
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class _VolunteerReadyContent extends StatelessWidget {
  const _VolunteerReadyContent({
    super.key,
    required this.hasLocation,
    required this.onOpenAlerts,
  });
  final bool hasLocation;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _LocationStatusCard(hasLocation: hasLocation),
      const SizedBox(height: 20),
      SurfaceCard(
        padding: 18,
        shadow: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '✓ متطوع معتمد',
              style: AppType.text(
                18,
                weight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'أنت متاح لاستقبال نداءات الحرائق ضمن منطقتك.',
              style: AppType.caption,
            ),
            const SizedBox(height: 12),
            AppButton('عرض التنبيهات', onPressed: onOpenAlerts),
          ],
        ),
      ),
    ],
  );
}

class _LocationStatusCard extends StatelessWidget {
  const _LocationStatusCard({required this.hasLocation});
  final bool hasLocation;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    shadow: true,
    child: Row(
      children: [
        Icon(
          hasLocation ? Icons.location_on : Icons.location_off,
          color: hasLocation ? AppColors.primary : AppColors.textSecondary,
          size: 40,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasLocation ? 'الموقع متاح' : 'سيُطلب موقعك عند إرسال البلاغ',
                style: AppType.section,
              ),
              Text(
                'تُرسل الإحداثيات الحقيقية إلى الخادم عند إنشاء بلاغ.',
                style: AppType.caption,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
