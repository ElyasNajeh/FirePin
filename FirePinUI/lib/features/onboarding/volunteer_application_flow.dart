import 'package:flutter/material.dart';

import '../municipality/municipality_repository.dart';
import 'municipality_selection_screen.dart';
import 'onboarding_models.dart';
import 'onboarding_services.dart';
import 'role_screens.dart';

class VolunteerApplicationFlow extends StatefulWidget {
  const VolunteerApplicationFlow({
    super.key,
    required this.directory,
    required this.applications,
    required this.onCancel,
    required this.onSubmitted,
  });

  final MunicipalityDirectoryRepository directory;
  final VolunteerApplicationService applications;
  final VoidCallback onCancel;
  final Future<void> Function(ApplicationStatus status) onSubmitted;

  @override
  State<VolunteerApplicationFlow> createState() =>
      _VolunteerApplicationFlowState();
}

class _VolunteerApplicationFlowState extends State<VolunteerApplicationFlow> {
  MunicipalityDirectoryEntry? _municipality;

  @override
  Widget build(BuildContext context) {
    final municipality = _municipality;
    if (municipality == null) {
      return MunicipalitySelectionScreen(
        repository: widget.directory,
        onBack: widget.onCancel,
        onContinue: (selected) => setState(() => _municipality = selected),
      );
    }
    return VolunteerWarningScreen(
      service: widget.applications,
      municipalityId: municipality.id,
      onBack: () => setState(() => _municipality = null),
      onSubmitted: widget.onSubmitted,
    );
  }
}
