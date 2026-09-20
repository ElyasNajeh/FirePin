import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui/components.dart';
import '../../theme/app_theme.dart';
import '../municipality/municipality_repository.dart';

class MunicipalitySelectionScreen extends StatefulWidget {
  const MunicipalitySelectionScreen({
    super.key,
    required this.repository,
    required this.onContinue,
    required this.onBack,
    this.initialMunicipalityId,
  });

  final MunicipalityDirectoryRepository repository;
  final ValueChanged<MunicipalityDirectoryEntry> onContinue;
  final VoidCallback onBack;
  final int? initialMunicipalityId;

  @override
  State<MunicipalitySelectionScreen> createState() =>
      _MunicipalitySelectionScreenState();
}

class _MunicipalitySelectionScreenState
    extends State<MunicipalitySelectionScreen> {
  List<MunicipalityDirectoryEntry>? _municipalities;
  MunicipalityDirectoryEntry? _selected;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final selectedId = _selected?.id ?? widget.initialMunicipalityId;
    setState(() {
      _municipalities = null;
      _error = null;
    });
    try {
      final municipalities = await widget.repository.getActiveMunicipalities();
      if (!mounted) return;
      setState(() {
        _municipalities = municipalities;
        _selected = municipalities
            .where((item) => item.id == selectedId)
            .firstOrNull;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  void _select(MunicipalityDirectoryEntry municipality) {
    HapticFeedback.selectionClick();
    setState(() => _selected = municipality);
  }

  @override
  Widget build(BuildContext context) => OnboardingPage(
    onBack: widget.onBack,
    children: [
      const SizedBox(height: 34),
      const PageTitle('اختر البلدية'),
      const SizedBox(height: 8),
      Text(
        'اختر البلدية التي ستراجع طلب التطوع الخاص بك.',
        style: AppType.text(15, color: AppColors.textSecondary, height: 28),
      ),
      const SizedBox(height: 24),
      _directoryContent(),
      const SizedBox(height: 28),
      AppButton(
        'متابعة',
        key: const ValueKey('municipality-selection-continue'),
        onPressed: _selected == null
            ? null
            : () => widget.onContinue(_selected!),
      ),
    ],
  );

  Widget _directoryContent() {
    final municipalities = _municipalities;
    if (_error != null) {
      return Column(
        key: const ValueKey('municipality-directory-error'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InlineMessage(
            'تعذّر تحميل البلديات. تحقق من الاتصال وحاول مجددًا.',
          ),
          const SizedBox(height: 12),
          AppButton('إعادة المحاولة', secondary: true, onPressed: _load),
        ],
      );
    }
    if (municipalities == null) {
      return const SizedBox(
        key: ValueKey('municipality-directory-loading'),
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (municipalities.isEmpty) {
      return Column(
        key: const ValueKey('municipality-directory-empty'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'لا توجد بلديات متاحة حاليًا.',
            textAlign: TextAlign.center,
            style: AppType.text(15, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          AppButton('إعادة التحميل', secondary: true, onPressed: _load),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final municipality in municipalities) ...[
          _MunicipalityCard(
            municipality: municipality,
            selected: _selected?.id == municipality.id,
            onTap: () => _select(municipality),
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: const ValueKey('municipality-directory-reload'),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة التحميل'),
          ),
        ),
      ],
    );
  }
}

class _MunicipalityCard extends StatelessWidget {
  const _MunicipalityCard({
    required this.municipality,
    required this.selected,
    required this.onTap,
  });

  final MunicipalityDirectoryEntry municipality;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? AppColors.primaryContainer : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.outline,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: ValueKey('municipality-${municipality.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(municipality.name, style: AppType.section)),
            ],
          ),
        ),
      ),
    ),
  );
}
