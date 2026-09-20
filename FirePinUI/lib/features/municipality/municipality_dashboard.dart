import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/ui/components.dart';
import '../../theme/app_theme.dart';
import '../auth/auth_models.dart';
import '../onboarding/onboarding_models.dart';
import '../report/fire_report_repository.dart';
import 'municipality_repository.dart';

enum MunicipalitySection {
  overview,
  activeIncidents,
  applications,
  volunteers,
  history,
  account,
}

class MunicipalityDashboard extends StatefulWidget {
  const MunicipalityDashboard({
    super.key,
    required this.account,
    required this.repository,
    required this.onLogout,
  });
  final MunicipalityAccount account;
  final MunicipalityRepository repository;
  final Future<void> Function() onLogout;

  @override
  State<MunicipalityDashboard> createState() => _MunicipalityDashboardState();
}

class _MunicipalityDashboardState extends State<MunicipalityDashboard> {
  MunicipalitySection _section = MunicipalitySection.overview;

  @override
  void initState() {
    super.initState();
    unawaited(_reloadVolunteerData());
  }

  Future<void> _reloadVolunteerData() async {
    try {
      await widget.repository.loadVolunteerData();
    } on Object {
      // The repository exposes the error so the dashboard can offer retry.
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: wide
              ? null
              : AppBar(
                  title: Text(_label(_section)),
                  actions: [
                    IconButton(
                      tooltip: 'تحديث',
                      onPressed: widget.repository.isVolunteerDataLoading
                          ? null
                          : _reloadVolunteerData,
                      icon: const Icon(Icons.refresh),
                    ),
                    const Padding(
                      padding: EdgeInsetsDirectional.only(end: 16),
                      child: BrandHeader(),
                    ),
                  ],
                ),
          drawer: wide ? null : Drawer(child: _navigation(compact: true)),
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  SizedBox(width: 250, child: _navigation(compact: false)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 30 : 18),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: _content(wide),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _navigation({required bool compact}) => Material(
    color: Colors.white,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!compact) ...[
              const BrandHeader(),
              const SizedBox(height: 8),
              Text(widget.account.name, style: AppType.section),
              Text('مركز العمليات', style: AppType.caption),
              const SizedBox(height: 24),
            ],
            for (final item in MunicipalitySection.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: ListTile(
                  selected: item == _section,
                  selectedTileColor: AppColors.primaryContainer,
                  selectedColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: Icon(_icon(item)),
                  title: Text(_label(item)),
                  onTap: () {
                    setState(() => _section = item);
                    if (compact) Navigator.pop(context);
                  },
                ),
              ),
            const Spacer(),
            Text(
              'آخر مزامنة: الآن',
              style: AppType.text(11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _content(bool wide) => Column(
    key: ValueKey(_section),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (wide) ...[
        Row(
          children: [
            Expanded(child: PageTitle(_label(_section))),
            IconButton(
              tooltip: 'تحديث',
              onPressed: widget.repository.isVolunteerDataLoading
                  ? null
                  : _reloadVolunteerData,
              icon: const Icon(Icons.refresh),
            ),
            _LiveStatus(connected: !widget.repository.hasSyncError),
          ],
        ),
        const SizedBox(height: 22),
      ],
      switch (_section) {
        MunicipalitySection.overview => _overview(wide),
        MunicipalitySection.activeIncidents => _incidents(resolved: false),
        MunicipalitySection.applications => _volunteerData(_applications()),
        MunicipalitySection.volunteers => _volunteerData(_volunteers()),
        MunicipalitySection.history => _incidents(resolved: true),
        MunicipalitySection.account => _account(),
      },
    ],
  );

  Widget _overview(bool wide) {
    final incidents = widget.repository.reports;
    final active = incidents.where((item) => !item.isResolved).toList();
    final resolved = incidents.where((item) => item.isResolved).toList();
    final pending = widget.repository.applications
        .where((item) => item.status == ApplicationStatus.pending)
        .length;
    final stats = [
      (
        'الحرائق النشطة',
        '${active.length}',
        Icons.local_fire_department,
        AppColors.emergency,
      ),
      (
        'طلبات التطوع قيد المراجعة',
        '$pending',
        Icons.how_to_reg,
        const Color(0xFFB26A00),
      ),
      (
        'المتطوعون المعتمدون',
        '${widget.repository.volunteers.length}',
        Icons.volunteer_activism,
        AppColors.primary,
      ),
      (
        'الحالات التي تمت معالجتها',
        '${resolved.length}',
        Icons.task_alt,
        const Color(0xFF287A59),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: wide ? 4 : 2,
            mainAxisExtent: 170,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: stats.length,
          itemBuilder: (_, index) {
            final stat = stats[index];
            return _StatCard(
              label: stat.$1,
              value: stat.$2,
              icon: stat.$3,
              color: stat.$4,
            );
          },
        ),
        const SizedBox(height: 22),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _OperationsMap(incidents: active)),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: _ActiveSummary(incidents: active, onOpen: _openIncident),
              ),
            ],
          )
        else ...[
          _OperationsMap(incidents: active),
          const SizedBox(height: 16),
          _ActiveSummary(incidents: active, onOpen: _openIncident),
        ],
      ],
    );
  }

  Widget _volunteerData(Widget child) {
    if (widget.repository.isVolunteerDataLoading &&
        widget.repository.applications.isEmpty &&
        widget.repository.volunteers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.repository.volunteerDataError != null &&
        widget.repository.applications.isEmpty &&
        widget.repository.volunteers.isEmpty) {
      return _VolunteerDataError(onRetry: _reloadVolunteerData);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.repository.volunteerDataError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _VolunteerDataError(onRetry: _reloadVolunteerData),
          ),
        child,
      ],
    );
  }

  Widget _incidents({required bool resolved}) {
    final items = widget.repository.reports
        .where((item) => item.isResolved == resolved)
        .toList();
    if (items.isEmpty) return const _EmptyState('لا توجد بلاغات في هذا القسم.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final incident in items) ...[
          _IncidentCard(
            incident: incident,
            onOpen: () => _openIncident(incident),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _applications() => DefaultTabController(
    length: 3,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'قيد المراجعة'),
            Tab(text: 'مقبول'),
            Tab(text: 'مرفوض'),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 520,
          child: TabBarView(
            children: [
              _applicationList(ApplicationStatus.pending),
              _applicationList(ApplicationStatus.accepted),
              _applicationList(ApplicationStatus.rejected),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _applicationList(ApplicationStatus status) {
    final items = widget.repository.applications
        .where((item) => item.status == status)
        .toList();
    if (items.isEmpty) return const _EmptyState('لا توجد طلبات بهذه الحالة.');
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final item = items[index];
        return SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item.fullName, style: AppType.section),
              const SizedBox(height: 8),
              Wrap(
                spacing: 20,
                runSpacing: 6,
                children: [
                  Text('الهوية: ${item.nationalId}', style: AppType.caption),
                  Text('الهاتف: ${item.phone}', style: AppType.caption),
                  Text('الميلاد: ${item.birthDate}', style: AppType.caption),
                  Text(
                    'تاريخ الطلب: ${_date(item.requestedAt)}',
                    style: AppType.caption,
                  ),
                ],
              ),
              if (status == ApplicationStatus.pending) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        'قبول',
                        onPressed: () => _manageApplication(item.id, true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton(
                        'رفض',
                        secondary: true,
                        onPressed: () => _manageApplication(item.id, false),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _volunteers() {
    final activeResponders = widget.repository.reports
        .where((item) => !item.isResolved)
        .map((item) => item.assignedVolunteer)
        .whereType<AssignedVolunteer>()
        .toList();
    final activeIds = activeResponders.map((response) => response.id).toSet();
    final activePhones = activeResponders
        .map((response) => response.phone)
        .toSet();
    if (widget.repository.volunteers.isEmpty) {
      return const _EmptyState('لا يوجد متطوعون معتمدون بعد.');
    }
    return Column(
      children: [
        for (final volunteer in widget.repository.volunteers) ...[
          SurfaceCard(
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.primaryContainer,
                  child: Icon(Icons.person, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(volunteer.fullName, style: AppType.section),
                      Text(
                        '${volunteer.phone}  •  ${volunteer.nationalId}',
                        style: AppType.caption,
                      ),
                      Text(
                        'اعتماد: ${_date(volunteer.joinedAt)}',
                        style: AppType.caption,
                      ),
                    ],
                  ),
                ),
                _StatusBadge(
                  activeIds.contains(volunteer.id) ||
                          activePhones.contains(volunteer.phone)
                      ? 'في استجابة'
                      : 'متاح',
                  warning:
                      activeIds.contains(volunteer.id) ||
                      activePhones.contains(volunteer.phone),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Future<void> _manageApplication(int id, bool accept) async {
    try {
      if (accept) {
        await widget.repository.acceptApplication(id);
      } else {
        await widget.repository.rejectApplication(id);
      }
    } on Object {
      if (mounted) {
        showFeedback(context, 'تعذّر تحديث طلب التطوع. حاول مجددًا.');
      }
    }
  }

  Widget _account() => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 680),
    child: SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primaryContainer,
                child: Icon(
                  Icons.apartment,
                  color: AppColors.primary,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.account.name, style: AppType.section),
                    Text(widget.account.email, style: AppType.caption),
                    Text(widget.account.serviceArea, style: AppType.caption),
                  ],
                ),
              ),
              _StatusBadge(widget.account.isActive ? 'حساب نشط' : 'غير نشط'),
            ],
          ),
          const SizedBox(height: 24),
          AppButton(
            'تسجيل الخروج',
            secondary: true,
            onPressed: widget.onLogout,
          ),
        ],
      ),
    ),
  );

  void _openIncident(MunicipalityFireReport incident) {
    showDialog<void>(
      context: context,
      builder: (_) => AnimatedBuilder(
        animation: widget.repository,
        builder: (context, _) {
          final current = widget.repository.reports
              .where((item) => item.id == incident.id)
              .firstOrNull;
          return MunicipalityReportDetailsDialog(incident: current ?? incident);
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: 16,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const Spacer(),
        Text(
          value,
          style: AppType.text(28, weight: FontWeight.w700, color: color),
        ),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppType.caption,
        ),
      ],
    ),
  );
}

class _OperationsMap extends StatelessWidget {
  const _OperationsMap({required this.incidents});
  final List<MunicipalityFireReport> incidents;

  @override
  Widget build(BuildContext context) {
    if (incidents.isEmpty) {
      return SurfaceCard(
        child: SizedBox(
          height: 290,
          child: Center(
            child: Text('لا توجد بلاغات نشطة.', style: AppType.caption),
          ),
        ),
      );
    }
    final points = [
      for (final incident in incidents)
        LatLng(incident.latitude, incident.longitude),
    ];
    final center = LatLng(
      points.map((point) => point.latitude).reduce((a, b) => a + b) /
          points.length,
      points.map((point) => point.longitude).reduce((a, b) => a + b) /
          points.length,
    );
    return SurfaceCard(
      padding: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 330,
          child: FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.firepin.firepin_ui',
              ),
              MarkerLayer(
                markers: [
                  for (final incident in incidents)
                    Marker(
                      key: ValueKey('municipality-fire-${incident.id}'),
                      point: LatLng(incident.latitude, incident.longitude),
                      width: 42,
                      height: 42,
                      child: const CircleAvatar(
                        backgroundColor: AppColors.emergency,
                        child: Icon(
                          Icons.local_fire_department,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveSummary extends StatelessWidget {
  const _ActiveSummary({required this.incidents, required this.onOpen});
  final List<MunicipalityFireReport> incidents;
  final ValueChanged<MunicipalityFireReport> onOpen;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('البلاغات الحالية', style: AppType.section),
        const SizedBox(height: 10),
        if (incidents.isEmpty)
          Text('لا توجد بلاغات نشطة.', style: AppType.caption),
        for (final incident in incidents.take(4))
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.local_fire_department,
                color: AppColors.emergency,
              ),
              title: Text('#${incident.id}'),
              subtitle: Text(
                '${_status(incident.status)} · ${_assignmentSummary(incident.assignedVolunteer)}\n${incident.locationLabel}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_left),
              onTap: () => onOpen(incident),
            ),
          ),
      ],
    ),
  );
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({required this.incident, required this.onOpen});
  final MunicipalityFireReport incident;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: InkWell(
      onTap: onOpen,
      child: Row(
        children: [
          Icon(
            incident.isResolved ? Icons.task_alt : Icons.local_fire_department,
            color: incident.isResolved
                ? AppColors.primary
                : AppColors.emergency,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${incident.id} • ${_status(incident.status)}',
                  style: AppType.section,
                ),
                Text(
                  '${incident.locationLabel} • ${_dateTime(incident.reportedAt)}',
                  style: AppType.caption,
                ),
                Text(
                  _assignmentSummary(incident.assignedVolunteer),
                  style: AppType.caption,
                ),
                if (incident.assignedVolunteer != null)
                  Text(
                    incident.assignedVolunteer!.fullName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption,
                  ),
              ],
            ),
          ),
          const Icon(Icons.chevron_left),
        ],
      ),
    ),
  );
}

class MunicipalityReportDetailsDialog extends StatelessWidget {
  const MunicipalityReportDetailsDialog({super.key, required this.incident});
  final MunicipalityFireReport incident;
  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'تفاصيل البلاغ #${incident.id}',
                    style: AppType.section,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'إغلاق',
                ),
              ],
            ),
            _StatusBadge(
              _status(incident.status),
              warning: !incident.isResolved,
            ),
            const SizedBox(height: 14),
            _OperationsMap(incidents: [incident]),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _Detail('الموقع', incident.locationLabel),
                _Detail('وقت البلاغ', _dateTime(incident.reportedAt)),
                _Detail('المُبلّغ', incident.reporterName),
                _Detail('هاتف المُبلّغ', incident.reporterPhone),
                _Detail('رقم الهوية', incident.reporterNationalId),
                _Detail('الجهة المسؤولة', incident.municipalityName),
                _Detail(
                  'المتطوع المعيّن',
                  incident.assignedVolunteer?.fullName ?? 'غير معيّن',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('المتطوع المعيّن', style: AppType.section),
            const SizedBox(height: 8),
            if (incident.assignedVolunteer == null)
              Text('لم يتم تعيين متطوع بعد.', style: AppType.caption)
            else
              _ResponderCard(response: incident.assignedVolunteer!),
          ],
        ),
      ),
    ),
  );
}

class _ResponderCard extends StatelessWidget {
  const _ResponderCard({required this.response});
  final AssignedVolunteer response;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('municipality-responder-detail-${response.id}'),
    width: 210,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          response.fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.text(13, weight: FontWeight.w700),
        ),
        if (response.phone.isNotEmpty)
          Text(response.phone, style: AppType.caption),
        Text(
          'المتطوع المعيّن للبلاغ',
          style: AppType.text(11, color: AppColors.primary),
        ),
      ],
    ),
  );
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 200,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppType.caption),
        Text(value, style: AppType.text(14, weight: FontWeight.w700)),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.label, {this.warning = false});
  final String label;
  final bool warning;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFFF1D6) : AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppType.text(
          12,
          weight: FontWeight.w700,
          color: warning ? const Color(0xFF8A5200) : AppColors.primary,
        ),
      ),
    ),
  );
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(
        Icons.circle,
        size: 9,
        color: connected ? const Color(0xFF2E8B62) : const Color(0xFFB26A00),
      ),
      const SizedBox(width: 7),
      Text(
        connected
            ? 'مركز العمليات متصل'
            : 'الخادم التجريبي غير متاح · ستتم إعادة المحاولة',
      ),
    ],
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Text(label, style: AppType.body),
    ),
  );
}

class _VolunteerDataError extends StatelessWidget {
  const _VolunteerDataError({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    warning: true,
    child: Column(
      children: [
        Text('تعذّر تحميل بيانات المتطوعين.', style: AppType.body),
        const SizedBox(height: 10),
        AppButton('إعادة المحاولة', secondary: true, onPressed: onRetry),
      ],
    ),
  );
}

String _status(FireReportStatus status) => switch (status) {
  FireReportStatus.pending => 'جارٍ البحث عن مستجيب',
  FireReportStatus.assigned => 'تم تعيين متطوع',
  FireReportStatus.resolved => 'تمت معالجة الحالة',
};

String _assignmentSummary(AssignedVolunteer? volunteer) =>
    volunteer == null ? 'لم يتم تعيين متطوع' : 'تم تعيين متطوع';

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';
String _dateTime(DateTime value) =>
    '${_date(value)}  ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _label(MunicipalitySection section) => switch (section) {
  MunicipalitySection.overview => 'نظرة عامة',
  MunicipalitySection.activeIncidents => 'البلاغات النشطة',
  MunicipalitySection.applications => 'طلبات التطوع',
  MunicipalitySection.volunteers => 'المتطوعون',
  MunicipalitySection.history => 'السجل',
  MunicipalitySection.account => 'الحساب',
};

IconData _icon(MunicipalitySection section) => switch (section) {
  MunicipalitySection.overview => Icons.dashboard_outlined,
  MunicipalitySection.activeIncidents => Icons.local_fire_department_outlined,
  MunicipalitySection.applications => Icons.how_to_reg_outlined,
  MunicipalitySection.volunteers => Icons.volunteer_activism_outlined,
  MunicipalitySection.history => Icons.history_rounded,
  MunicipalitySection.account => Icons.account_circle_outlined,
};
