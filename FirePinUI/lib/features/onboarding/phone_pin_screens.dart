import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/ui/components.dart';
import '../../core/ui/digit_input.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';
import 'onboarding_models.dart';

/// Figma 109:48.
class PhoneNumberScreen extends StatefulWidget {
  const PhoneNumberScreen({super.key, required this.onContinue, this.onBack});
  final ValueChanged<String> onContinue;
  final VoidCallback? onBack;
  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  final _phone = TextEditingController();
  String? _error;
  int _shake = 0;
  void _submit() {
    if (!isValidPhone(_phone.text)) {
      setState(() {
        _error = 'أدخل رقمًا صحيحًا مثل 0591234567 أو رقمًا مع رمز الدولة.';
        _shake++;
      });
      return;
    }
    final phone = normalizePhone(_phone.text);
    FocusScope.of(context).unfocus();
    widget.onContinue(phone);
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnboardingPage(
    onBack: widget.onBack,
    children: [
      const SizedBox(height: 34),
      const IllustrationBadge('phone'),
      const SizedBox(height: 28),
      const PageTitle('أدخل رقم هاتفك'),
      const SizedBox(height: 6),
      const CopyBlock(
        'سنستخدم هذا الرقم للتواصل معك وربطه بحسابك.',
        minHeight: 56,
      ),
      const SizedBox(height: 36),
      Text(
        'رقم الهاتف',
        style: AppType.text(15, weight: FontWeight.w500, height: 28),
      ),
      const SizedBox(height: 6),
      Shake(
        trigger: _shake,
        child: TextField(
          key: const ValueKey('phone-number'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
          autofillHints: const [AutofillHints.telephoneNumber],
          style: AppType.text(15),
          decoration: const InputDecoration(
            hintText: '05X XXX XXXX',
            constraints: BoxConstraints(minHeight: 58),
          ),
          inputFormatters: [
            TextInputFormatter.withFunction(
              (oldValue, newValue) =>
                  newValue.copyWith(text: normalizeDigits(newValue.text)),
            ),
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')),
            LengthLimitingTextInputFormatter(20),
          ],
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      ),
      InlineMessage(_error),
      SizedBox(height: MediaQuery.viewInsetsOf(context).bottom > 0 ? 28 : 216),
      AppButton('متابعة', onPressed: _submit),
    ],
  );
}

/// Figma 110:2. PIN values exist in memory only and are never logged.
class PinScreen extends StatefulWidget {
  const PinScreen({
    super.key,
    required this.session,
    required this.onContinue,
    this.onBack,
  });
  final OnboardingSession session;
  final VoidCallback onContinue;
  final VoidCallback? onBack;
  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  final _confirmationFocus = FocusNode();
  String? _error;
  int _shake = 0;
  void _save() {
    final result = confirmPin(_pin.text, _confirmation.text);
    if (result != PinConfirmation.confirmed) {
      setState(() {
        _error = result == PinConfirmation.incomplete
            ? 'أكمل رمز الدخول وتأكيده، 4 أرقام لكل منهما.'
            : 'الرمزان غير متطابقين. أعد إدخال رمز التأكيد.';
        _shake++;
      });
      if (result == PinConfirmation.mismatch) _confirmation.clear();
      _confirmationFocus.requestFocus();
      return;
    }
    widget.session.savePin(_pin.text, _confirmation.text);
    _pin.clear();
    _confirmation.clear();
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    widget.onContinue();
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirmation.dispose();
    _confirmationFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnboardingPage(
    onBack: widget.onBack,
    children: [
      const SizedBox(height: 42),
      const PageTitle('أنشئ رمز الدخول'),
      const SizedBox(height: 6),
      const CopyBlock(
        'اختر رمزًا شخصيًا من 4 أرقام، ثم أعد إدخاله للتأكيد.',
        minHeight: 58,
      ),
      const SizedBox(height: 24),
      Text(
        'رمز الدخول',
        style: AppType.text(15, weight: FontWeight.w500, height: 28),
      ),
      const SizedBox(height: 8),
      DigitInput(
        controller: _pin,
        label: 'رمز الدخول',
        length: 4,
        obscure: true,
        onComplete: (_) => _confirmationFocus.requestFocus(),
      ),
      const SizedBox(height: 30),
      Text(
        'تأكيد رمز الدخول',
        style: AppType.text(15, weight: FontWeight.w500, height: 28),
      ),
      const SizedBox(height: 8),
      Shake(
        trigger: _shake,
        child: DigitInput(
          controller: _confirmation,
          label: 'تأكيد رمز الدخول',
          focusNode: _confirmationFocus,
          length: 4,
          obscure: true,
        ),
      ),
      InlineMessage(_error),
      const SizedBox(height: 36),
      SurfaceCard(
        warning: true,
        radius: 16,
        padding: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تنبيه مهم',
              style: AppType.text(
                17,
                weight: FontWeight.w700,
                color: AppColors.warning,
                height: 30,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'احفظ رمز الدخول جيدًا. ستحتاج إليه للدخول إلى حسابك لاحقًا، ولا تشاركه مع أي شخص.',
              style: AppType.text(14, weight: FontWeight.w500, height: 26),
            ),
          ],
        ),
      ),
      SizedBox(height: MediaQuery.viewInsetsOf(context).bottom > 0 ? 28 : 68),
      AppButton('حفظ رمز الدخول', onPressed: _save),
    ],
  );
}
