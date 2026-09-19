import 'package:flutter/material.dart';
import '../../core/ui/components.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';

/// Figma 5:8.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onStart,
    this.onLogin,
    this.onMunicipalityLogin,
  });
  final VoidCallback onStart;
  final VoidCallback? onLogin;
  final VoidCallback? onMunicipalityLogin;
  @override
  Widget build(BuildContext context) => OnboardingPage(
    children: [
      const SizedBox(height: 30),
      const Reveal(
        child: IllustrationBadge(
          'verified_shield',
          size: 68,
          iconSize: 36,
          radius: 18,
        ),
      ),
      const SizedBox(height: 20),
      Text('إنشاء حساب موثّق', style: AppType.title),
      const SizedBox(height: 8),
      Text(
        'تسجيل رسمي وآمن. جهّز المتطلبات التالية للبدء.',
        style: AppType.body,
      ),
      const SizedBox(height: 38),
      SurfaceCard(
        radius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('قبل أن تبدأ', style: AppType.section),
            for (final label in [
              'بطاقة هوية سارية',
              'رقم هاتف فعّال',
              'تفعيل الموقع أثناء الاستخدام',
              'أن تكون فوق السن المعتمد',
            ]) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Row(
                  children: [
                    const FigmaIcon('requirement_dot', size: 10),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: AppType.text(
                          16,
                          weight: FontWeight.w500,
                          height: 27,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 40),
      AppButton('إنشاء حساب جديد', onPressed: onStart),
      const SizedBox(height: 10),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('لدي حساب بالفعل —', style: AppType.muted),
          TextButton(
            onPressed:
                onLogin ??
                () => showFeedback(context, 'تسجيل الدخول سيتوفر قريبًا.'),
            child: Text(
              'تسجيل الدخول',
              style: AppType.text(
                15,
                color: AppColors.primary,
                weight: FontWeight.w700,
                height: 25,
              ).copyWith(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      AppButton(
        'دخول الجهة المسؤولة',
        secondary: true,
        minHeight: 44,
        fontSize: 15,
        onPressed:
            onMunicipalityLogin ??
            () => showFeedback(context, 'دخول الجهة المسؤولة سيتوفر قريبًا.'),
      ),
    ],
  );
}
