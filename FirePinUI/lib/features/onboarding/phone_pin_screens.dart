import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/ui/components.dart';
import '../../core/ui/digit_input.dart';
import '../../core/ui/motion.dart';
import '../../theme/app_theme.dart';
import 'onboarding_models.dart';
import 'onboarding_services.dart';

/// Figma 109:48.
class PhoneNumberScreen extends StatefulWidget {
  const PhoneNumberScreen({super.key, required this.otp, required this.onSent});
  final OtpService otp;
  final ValueChanged<String> onSent;
  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;
  int _shake = 0;
  Future<void> _submit() async {
    if (_busy) return;
    if (!isValidPhone(_phone.text)) {
      setState(() {
        _error = 'أدخل رقمًا صحيحًا مثل 0591234567 أو رقمًا مع رمز الدولة.';
        _shake++;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final phone = normalizePhone(_phone.text);
    try {
      await widget.otp.send(phone);
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      widget.onSent(phone);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر إرسال الرمز. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnboardingPage(
    children: [
      const SizedBox(height: 34),
      const IllustrationBadge('phone'),
      const SizedBox(height: 28),
      const PageTitle('أدخل رقم هاتفك'),
      const SizedBox(height: 6),
      const CopyBlock(
        'سنرسل رمز تحقق عبر رسالة SMS إلى هذا الرقم.',
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
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.send,
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
      AppButton(
        _busy ? 'جارٍ إرسال الرمز' : 'إرسال رمز التحقق',
        onPressed: _submit,
        busy: _busy,
      ),
    ],
  );
}

/// Figma 109:63. One input drives six tappable visual cells.
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.otp,
    required this.phone,
    required this.onVerified,
  });
  final OtpService otp;
  final String phone;
  final VoidCallback onVerified;
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  int _shake = 0;
  Future<void> _verify() async {
    if (_busy) return;
    if (_code.text.length != 6) {
      setState(() {
        _error = 'أدخل الرمز المكوّن من 6 أرقام.';
        _shake++;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final accepted = await widget.otp.verify(widget.phone, _code.text);
      if (!mounted) return;
      if (accepted) {
        FocusScope.of(context).unfocus();
        HapticFeedback.lightImpact();
        widget.onVerified();
      } else {
        setState(() {
          _error = 'الرمز غير صحيح. تحقق منه وحاول مجددًا.';
          _shake++;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر التحقق الآن. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.otp.send(widget.phone);
      if (!mounted) return;
      _code.clear();
      showFeedback(context, 'تمت إعادة إرسال الرمز.');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذّرت إعادة الإرسال. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnboardingPage(
    children: [
      const SizedBox(height: 56),
      const PageTitle('أدخل رمز التحقق'),
      const SizedBox(height: 8),
      const CopyBlock('أرسلنا رمزًا من 6 أرقام إلى الرقم:', minHeight: 34),
      const SizedBox(height: 10),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          width: 190,
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Text(
            widget.phone,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: AppType.text(
              15,
              weight: FontWeight.w500,
              color: AppColors.primary,
              height: 28,
            ),
          ),
        ),
      ),
      const SizedBox(height: 64),
      Shake(
        trigger: _shake,
        child: DigitInput(
          controller: _code,
          label: 'رمز التحقق',
          length: 6,
          enabled: !_busy,
        ),
      ),
      InlineMessage(_error),
      SizedBox(height: MediaQuery.viewInsetsOf(context).bottom > 0 ? 28 : 132),
      AppButton(
        _busy ? 'جارٍ التحقق' : 'تحقق',
        busy: _busy,
        onPressed: _verify,
      ),
      const SizedBox(height: 16),
      TextButton(
        onPressed: _busy ? null : _resend,
        child: Text(
          'إعادة إرسال الرمز',
          style: AppType.text(
            15,
            color: AppColors.primary,
            weight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

/// Figma 109:81.
class PhoneSuccessScreen extends StatelessWidget {
  const PhoneSuccessScreen({super.key, required this.onContinue});
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) => OnboardingPage(
    children: [
      const SizedBox(height: 96),
      const Reveal(scale: true, child: IllustrationBadge('phone_success')),
      const SizedBox(height: 46),
      Reveal(
        delay: const Duration(milliseconds: 100),
        child: Semantics(
          liveRegion: true,
          child: const PageTitle(
            'تم التحقق من رقم الهاتف',
            size: 26,
            align: TextAlign.center,
          ),
        ),
      ),
      const SizedBox(height: 12),
      const CopyBlock(
        'أصبح رقم هاتفك مرتبطًا بحسابك الموثّق.',
        minHeight: 58,
        center: true,
      ),
      const SizedBox(height: 176),
      AppButton('متابعة', onPressed: onContinue),
    ],
  );
}

/// Figma 110:2. PIN values exist in memory only and are never logged.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.session, required this.onContinue});
  final OnboardingSession session;
  final VoidCallback onContinue;
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
