import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/components.dart';
import '../../theme/app_theme.dart';
import 'auth_controller.dart';
import 'auth_models.dart';

class UserLoginScreen extends StatefulWidget {
  const UserLoginScreen({
    super.key,
    required this.auth,
    required this.onBack,
    required this.onCreateAccount,
  });
  final AuthController auth;
  final VoidCallback onBack;
  final VoidCallback onCreateAccount;

  @override
  State<UserLoginScreen> createState() => _UserLoginScreenState();
}

class _UserLoginScreenState extends State<UserLoginScreen> {
  final _nationalId = TextEditingController();
  final _pin = TextEditingController();
  String? _nationalIdError;
  String? _pinError;
  String? _authError;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _nationalId.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final validId = isValidNationalId(_nationalId.text);
    final validPin = isValidLoginPin(_pin.text);
    setState(() {
      _nationalIdError = validId ? null : 'أدخل رقم هوية مكوّنًا من 9 أرقام.';
      _pinError = validPin ? null : 'أدخل رمز دخول مكوّنًا من 4 أرقام.';
      _authError = null;
    });
    if (!validId || !validPin) return;
    setState(() => _busy = true);
    try {
      await widget.auth.loginUser(_nationalId.text, _pin.text);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _authError = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IconButton(
                    tooltip: 'رجوع',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
                const BrandHeader(),
                const SizedBox(height: 36),
                const IllustrationBadge(
                  'verified_shield',
                  size: 68,
                  iconSize: 36,
                  radius: 18,
                ),
                const SizedBox(height: 18),
                Text('تسجيل الدخول', style: AppType.title),
                const SizedBox(height: 6),
                Text(
                  'ادخل إلى حسابك المواطن أو المتطوع بنفس البيانات.',
                  style: AppType.body,
                ),
                const SizedBox(height: 26),
                _AuthField(
                  key: const ValueKey('login-national-id'),
                  controller: _nationalId,
                  label: 'رقم الهوية',
                  hint: '9 أرقام',
                  error: _nationalIdError,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
                    LengthLimitingTextInputFormatter(9),
                  ],
                ),
                const SizedBox(height: 14),
                _AuthField(
                  key: const ValueKey('login-pin'),
                  controller: _pin,
                  label: 'رمز الدخول',
                  hint: '4 أرقام',
                  error: _pinError,
                  obscureText: _obscure,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
                    LengthLimitingTextInputFormatter(4),
                  ],
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'إظهار الرمز' : 'إخفاء الرمز',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                if (_authError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _authError!,
                    key: const ValueKey('user-login-error'),
                    style: AppType.text(13, color: AppColors.emergency),
                  ),
                ],
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => showFeedback(
                      context,
                      'استعادة رمز الدخول ستتوفر عند ربط خدمة الحسابات.',
                    ),
                    child: const Text('نسيت رمز الدخول؟'),
                  ),
                ),
                AppButton(
                  _busy ? 'جارٍ تسجيل الدخول...' : 'تسجيل الدخول',
                  onPressed: _busy ? null : _submit,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: widget.onCreateAccount,
                  child: const Text('إنشاء حساب جديد'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class MunicipalityLoginScreen extends StatefulWidget {
  const MunicipalityLoginScreen({
    super.key,
    required this.auth,
    required this.onBack,
  });
  final AuthController auth;
  final VoidCallback onBack;

  @override
  State<MunicipalityLoginScreen> createState() =>
      _MunicipalityLoginScreenState();
}

class _MunicipalityLoginScreenState extends State<MunicipalityLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;
  String? _authError;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final validEmail = isValidEmail(_email.text);
    final validPassword = _password.text.isNotEmpty;
    setState(() {
      _emailError = validEmail ? null : 'أدخل بريدًا إلكترونيًا صحيحًا.';
      _passwordError = validPassword ? null : 'أدخل كلمة المرور.';
      _authError = null;
    });
    if (!validEmail || !validPassword) return;
    setState(() => _busy = true);
    try {
      await widget.auth.loginMunicipality(_email.text, _password.text);
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _authError = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IconButton(
                    tooltip: 'العودة إلى FirePin',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
                const BrandHeader(),
                const SizedBox(height: 36),
                const Icon(
                  Icons.apartment_rounded,
                  size: 58,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text('دخول الجهة المسؤولة', style: AppType.title),
                const SizedBox(height: 6),
                Text(
                  'بوابة البلدية لمتابعة البلاغات والاستجابة الميدانية.',
                  style: AppType.body,
                ),
                const SizedBox(height: 26),
                _AuthField(
                  key: const ValueKey('municipality-email'),
                  controller: _email,
                  label: 'البريد الإلكتروني',
                  hint: 'name@municipality.ps',
                  error: _emailError,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: 14),
                _AuthField(
                  key: const ValueKey('municipality-password'),
                  controller: _password,
                  label: 'كلمة المرور',
                  error: _passwordError,
                  obscureText: _obscure,
                  textDirection: TextDirection.ltr,
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? 'إظهار كلمة المرور'
                        : 'إخفاء كلمة المرور',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                if (_authError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _authError!,
                    key: const ValueKey('municipality-login-error'),
                    style: AppType.text(13, color: AppColors.emergency),
                  ),
                ],
                const SizedBox(height: 22),
                AppButton(
                  _busy ? 'جارٍ تسجيل الدخول...' : 'تسجيل الدخول',
                  onPressed: _busy ? null : _submit,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: widget.onBack,
                  child: const Text('العودة إلى دخول المستخدمين'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.error,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.suffixIcon,
    this.textDirection,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? error;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffixIcon;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    textDirection: textDirection,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
