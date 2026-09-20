import 'package:flutter/material.dart';

import '../../core/ui/components.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';
import 'incident_controller.dart';

enum IncidentPerspective { reporter, nearbyCitizen, volunteer }

class IncidentScreen extends StatelessWidget {
  const IncidentScreen({
    super.key,
    required this.incident,
    required this.perspective,
    required this.controller,
    required this.viewerId,
    required this.onViewPhoto,
    required this.onContactReporter,
    this.volunteerDisplayName,
    this.volunteerPhone,
  });

  final FireIncident incident;
  final IncidentPerspective perspective;
  final IncidentController controller;
  final String viewerId;
  final VoidCallback onViewPhoto;
  final VoidCallback onContactReporter;
  final String? volunteerDisplayName;
  final String? volunteerPhone;

  bool get _isResolved => incident.stage == IncidentStage.resolved;

  @override
  Widget build(BuildContext context) {
    final nearbyWarning =
        perspective == IncidentPerspective.nearbyCitizen &&
        !incident.nearbyCitizenAcknowledged &&
        !_isResolved;
    return AnimatedContainer(
      duration: AppMotion.reduced(context)
          ? Duration.zero
          : AppMotion.selection,
      padding: nearbyWarning ? const EdgeInsets.all(6) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: nearbyWarning
            ? AppColors.emergency.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IncidentMap(
            incident: incident,
            perspective: perspective,
            viewerId: viewerId,
          ),
          const SizedBox(height: 18),
          _StatusCard(
            incident: incident,
            perspective: perspective,
            controller: controller,
            viewerId: viewerId,
            onViewPhoto: onViewPhoto,
            onContactReporter: onContactReporter,
            volunteerDisplayName: volunteerDisplayName,
            volunteerPhone: volunteerPhone,
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.incident,
    required this.perspective,
    required this.controller,
    required this.viewerId,
    required this.onViewPhoto,
    required this.onContactReporter,
    this.volunteerDisplayName,
    this.volunteerPhone,
  });

  final FireIncident incident;
  final IncidentPerspective perspective;
  final IncidentController controller;
  final String viewerId;
  final VoidCallback onViewPhoto;
  final VoidCallback onContactReporter;
  final String? volunteerDisplayName;
  final String? volunteerPhone;

  bool get _hasResponded => incident.hasResponded(viewerId);
  bool get _hasResponders => incident.responderCount > 0;
  bool get _isResolved => incident.stage == IncidentStage.resolved;

  @override
  Widget build(BuildContext context) {
    final urgent =
        perspective == IncidentPerspective.nearbyCitizen &&
        !incident.nearbyCitizenAcknowledged &&
        !_isResolved;
    return SurfaceCard(
      padding: 16,
      shadow: true,
      warning: urgent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _title,
                  style: AppType.text(
                    17,
                    weight: FontWeight.w700,
                    color: urgent ? AppColors.emergency : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(label: _statusLabel, urgent: urgent),
            ],
          ),
          const SizedBox(height: 4),
          Text(_body, style: AppType.text(12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          ..._actions,
        ],
      ),
    );
  }

  String get _title {
    if (_isResolved) return 'تمت معالجة الحالة';
    return switch (perspective) {
      IncidentPerspective.reporter =>
        _hasResponders
            ? 'استجاب ${incident.responderCount} من المتطوعين'
            : 'تم استلام البلاغ',
      IncidentPerspective.nearbyCitizen =>
        incident.nearbyCitizenAcknowledged
            ? 'تم إيقاف التنبيه'
            : 'تنبيه حريق قريب',
      IncidentPerspective.volunteer =>
        _hasResponded ? 'أنت تستجيب لهذا البلاغ' : 'نداء حريق جديد',
    };
  }

  String get _statusLabel {
    if (_isResolved) return 'منتهية';
    if (perspective == IncidentPerspective.reporter && _hasResponders) {
      return '${incident.responderCount} مستجيبين';
    }
    if (perspective == IncidentPerspective.volunteer && _hasResponded) {
      return 'استجابة نشطة';
    }
    return perspective == IncidentPerspective.nearbyCitizen
        ? incident.nearbyCitizenAcknowledged
              ? 'تم الاطلاع'
              : 'تحذير سلامة'
        : 'جارٍ البحث';
  }

  String get _body {
    if (_isResolved) {
      return 'تم إنهاء الحادث ولم يعد التنبيه نشطًا. يبقى سجل الحالة محفوظًا في التنبيهات.';
    }
    return switch (perspective) {
      IncidentPerspective.reporter =>
        _hasResponders
            ? 'تم تسجيل استجابات المتطوعين. سيبقى البلاغ نشطًا حتى تتم معالجة الحالة.'
            : 'تم تثبيت موقع الحريق، وجارٍ الآن البحث عن أقرب مستجيب معتمد.',
      IncidentPerspective.nearbyCitizen =>
        incident.nearbyCitizenAcknowledged
            ? 'سيبقى موقع الحريق ظاهرًا حتى انتهاء الحالة. حافظ على مسافة آمنة.'
            : 'ابتعد عن منطقة الخطر ولا تقترب من موقع الحريق، واتبع إرشادات السلامة.',
      IncidentPerspective.volunteer =>
        _hasResponded
            ? 'الاستجابة نشطة · أنت في الطريق. اتبع المسار الظاهر بأسرع طريقة آمنة.'
            : 'راجع موقع الحادث والتفاصيل قبل تلبية النداء.',
    };
  }

  List<Widget> get _actions {
    if (_isResolved) {
      return [
        _ActionButton(
          label: 'العودة للرئيسية',
          primary: true,
          onTap: controller.dismissResolved,
        ),
      ];
    }
    if (perspective == IncidentPerspective.reporter) {
      return [
        _ActionButton(
          label: incident.photo == null
              ? 'تفاصيل صورة البلاغ'
              : 'رؤية الصورة المرسلة',
          onTap: onViewPhoto,
        ),
      ];
    }
    if (perspective == IncidentPerspective.nearbyCitizen) {
      if (incident.nearbyCitizenAcknowledged) {
        return [
          _ActionButton(
            label: incident.photo == null
                ? 'لا توجد صورة للبلاغ'
                : 'رؤية الصورة المرسلة',
            onTap: onViewPhoto,
          ),
        ];
      }
      return [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'رؤية الصورة المرسلة',
                onTap: onViewPhoto,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'تم الاطلاع',
                primary: true,
                onTap: controller.acknowledgeNearbyAlert,
              ),
            ),
          ],
        ),
      ];
    }
    if (!_hasResponded) {
      return [
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'رؤية الصورة المرسلة',
                onTap: onViewPhoto,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'اتصال بالمبلّغ',
                onTap: onContactReporter,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ActionButton(
          label: 'تلبية النداء',
          primary: true,
          onTap: () => controller.acceptByVolunteer(
            volunteerId: viewerId,
            displayName: volunteerDisplayName,
            phone: volunteerPhone,
          ),
        ),
        const SizedBox(height: 6),
        _ActionButton(
          label: 'تعذّر عليّ الاستجابة',
          danger: true,
          onTap: () => controller.declineForVolunteer(
            volunteerId: viewerId,
            displayName: volunteerDisplayName,
            phone: volunteerPhone,
          ),
        ),
      ];
    }
    return [
      Row(
        children: [
          Expanded(
            child: _ActionButton(
              label: 'رؤية الصورة المرسلة',
              onTap: onViewPhoto,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              label: 'اتصال بالمبلّغ',
              onTap: onContactReporter,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _ActionButton(
        label: 'الاستجابة نشطة · أنا في الطريق',
        primary: true,
        onTap: () {},
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: _ActionButton(
              label: 'إلغاء استجابتي',
              danger: true,
              onTap: () => controller.withdrawVolunteerResponse(viewerId),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              label: 'تمت معالجة الحالة',
              onTap: () => controller.resolveByVolunteer(viewerId),
            ),
          ),
        ],
      ),
    ];
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.urgent});
  final String label;
  final bool urgent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: urgent
          ? AppColors.emergency.withValues(alpha: 0.10)
          : AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      label,
      style: AppType.text(
        10,
        weight: FontWeight.w700,
        color: urgent ? AppColors.emergency : AppColors.primary,
      ),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.emergency : AppColors.primary;
    return SizedBox(
      height: 38,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          backgroundColor: primary
              ? color
              : danger
              ? const Color(0xFFFFF3F1)
              : AppColors.primaryContainer,
          foregroundColor: primary ? Colors.white : color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: danger
                ? BorderSide(color: color.withValues(alpha: 0.25))
                : BorderSide.none,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: AppType.text(
              11,
              weight: FontWeight.w700,
              color: primary ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}

class IncidentMap extends StatelessWidget {
  const IncidentMap({
    super.key,
    required this.incident,
    required this.perspective,
    required this.viewerId,
  });

  final FireIncident incident;
  final IncidentPerspective perspective;
  final String viewerId;

  bool get _showRoute =>
      perspective == IncidentPerspective.volunteer &&
      incident.hasResponded(viewerId);
  bool get _showPerson =>
      perspective == IncidentPerspective.nearbyCitizen || _showRoute;

  @override
  Widget build(BuildContext context) => Container(
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
          builder: (context, constraints) {
            final scale = constraints.maxWidth / 350;
            const fireLeft = 222.0;
            const fireTop = 76.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                const FigmaIcon(
                  'basemap',
                  width: 350,
                  height: 404,
                  fit: BoxFit.fill,
                ),
                if (_showRoute)
                  CustomPaint(
                    key: ValueKey('volunteer-route-$viewerId'),
                    painter: const VolunteerRoutePainter(),
                  ),
                if (_showPerson)
                  Positioned(
                    left: 47 * scale,
                    top: 260 * scale,
                    width: 80 * scale,
                    height: 80 * scale,
                    child: Breathe(
                      scale: 1.04,
                      opacity: 0.72,
                      child: const FigmaIcon('location_halo', size: 80),
                    ),
                  ),
                if (_showPerson)
                  Positioned(
                    key: perspective == IncidentPerspective.volunteer
                        ? ValueKey('volunteer-location-$viewerId')
                        : null,
                    left: 70 * scale,
                    top: 283 * scale,
                    width: 34 * scale,
                    height: 34 * scale,
                    child: const FigmaIcon('location_marker', size: 34),
                  ),
                Positioned(
                  left: fireLeft * scale,
                  top: fireTop * scale,
                  width: 98 * scale,
                  height: 98 * scale,
                  child: Breathe(
                    scale: incident.isResolved ? 1 : 1.04,
                    opacity: incident.isResolved ? 1 : 0.72,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.emergency.withValues(
                          alpha: incident.isResolved ? 0.05 : 0.10,
                        ),
                        border: Border.all(
                          color: AppColors.emergency.withValues(
                            alpha: incident.isResolved ? 0.18 : 0.38,
                          ),
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 50 * scale,
                        height: 50 * scale,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: incident.isResolved
                              ? AppColors.textSecondary
                              : AppColors.emergency,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: incident.isResolved
                            ? Icon(
                                Icons.check_rounded,
                                size: 25 * scale,
                                color: Colors.white,
                              )
                            : Icon(
                                Icons.local_fire_department_rounded,
                                size: 27 * scale,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 15 * scale,
                  left: 15 * scale,
                  child: _MapChip(label: _roleLabel, tinted: true),
                ),
                Positioned(
                  top: 15 * scale,
                  right: 16 * scale,
                  child: _MapChip(
                    label: incident.isResolved ? 'منتهية' : 'مباشر',
                    live: !incident.isResolved,
                  ),
                ),
                Positioned(
                  top: (fireTop + 101) * scale,
                  left: (fireLeft - 4) * scale,
                  child: _MapChip(
                    label: incident.isResolved ? 'تمت المعالجة' : 'موقع الحريق',
                    danger: !incident.isResolved,
                  ),
                ),
                if (_showPerson)
                  Positioned(
                    left: 31 * scale,
                    top: 340 * scale,
                    child: _MapChip(label: 'موقعك الحالي'),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );

  String get _roleLabel => switch (perspective) {
    IncidentPerspective.reporter => 'من جهة المُبلّغ',
    IncidentPerspective.nearbyCitizen => 'من جهة المواطن القريب',
    IncidentPerspective.volunteer => 'من جهة المتطوع',
  };
}

class _MapChip extends StatelessWidget {
  const _MapChip({
    required this.label,
    this.tinted = false,
    this.danger = false,
    this.live = false,
  });
  final String label;
  final bool tinted;
  final bool danger;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 94, minHeight: 31),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: tinted ? AppColors.primaryContainer : Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: danger
            ? AppColors.emergency.withValues(alpha: 0.30)
            : AppColors.outline,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x171C332B),
          blurRadius: 7,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (live) ...[
          const FigmaIcon('live_dot', size: 8),
          const SizedBox(width: 7),
        ],
        Text(
          label,
          style: AppType.text(
            11,
            weight: FontWeight.w700,
            color: danger ? AppColors.emergency : AppColors.primary,
          ),
        ),
      ],
    ),
  );
}

class VolunteerRoutePainter extends CustomPainter {
  const VolunteerRoutePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final end = Offset(size.width * .77, size.height * .30);
    final path = Path()
      ..moveTo(size.width * .25, size.height * .75)
      ..lineTo(size.width * .36, size.height * .75)
      ..quadraticBezierTo(
        size.width * .41,
        size.height * .75,
        size.width * .41,
        size.height * .68,
      )
      ..lineTo(size.width * .41, size.height * .58)
      ..quadraticBezierTo(
        size.width * .41,
        size.height * .53,
        size.width * .48,
        size.height * .53,
      )
      ..lineTo(size.width * .56, size.height * .53)
      ..quadraticBezierTo(
        size.width * .63,
        size.height * .53,
        size.width * .63,
        size.height * .46,
      )
      ..lineTo(end.dx, end.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 11
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(VolunteerRoutePainter oldDelegate) => false;
}
