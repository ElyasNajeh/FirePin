import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/ui/components.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';
import 'onboarding_models.dart';
import 'onboarding_services.dart';

/// Figma 110:25 and 110:42 are states of this one screen.
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({
    super.key,
    required this.onContinue,
    this.initialRole = UsageRole.citizen,
  });
  final ValueChanged<UsageRole> onContinue;
  final UsageRole initialRole;
  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  late UsageRole _role = widget.initialRole;
  void _select(UsageRole role) {
    if (_role == role) return;
    HapticFeedback.selectionClick();
    setState(() => _role = role);
  }

  @override
  Widget build(BuildContext context) => OnboardingPage(
    children: [
      const SizedBox(height: 44),
      const PageTitle('كيف تريد استخدام التطبيق؟', size: 25),
      const SizedBox(height: 8),
      CopyBlock(
        'اختر طريقة المتابعة. يمكنك تقديم طلب تطوع لاحقًا أيضًا.',
        minHeight: 58,
        style: AppType.text(15, color: AppColors.textSecondary, height: 29),
      ),
      const SizedBox(height: 30),
      _RoleCard(
        selected: _role == UsageRole.citizen,
        title: 'استخدام التطبيق كمواطن',
        description: 'الإبلاغ عن الحرائق واستقبال التنبيهات القريبة.',
        onTap: () => _select(UsageRole.citizen),
      ),
      const SizedBox(height: 20),
      _RoleCard(
        selected: _role == UsageRole.volunteer,
        title: 'تقديم طلب للانضمام كمتطوع',
        description: 'يتطلب مراجعة وموافقة المجلس المسؤول عن منطقتك.',
        onTap: () => _select(UsageRole.volunteer),
      ),
      const SizedBox(height: 144),
      AppButton('متابعة', onPressed: () => widget.onContinue(_role)),
    ],
  );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.selected,
    required this.title,
    required this.description,
    required this.onTap,
  });
  final bool selected;
  final String title;
  final String description;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    checked: selected,
    inMutuallyExclusiveGroup: true,
    button: true,
    child: AnimatedContainer(
      duration: AppMotion.reduced(context)
          ? Duration.zero
          : AppMotion.selection,
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 138),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryContainer : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.outline,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: Stack(
                      children: [
                        FigmaIcon(
                          selected ? 'radio_selected' : 'radio_empty',
                          size: 22,
                        ),
                        Center(
                          child: AnimatedScale(
                            scale: selected ? 1 : 0,
                            duration: AppMotion.reduced(context)
                                ? Duration.zero
                                : AppMotion.selection,
                            curve: Curves.easeOutBack,
                            child: const FigmaIcon('radio_dot', size: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title, style: AppType.section),
                      const SizedBox(height: 12),
                      Text(
                        description,
                        style: AppType.text(
                          14,
                          color: AppColors.textSecondary,
                          height: 26,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Figma 110:59.
class VolunteerWarningScreen extends StatefulWidget {
  const VolunteerWarningScreen({
    super.key,
    required this.service,
    required this.onSubmitted,
    required this.onBack,
  });
  final VolunteerApplicationService service;
  final ValueChanged<ApplicationStatus> onSubmitted;
  final VoidCallback onBack;
  @override
  State<VolunteerWarningScreen> createState() => _VolunteerWarningScreenState();
}

class _VolunteerWarningScreenState extends State<VolunteerWarningScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await widget.service.submit();
      if (mounted) widget.onSubmitted(status);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر إرسال الطلب. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: OnboardingPage(
      children: [
        const SizedBox(height: 36),
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: FigmaIcon('warning', size: 84),
        ),
        const SizedBox(height: 28),
        const PageTitle('تنبيه مهم', color: AppColors.warning),
        const SizedBox(height: 14),
        SurfaceCard(
          warning: true,
          padding: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 26),
              Text(
                'عند تقديم طلب الانضمام كمتطوع، لن يتم تفعيل حسابك حتى تتم مراجعة الطلب والموافقة عليه من المجلس المسؤول عن منطقتك.',
                style: AppType.text(15, weight: FontWeight.w500, height: 28),
              ),
              const SizedBox(height: 50),
              Text(
                'قد يبقى حسابك في حالة قيد المراجعة إلى حين صدور القرار.',
                style: AppType.text(15, weight: FontWeight.w500, height: 28),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
        InlineMessage(_error),
        const SizedBox(height: 82),
        AppButton(
          _busy ? 'جارٍ إرسال الطلب' : 'تأكيد وإرسال طلب التطوع',
          busy: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: 12),
        AppButton(
          'العودة',
          secondary: true,
          onPressed: _busy ? null : widget.onBack,
        ),
      ],
    ),
  );
}

/// Figma 110:74. The route stack is cleared on entry; no Home access.
class VolunteerPendingScreen extends StatelessWidget {
  const VolunteerPendingScreen({super.key});
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: OnboardingPage(
      children: [
        const SizedBox(height: 74),
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: FigmaIcon('pending', size: 112),
        ),
        const SizedBox(height: 48),
        const PageTitle('طلبك قيد المراجعة'),
        const SizedBox(height: 18),
        Text(
          'تم إرسال طلبك إلى المجلس المسؤول.',
          style: AppType.text(16, weight: FontWeight.w500, height: 40),
        ),
        const SizedBox(height: 4),
        const CopyBlock(
          'سيتم تفعيل حسابك بعد الموافقة على الطلب.',
          minHeight: 64,
        ),
        const SizedBox(height: 46),
        Container(
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Breathe(
            scale: 1,
            opacity: 0.7,
            child: Text(
              'قيد المراجعة',
              style: AppType.text(
                18,
                color: AppColors.primary,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
