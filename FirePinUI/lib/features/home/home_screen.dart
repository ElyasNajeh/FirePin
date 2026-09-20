import 'package:flutter/material.dart';

import '../../core/ui/app_shell.dart';
import '../../core/ui/components.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';
import '../account/account_screen.dart';
import '../alerts/alerts_screen.dart';
import '../incidents/incident_controller.dart';
import '../incidents/incident_screen.dart';
import '../onboarding/onboarding_models.dart';
import '../report/fire_report_repository.dart';
import '../report/fire_reports_screen.dart';
import '../../core/services/device_services.dart';

/// Authenticated product shell. All role views observe one incident controller.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.hasLocation,
    required this.onReport,
    this.session,
    this.incidentController,
    this.onLogout,
    this.onApplyVolunteer,
    this.reportRepository,
    this.location,
  });

  final bool hasLocation;
  final VoidCallback onReport;
  final OnboardingSession? session;
  final IncidentController? incidentController;
  final Future<void> Function()? onLogout;
  final VoidCallback? onApplyVolunteer;
  final FireReportRepository? reportRepository;
  final LocationService? location;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppSection _section = AppSection.home;
  late final bool _ownsController = widget.incidentController == null;
  late final IncidentController _incidents =
      widget.incidentController ?? IncidentController();
  late final OnboardingSession _fallbackSession = OnboardingSession()
    ..role = UsageRole.citizen
    ..phone = '059 123 4567';

  OnboardingSession get _session => widget.session ?? _fallbackSession;
  FireIncident? get _incident => _incidents.incident;
  bool get _isReporter {
    final incident = _incident;
    return incident != null &&
        ((incident.reporterId?.isNotEmpty == true &&
                incident.reporterId == _session.participantId) ||
            (_session.phone.isNotEmpty &&
                incident.reporterPhone == _session.phone));
  }

  bool get _isApprovedVolunteer =>
      _session.role == UsageRole.volunteer &&
      (_session.applicationStatus == ApplicationStatus.accepted ||
          _session.applicationStatus == ApplicationStatus.none);

  @override
  void dispose() {
    if (_ownsController) _incidents.dispose();
    super.dispose();
  }

  void _changeSection(AppSection section) => setState(() => _section = section);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _incidents,
    builder: (context, _) => AppShell(
      section: _section,
      onSectionChanged: _changeSection,
      child: AnimatedSwitcher(
        duration: AppMotion.reduced(context)
            ? Duration.zero
            : AppMotion.selection,
        child: switch (_section) {
          AppSection.home => _buildHome(),
          AppSection.alerts =>
            widget.reportRepository != null && widget.location != null
                ? FireReportsScreen(
                    key: const ValueKey('real-reports'),
                    role: _session.role,
                    repository: widget.reportRepository!,
                    location: widget.location!,
                  )
                : AlertsScreen(
                    key: const ValueKey('alerts'),
                    role: _session.role,
                    controller: _incidents,
                    isReporter: _isReporter,
                    viewerId: _session.participantId,
                    onOpenIncident: () => _changeSection(AppSection.home),
                  ),
          AppSection.account => AccountScreen(
            key: const ValueKey('account'),
            session: _session,
            incidentController: _incidents,
            onChangePin: () =>
                showFeedback(context, 'تغيير رمز الدخول سيتوفر مع ربط الحساب.'),
            onLogout: widget.onLogout == null
                ? () => showFeedback(
                    context,
                    'تسجيل الخروج غير مفعّل في جلسة العرض المحلية.',
                  )
                : () => widget.onLogout!(),
            onApplyVolunteer: widget.onApplyVolunteer,
          ),
        },
      ),
    ),
  );

  Widget _buildHome() {
    final incident = _incident;
    if (incident == null ||
        (_isApprovedVolunteer &&
            incident.isDeclinedFor(_session.participantId))) {
      return _isApprovedVolunteer
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
    final perspective = _isApprovedVolunteer
        ? IncidentPerspective.volunteer
        : _isReporter
        ? IncidentPerspective.reporter
        : IncidentPerspective.nearbyCitizen;
    return IncidentScreen(
      key: ValueKey('${incident.id}-${incident.stage}-$perspective'),
      incident: incident,
      perspective: perspective,
      controller: _incidents,
      viewerId: _session.participantId,
      volunteerDisplayName: _session.identity?.fullName,
      volunteerPhone: _session.phone,
      onViewPhoto: () => showIncidentPhoto(context, incident),
      onContactReporter: () => showReporterContact(context, incident),
    );
  }
}

Future<void> showIncidentPhoto(
  BuildContext context,
  FireIncident incident,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        incident.hasPhoto ? 'الصورة المرسلة' : 'صورة البلاغ',
        style: AppType.section,
      ),
      content: !incident.hasPhoto
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.image_not_supported_outlined,
                  size: 48,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  'تم إرسال هذا البلاغ بدون صورة.',
                  textAlign: TextAlign.center,
                  style: AppType.caption,
                ),
              ],
            )
          : incident.photo == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_done_outlined,
                  size: 48,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 12),
                Text(
                  'تم تسجيل وجود صورة في الخادم التجريبي، لكن بايتات الصورة تبقى على جهاز المُبلّغ فقط.',
                  textAlign: TextAlign.center,
                  style: AppType.caption,
                ),
              ],
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                incident.photo!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Text(
                  'تعذّر عرض الصورة داخل هذه الجلسة.',
                  style: AppType.caption,
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('إغلاق'),
        ),
      ],
    ),
  );
}

Future<void> showReporterContact(
  BuildContext context,
  FireIncident incident,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('التواصل مع المُبلّغ', style: AppType.section),
            const SizedBox(height: 4),
            Text(
              'استخدم الرقم فقط لتنسيق الاستجابة لهذا الحادث.',
              style: AppType.caption,
            ),
            const SizedBox(height: 14),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                incident.reporterPhone,
                textAlign: TextAlign.center,
                style: AppType.text(22, weight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 14),
            AppButton('إغلاق', onPressed: () => Navigator.pop(sheetContext)),
          ],
        ),
      ),
    ),
  );
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
      _ReferenceMap(hasLocation: hasLocation),
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
      _ReferenceMap(hasLocation: hasLocation),
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
