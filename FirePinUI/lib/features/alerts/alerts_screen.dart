import 'package:flutter/material.dart';

import '../../core/ui/components.dart';
import '../../theme/app_theme.dart';
import '../incidents/incident_controller.dart';
import '../onboarding/onboarding_models.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({
    super.key,
    required this.role,
    required this.controller,
    required this.isReporter,
    required this.viewerId,
    required this.onOpenIncident,
  });

  final UsageRole role;
  final IncidentController controller;
  final bool isReporter;
  final String viewerId;
  final VoidCallback onOpenIncident;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String _filter = 'الكل';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final volunteer = widget.role == UsageRole.volunteer;
      final incident = widget.controller.incident;
      final showCurrent =
          incident != null &&
          !incident.isResolved &&
          (!volunteer || !incident.isDeclinedFor(widget.viewerId));
      final filters = volunteer
          ? const ['الكل', 'الحالية', 'السجل']
          : const ['الكل', 'الحرائق', 'حالة بلاغاتي'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageTitle('التنبيهات'),
          Text(
            volunteer
                ? 'نداءات الحرائق والتنبيهات المخصصة للمتطوعين المعتمدين.'
                : 'تابع التنبيهات النشطة وسجل حالة البلاغات.',
            style: AppType.caption,
          ),
          if (showCurrent) ...[
            const SizedBox(height: 10),
            Text('يحدث الآن', style: AppType.text(13, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            _CurrentIncidentCard(
              incident: incident,
              volunteer: volunteer,
              isReporter: widget.isReporter,
              viewerId: widget.viewerId,
              onTap: widget.onOpenIncident,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: filters.map((filter) {
              final selected = filter == _filter;
              return ChoiceChip(
                label: Text(filter),
                selected: selected,
                onSelected: (_) => setState(() => _filter = filter),
                showCheckmark: false,
                selectedColor: AppColors.primary,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.outline),
                labelStyle: AppType.text(
                  12,
                  weight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text('سجل الحالة', style: AppType.text(13, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (incident == null)
            const _EmptyAlerts()
          else
            ..._historyFor(incident, volunteer),
        ],
      );
    },
  );

  List<Widget> _historyFor(FireIncident incident, bool volunteer) {
    final events = incident.events.reversed.where((event) {
      if (volunteer) {
        return event.stage != IncidentStage.reported &&
            (event.volunteerId == null || event.volunteerId == widget.viewerId);
      }
      return true;
    });
    return events
        .map(
          (event) => _HistoryCard(
            title: _eventTitle(event.stage, volunteer),
            body: _eventBody(event.stage, volunteer),
            time: _relativeTime(event.at),
            completed: event.stage == IncidentStage.resolved,
          ),
        )
        .toList();
  }

  String _eventTitle(IncidentStage stage, bool volunteer) => switch (stage) {
    IncidentStage.reported => 'تم استلام البلاغ',
    IncidentStage.waitingForResponder =>
      volunteer ? 'نداء حريق جديد' : 'جارٍ البحث عن مستجيب',
    IncidentStage.responderAccepted => 'تم قبول النداء',
    IncidentStage.responderEnRoute =>
      volunteer ? 'بدأت الاستجابة' : 'متطوع في الطريق',
    IncidentStage.resolved => 'تمت معالجة الحالة',
  };

  String _eventBody(IncidentStage stage, bool volunteer) => switch (stage) {
    IncidentStage.reported => 'تم تسجيل موقع الحريق وصورة البلاغ المتاحة.',
    IncidentStage.waitingForResponder =>
      volunteer
          ? 'حادث متاح ضمن منطقتك ويحتاج إلى مستجيب معتمد.'
          : 'تم إرسال النداء إلى المتطوعين المعتمدين القريبين.',
    IncidentStage.responderAccepted =>
      volunteer
          ? 'تم ربط استجابتك بالحادث.'
          : 'تم تسجيل استجابة متطوع معتمد للحادث.',
    IncidentStage.responderEnRoute =>
      volunteer
          ? 'المسار إلى موقع الحريق نشط.'
          : 'تم تحديث عدد المتطوعين المستجيبين للحادث.',
    IncidentStage.resolved => 'انتهى الحادث ولم يعد التنبيه نشطًا.',
  };

  String _relativeTime(DateTime time) {
    final minutes = DateTime.now().difference(time).inMinutes;
    if (minutes < 1) return 'الآن';
    if (minutes == 1) return 'منذ دقيقة';
    return 'منذ $minutes دقائق';
  }
}

class _CurrentIncidentCard extends StatelessWidget {
  const _CurrentIncidentCard({
    required this.incident,
    required this.volunteer,
    required this.isReporter,
    required this.viewerId,
    required this.onTap,
  });
  final FireIncident incident;
  final bool volunteer;
  final bool isReporter;
  final String viewerId;
  final VoidCallback onTap;

  bool get _hasResponded => incident.hasResponded(viewerId);

  @override
  Widget build(BuildContext context) {
    final urgent =
        volunteer || (!isReporter && !incident.nearbyCitizenAcknowledged);
    final title = volunteer
        ? _hasResponded
              ? 'الاستجابة نشطة الآن'
              : 'نداء حريق جديد'
        : isReporter
        ? incident.responderCount > 0
              ? 'استجاب ${incident.responderCount} من المتطوعين'
              : 'بلاغك قيد الاستجابة'
        : incident.nearbyCitizenAcknowledged
        ? 'حريق قريب · تم إيقاف التنبيه'
        : 'حادث نشط الآن';
    return SurfaceCard(
      warning: urgent,
      padding: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '🔥 $title',
            style: AppType.text(
              17,
              weight: FontWeight.w700,
              color: urgent ? AppColors.emergency : AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            volunteer
                ? _hasResponded
                      ? 'مسارك إلى الحادث وتفاصيل المبلّغ متاحة الآن.'
                      : 'الحادث متاح للاستجابة حتى مع استجابة متطوعين آخرين.'
                : isReporter
                ? 'افتح الحالة لمتابعة البلاغ وعدد المستجيبين.'
                : 'ابتعد عن منطقة الخطر وافتح الخريطة لمتابعة الحالة.',
            style: AppType.text(12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'الآن',
                style: AppType.text(11, color: AppColors.textSecondary),
              ),
              const Spacer(),
              SizedBox(
                width: 138,
                height: 36,
                child: FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: urgent
                        ? AppColors.emergency
                        : AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: Text(
                    volunteer ? 'عرض الحادث' : 'عرض على الخريطة',
                    style: AppType.text(
                      12,
                      weight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.title,
    required this.body,
    required this.time,
    required this.completed,
  });
  final String title;
  final String body;
  final String time;
  final bool completed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SurfaceCard(
      padding: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppType.text(
              15,
              weight: FontWeight.w700,
              color: completed
                  ? AppColors.textSecondary
                  : AppColors.textPrimary,
            ),
          ),
          Text(body, style: AppType.text(12, color: AppColors.textSecondary)),
          Text(time, style: AppType.text(10, color: const Color(0xFF92A19E))),
        ],
      ),
    ),
  );
}

class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts();

  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: 18,
    child: Text(
      'لا توجد تنبيهات أو حوادث مسجلة في هذه الجلسة.',
      textAlign: TextAlign.center,
      style: AppType.caption,
    ),
  );
}
