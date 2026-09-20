import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/device_services.dart';
import '../../core/ui/app_shell.dart';
import '../../core/ui/components.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';
import '../account/account_screen.dart';
import '../onboarding/onboarding_models.dart';
import '../report/fire_report_repository.dart';
import '../report/fire_reports_screen.dart';

/// Authenticated user shell backed entirely by the FirePin API and device GPS.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onReport,
    required this.session,
    required this.onLogout,
    required this.reportRepository,
    required this.location,
    this.onApplyVolunteer,
  });

  final ValueChanged<LocationFix> onReport;
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

  Widget _buildHome() => widget.session.role == UsageRole.volunteer
      ? _VolunteerReadyContent(
          key: const ValueKey('volunteer-ready'),
          onOpenAlerts: () => _changeSection(AppSection.alerts),
        )
      : _CitizenHomeContent(
          key: const ValueKey('citizen-location-home'),
          locationService: widget.location,
          onReport: widget.onReport,
        );
}

class _CitizenHomeContent extends StatefulWidget {
  const _CitizenHomeContent({
    super.key,
    required this.locationService,
    required this.onReport,
  });

  final LocationService locationService;
  final ValueChanged<LocationFix> onReport;

  @override
  State<_CitizenHomeContent> createState() => _CitizenHomeContentState();
}

class _CitizenHomeContentState extends State<_CitizenHomeContent> {
  LocationFix? _location;
  LocationProblem? _problem;
  bool _loading = true;
  bool _mapError = false;
  int _mapGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    setState(() {
      _loading = true;
      _problem = null;
      _mapError = false;
    });
    try {
      final location = await widget.locationService.requestCurrentPosition();
      if (mounted) setState(() => _location = location);
    } on LocationFailure catch (error) {
      if (mounted) {
        setState(() {
          _location = null;
          _problem = error.problem;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _location = null;
          _problem = LocationProblem.unavailable;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSettings() async {
    final problem = _problem;
    try {
      final opened = await widget.locationService.openSettings(
        locationService: problem == LocationProblem.serviceDisabled,
      );
      if (!opened && mounted) {
        showFeedback(context, 'افتح إعدادات الجهاز وفعّل الموقع.');
      }
    } on Object {
      if (mounted) {
        showFeedback(context, 'تعذّر فتح إعدادات الموقع.');
      }
    }
  }

  void _handleTileError(Object error) {
    if (_mapError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_mapError) setState(() => _mapError = true);
    });
  }

  void _retryMap() {
    setState(() {
      _mapError = false;
      _mapGeneration++;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('موقعك الحالي', style: AppType.section),
      const SizedBox(height: 10),
      if (_loading)
        const SurfaceCard(
          child: SizedBox(
            height: 250,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('جارٍ تحديد موقعك الحقيقي...'),
                ],
              ),
            ),
          ),
        )
      else if (_location == null)
        SurfaceCard(
          key: const ValueKey('citizen-location-error'),
          warning: true,
          child: Column(
            children: [
              const Icon(Icons.location_off, size: 44),
              const SizedBox(height: 10),
              Text(
                locationExplanation(_problem ?? LocationProblem.unavailable),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              AppButton('إعادة المحاولة', onPressed: _loadLocation),
              if (_problem == LocationProblem.permanentlyDenied ||
                  _problem == LocationProblem.serviceDisabled) ...[
                const SizedBox(height: 8),
                AppButton(
                  'فتح إعدادات الموقع',
                  secondary: true,
                  onPressed: _openSettings,
                ),
              ],
            ],
          ),
        )
      else
        _CurrentLocationMap(
          key: ValueKey('citizen-location-map-$_mapGeneration'),
          location: _location!,
          mapError: _mapError,
          onTileError: _handleTileError,
          onRetryMap: _retryMap,
        ),
      const SizedBox(height: 18),
      AppButton(
        '🔥 إبلاغ عن حريق',
        key: const ValueKey('create-fire-report'),
        emergency: true,
        minHeight: 72,
        fontSize: 21,
        onPressed: _location == null || _loading
            ? null
            : () => widget.onReport(_location!),
      ),
      const SizedBox(height: 10),
      Text(
        _location == null
            ? 'يجب تحديد موقعك قبل إنشاء البلاغ'
            : 'سيُعاد التحقق من موقعك عند إرسال البلاغ',
        style: AppType.caption,
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class _CurrentLocationMap extends StatelessWidget {
  const _CurrentLocationMap({
    super.key,
    required this.location,
    required this.mapError,
    required this.onTileError,
    required this.onRetryMap,
  });

  final LocationFix location;
  final bool mapError;
  final ValueChanged<Object> onTileError;
  final VoidCallback onRetryMap;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(location.latitude, location.longitude);
    return SizedBox(
      height: 320,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(initialCenter: point, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.firepin.firepin_ui',
                  errorTileCallback: (_, error, _) => onTileError(error),
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.my_location,
                        key: ValueKey('citizen-current-location-marker'),
                        color: AppColors.primary,
                        size: 38,
                      ),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.bottomLeft,
                  child: ColoredBox(
                    color: Colors.white70,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      child: Text('© OpenStreetMap contributors'),
                    ),
                  ),
                ),
              ],
            ),
            if (mapError)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xDDFFFFFF),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'تعذّر تحميل خريطة OpenStreetMap.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          AppButton(
                            'إعادة تحميل الخريطة',
                            secondary: true,
                            onPressed: onRetryMap,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VolunteerReadyContent extends StatelessWidget {
  const _VolunteerReadyContent({super.key, required this.onOpenAlerts});

  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) => SurfaceCard(
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
          'أنت متاح لاستقبال نداءات الحرائق ضمن بلديتك.',
          style: AppType.caption,
        ),
        const SizedBox(height: 12),
        AppButton('عرض التنبيهات', onPressed: onOpenAlerts),
      ],
    ),
  );
}
