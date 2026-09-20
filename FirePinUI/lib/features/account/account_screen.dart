import 'package:flutter/material.dart';

import '../../core/ui/components.dart';
import '../../theme/app_theme.dart';
import '../incidents/incident_controller.dart';
import '../onboarding/onboarding_models.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.session,
    required this.incidentController,
    required this.onChangePin,
    required this.onLogout,
    this.onApplyVolunteer,
  });

  final OnboardingSession session;
  final IncidentController incidentController;
  final VoidCallback onChangePin;
  final VoidCallback onLogout;
  final VoidCallback? onApplyVolunteer;

  @override
  Widget build(BuildContext context) {
    final identity = session.identity;
    final approvedVolunteer =
        session.role == UsageRole.volunteer &&
        session.applicationStatus != ApplicationStatus.pending &&
        session.applicationStatus != ApplicationStatus.rejected;
    final name = identity?.fullName ?? 'رمزي أبو فلاح';
    final initial = name.trim().isEmpty ? 'ر' : name.trim().characters.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageTitle('الحساب'),
        const SizedBox(height: 8),
        if ((session.applicationStatus == ApplicationStatus.none ||
                session.applicationStatus == ApplicationStatus.rejected) &&
            onApplyVolunteer != null) ...[
          AppButton(
            session.applicationStatus == ApplicationStatus.rejected
                ? 'إعادة التقديم كمتطوع'
                : 'التقديم كمتطوع',
            onPressed: onApplyVolunteer,
          ),
          const SizedBox(height: 8),
        ],
        SurfaceCard(
          child: Row(
            children: [
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: AppType.text(26, weight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppType.text(20, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFFC9DEDA)),
                      ),
                      child: Text(
                        approvedVolunteer ? '✓ متطوع معتمد' : '✓ حساب موثّق',
                        style: AppType.text(
                          12,
                          weight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Text(
                      'نوع الحساب: ${approvedVolunteer
                          ? 'متطوع معتمد'
                          : session.applicationStatus == ApplicationStatus.pending
                          ? 'طلب تطوع قيد المراجعة'
                          : session.applicationStatus == ApplicationStatus.rejected
                          ? 'طلب التطوع مرفوض'
                          : 'مواطن'}',
                      style: AppType.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (approvedVolunteer) ...[
          Text('حالة التطوع', style: AppType.section),
          const SizedBox(height: 4),
          SurfaceCard(
            padding: 14,
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.volunteer_activism_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _volunteerStatus,
                        style: AppType.text(14, weight: FontWeight.w700),
                      ),
                      Text(
                        'نطاق الاستجابة: ${identity?.address ?? 'القدس — الطور'}',
                        style: AppType.text(11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text('البيانات الشخصية', style: AppType.section),
        const SizedBox(height: 4),
        SurfaceCard(
          padding: 14,
          child: Column(
            children: [
              _DetailsRow(
                firstLabel: 'رقم الهوية',
                firstValue: _maskedIdentity(identity?.identityNumber),
                secondLabel: 'رقم الهاتف',
                secondValue: session.phone.isEmpty
                    ? '059 123 4567'
                    : session.phone,
              ),
              const SizedBox(height: 12),
              _DetailsRow(
                firstLabel: 'العنوان',
                firstValue: identity?.address ?? 'القدس — الطور',
                secondLabel: 'تاريخ الميلاد',
                secondValue: identity?.birthDate ?? '14 / 05 / 1998',
              ),
              const SizedBox(height: 10),
              Text(
                'البيانات المستخرجة من الهوية غير قابلة للتعديل مباشرة.',
                style: AppType.text(11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('الحالة والأذونات', style: AppType.section),
        const SizedBox(height: 4),
        SurfaceCard(
          padding: 12,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      approvedVolunteer
                          ? 'استخدام التطبيق كمتطوع'
                          : 'استخدام التطبيق كمواطن',
                      style: AppType.text(14, weight: FontWeight.w700),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      approvedVolunteer ? 'متطوع معتمد' : 'التقديم كمتطوع',
                      style: AppType.text(11, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              const Divider(color: AppColors.outline),
              Text(
                'الموقع ✓   الإشعارات ✓   الكاميرا ✓',
                style: AppType.text(12, color: AppColors.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SurfaceCard(
          padding: 10,
          child: Row(
            children: [
              Expanded(
                child: _AccountAction(
                  label: 'تسجيل الخروج',
                  color: AppColors.emergency,
                  onTap: onLogout,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AccountAction(
                  label: 'تغيير رمز الدخول',
                  color: AppColors.primary,
                  onTap: onChangePin,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _maskedIdentity(String? value) {
    if (value == null || value.length < 2) return '*******89';
    return '${List.filled(value.length - 2, '*').join()}${value.substring(value.length - 2)}';
  }

  String get _volunteerStatus {
    if (incidentController.incident?.hasResponded(session.participantId) ==
        true) {
      return 'استجابة نشطة · أنت في الطريق';
    }
    return 'متاح لاستقبال نداءات الحريق';
  }
}

class _DetailsRow extends StatelessWidget {
  const _DetailsRow({
    required this.firstLabel,
    required this.firstValue,
    required this.secondLabel,
    required this.secondValue,
  });
  final String firstLabel;
  final String firstValue;
  final String secondLabel;
  final String secondValue;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _Detail(label: firstLabel, value: firstValue),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: _Detail(label: secondLabel, value: secondValue),
      ),
    ],
  );
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppType.text(11, color: AppColors.textSecondary)),
      Text(value, style: AppType.text(13, weight: FontWeight.w700)),
    ],
  );
}

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withValues(alpha: 0.25)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    child: Text(
      label,
      style: AppType.text(12, weight: FontWeight.w700, color: color),
    ),
  );
}
