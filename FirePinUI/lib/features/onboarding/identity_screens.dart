import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/components.dart';
import '../../theme/app_theme.dart';
import 'onboarding_models.dart';

class IdentityDetailsScreen extends StatefulWidget {
  const IdentityDetailsScreen({
    super.key,
    required this.onContinue,
    this.onBack,
  });

  final ValueChanged<IdentityData> onContinue;
  final VoidCallback? onBack;

  @override
  State<IdentityDetailsScreen> createState() => _IdentityDetailsScreenState();
}

class _IdentityDetailsScreenState extends State<IdentityDetailsScreen> {
  final _fullName = TextEditingController();
  final _nationalId = TextEditingController();
  final _birthDate = TextEditingController();
  String? _error;

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  void _submit() {
    final fullName = _fullName.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final nationalId = normalizeDigits(_nationalId.text).trim();
    final birthDate = normalizeDigits(_birthDate.text).trim();
    if (RegExp(r'[ء-ي]{2,}').allMatches(fullName).length < 2) {
      setState(() => _error = 'أدخل الاسم الكامل كما هو في الهوية.');
      return;
    }
    if (!RegExp(r'^[0-9]{9}$').hasMatch(nationalId)) {
      setState(() => _error = 'رقم الهوية يجب أن يتكوّن من 9 أرقام.');
      return;
    }
    if (!_validBirthDate(birthDate)) {
      setState(() => _error = 'أدخل تاريخ ميلاد صحيحًا بصيغة يوم/شهر/سنة.');
      return;
    }
    FocusScope.of(context).unfocus();
    widget.onContinue(
      IdentityData(
        fullName: fullName,
        identityNumber: nationalId,
        birthDate: birthDate,
        address: '',
      ),
    );
  }

  bool _validBirthDate(String value) {
    final parts = value.split(RegExp(r'\s*/\s*'));
    if (parts.length != 3) return false;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return false;
    final date = DateTime(year, month, day);
    final today = DateTime.now();
    return date.year == year &&
        date.month == month &&
        date.day == day &&
        year >= today.year - 120 &&
        !date.isAfter(DateTime(today.year, today.month, today.day));
  }

  @override
  void dispose() {
    _fullName.dispose();
    _nationalId.dispose();
    _birthDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnboardingPage(
    onBack: widget.onBack,
    children: [
      const SizedBox(height: 32),
      const PageTitle('بيانات الحساب'),
      const SizedBox(height: 8),
      Text('أدخل بياناتك كما تظهر في بطاقة الهوية.', style: AppType.body),
      const SizedBox(height: 26),
      _Field(
        key: const ValueKey('identity-full-name'),
        controller: _fullName,
        label: 'الاسم الكامل',
        textInputAction: TextInputAction.next,
        onChanged: _clearError,
      ),
      const SizedBox(height: 14),
      _Field(
        key: const ValueKey('identity-national-id'),
        controller: _nationalId,
        label: 'رقم الهوية',
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        maxLength: 9,
        textInputAction: TextInputAction.next,
        onChanged: _clearError,
      ),
      const SizedBox(height: 14),
      _Field(
        key: const ValueKey('identity-birth-date'),
        controller: _birthDate,
        label: 'تاريخ الميلاد',
        hint: '14 / 05 / 1998',
        keyboardType: TextInputType.datetime,
        textDirection: TextDirection.ltr,
        textInputAction: TextInputAction.next,
        onChanged: _clearError,
      ),
      InlineMessage(_error),
      const SizedBox(height: 30),
      AppButton('متابعة', onPressed: _submit),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.hint,
    this.keyboardType,
    this.textDirection,
    this.maxLength,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;
  final String? hint;
  final TextInputType? keyboardType;
  final TextDirection? textDirection;
  final int? maxLength;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    textDirection: textDirection,
    textInputAction: textInputAction,
    maxLength: maxLength,
    inputFormatters: keyboardType == TextInputType.number
        ? [
            TextInputFormatter.withFunction(
              (oldValue, newValue) =>
                  newValue.copyWith(text: normalizeDigits(newValue.text)),
            ),
            FilteringTextInputFormatter.digitsOnly,
          ]
        : null,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      counterText: '',
    ),
    onChanged: (_) => onChanged(),
  );
}
