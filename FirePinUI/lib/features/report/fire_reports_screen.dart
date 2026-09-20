import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/device_services.dart';
import '../../core/ui/components.dart';
import '../../theme/app_theme.dart';
import '../onboarding/onboarding_models.dart';
import 'fire_report_repository.dart';

class FireReportsScreen extends StatefulWidget {
  const FireReportsScreen({
    super.key,
    required this.role,
    required this.repository,
    required this.location,
  });

  final UsageRole role;
  final FireReportRepository repository;
  final LocationService location;

  @override
  State<FireReportsScreen> createState() => _FireReportsScreenState();
}

class _FireReportsScreenState extends State<FireReportsScreen> {
  bool _loading = true;
  Object? _error;
  List<FireReport> _reports = const [];

  bool get _volunteer => widget.role == UsageRole.volunteer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reports = _volunteer
          ? await widget.repository.getVolunteerReports()
          : await widget.repository.getMyReports();
      if (mounted) setState(() => _reports = reports);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(FireReport summary) async {
    try {
      final report = _volunteer
          ? await widget.repository.getVolunteerReport(summary.id)
          : await widget.repository.getMyReport(summary.id);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => FireReportDetailScreen(
            report: report,
            volunteer: _volunteer,
            repository: widget.repository,
            location: widget.location,
          ),
        ),
      );
    } catch (_) {
      if (mounted) showFeedback(context, 'تعذّر تحميل تفاصيل البلاغ.');
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      key: const ValueKey('real-fire-report-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        PageTitle(_volunteer ? 'بلاغات البلدية' : 'بلاغاتي'),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _ReportError(onRetry: _load)
        else if (_reports.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: Text('لا توجد بلاغات حتى الآن.')),
          )
        else
          for (final report in _reports) ...[
            SurfaceCard(
              child: ListTile(
                key: ValueKey('fire-report-${report.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.local_fire_department,
                  color: AppColors.emergency,
                ),
                title: Text('بلاغ #${report.id}'),
                subtitle: Text(
                  '${report.municipality.name} · ${_status(report.status)}\n'
                  '${_dateTime(report.reportedAt)}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _open(report),
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    ),
  );
}

class FireReportDetailScreen extends StatefulWidget {
  const FireReportDetailScreen({
    super.key,
    required this.report,
    required this.volunteer,
    required this.repository,
    required this.location,
  });

  final FireReport report;
  final bool volunteer;
  final FireReportRepository repository;
  final LocationService location;

  @override
  State<FireReportDetailScreen> createState() => _FireReportDetailScreenState();
}

class _FireReportDetailScreenState extends State<FireReportDetailScreen> {
  bool _routing = false;
  Object? _routeError;
  LocationFix? _origin;
  FireReportRoute? _route;

  @override
  void initState() {
    super.initState();
    if (widget.volunteer) _loadRoute();
  }

  Future<void> _loadRoute() async {
    setState(() {
      _routing = true;
      _routeError = null;
      _route = null;
      _origin = null;
    });
    try {
      final origin = await widget.location.requestCurrentPosition();
      final route = await widget.repository.getVolunteerRoute(
        widget.report.id,
        origin,
      );
      if (mounted) {
        setState(() {
          _origin = origin;
          _route = route;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _routeError = error);
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('بلاغ #${widget.report.id}')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        FireReportMap(report: widget.report, origin: _origin, route: _route),
        const SizedBox(height: 12),
        if (_routing)
          const Center(child: CircularProgressIndicator())
        else if (_routeError != null)
          SurfaceCard(
            warning: true,
            child: Column(
              children: [
                const Text('تعذّر تحميل مسار الطريق الحقيقي.'),
                const SizedBox(height: 8),
                AppButton(
                  'إعادة المحاولة',
                  secondary: true,
                  onPressed: _loadRoute,
                ),
              ],
            ),
          )
        else if (_route != null)
          SurfaceCard(
            key: const ValueKey('route-summary'),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('${_route!.distanceKm.toStringAsFixed(1)} كم'),
                Text('${(_route!.durationSeconds / 60).ceil()} دقيقة'),
              ],
            ),
          ),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_status(widget.report.status), style: AppType.section),
              Text(widget.report.municipality.name, style: AppType.body),
              Text(_dateTime(widget.report.reportedAt), style: AppType.caption),
              Text(
                '${widget.report.latitude}, ${widget.report.longitude}',
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
        for (final image in widget.report.images) ...[
          const SizedBox(height: 12),
          _ProtectedReportImage(
            load: () => widget.repository.getImage(widget.report.id, image.id),
          ),
        ],
      ],
    ),
  );
}

class FireReportMap extends StatelessWidget {
  const FireReportMap({
    super.key,
    required this.report,
    this.origin,
    this.route,
  });

  final FireReport report;
  final LocationFix? origin;
  final FireReportRoute? route;

  @override
  Widget build(BuildContext context) {
    final fire = LatLng(report.latitude, report.longitude);
    final routePoints =
        route?.geometry
            .map((point) => LatLng(point.latitude, point.longitude))
            .toList(growable: false) ??
        const <LatLng>[];
    final visible = [
      fire,
      if (origin != null) LatLng(origin!.latitude, origin!.longitude),
      ...routePoints,
    ];
    return SizedBox(
      key: const ValueKey('real-fire-report-map'),
      height: 340,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: fire,
            initialZoom: 14,
            initialCameraFit: visible.length > 1
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(visible),
                    padding: const EdgeInsets.all(42),
                  )
                : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.firepin.firepin_ui',
            ),
            if (routePoints.isNotEmpty)
              PolylineLayer(
                key: const ValueKey('backend-route-polyline'),
                polylines: [
                  Polyline(
                    points: routePoints,
                    strokeWidth: 5,
                    color: AppColors.primary,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: fire,
                  width: 44,
                  height: 44,
                  child: const Icon(
                    Icons.local_fire_department,
                    color: AppColors.emergency,
                    size: 38,
                  ),
                ),
                if (origin != null)
                  Marker(
                    point: LatLng(origin!.latitude, origin!.longitude),
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.my_location,
                      color: AppColors.primary,
                      size: 34,
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
      ),
    );
  }
}

class _ProtectedReportImage extends StatefulWidget {
  const _ProtectedReportImage({required this.load});
  final Future<Uint8List> Function() load;

  @override
  State<_ProtectedReportImage> createState() => _ProtectedReportImageState();
}

class _ProtectedReportImageState extends State<_ProtectedReportImage> {
  late final Future<Uint8List> _image = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _image,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const SurfaceCard(child: Text('تعذّر تحميل صورة البلاغ.'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(snapshot.data!, fit: BoxFit.cover),
      );
    },
  );
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    warning: true,
    child: Column(
      children: [
        const Text('تعذّر تحميل البلاغات من الخادم.'),
        const SizedBox(height: 8),
        AppButton('إعادة المحاولة', secondary: true, onPressed: onRetry),
      ],
    ),
  );
}

String _status(FireReportStatus status) => switch (status) {
  FireReportStatus.pending => 'قيد الانتظار',
  FireReportStatus.assigned => 'تم تعيين متطوع',
  FireReportStatus.resolved => 'تمت المعالجة',
};

String _dateTime(DateTime value) =>
    '${value.day}/${value.month}/${value.year} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
