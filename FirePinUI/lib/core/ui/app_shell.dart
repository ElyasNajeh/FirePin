import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'components.dart';

enum AppSection { home, alerts, account }

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.section,
    required this.onSectionChanged,
    required this.child,
    this.scrollable = true,
    this.showHeaderActions = true,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSectionChanged;
  final Widget child;
  final bool scrollable;
  final bool showHeaderActions;

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    final content = Padding(
      padding: EdgeInsets.fromLTRB(20, math.max(16, safe.top + 8), 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AppHeader(
            showActions: showHeaderActions,
            onSectionChanged: onSectionChanged,
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
    return Scaffold(
      bottomNavigationBar: _AppNavigation(
        section: section,
        onSectionChanged: onSectionChanged,
        bottomInset: safe.bottom,
      ),
      body: scrollable ? SingleChildScrollView(child: content) : content,
    );
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({required this.showActions, required this.onSectionChanged});

  final bool showActions;
  final ValueChanged<AppSection> onSectionChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Row(
      children: [
        const Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: BrandHeader(),
          ),
        ),
        if (showActions) ...[
          _HeaderAction(
            label: 'الحساب',
            asset: 'account',
            onTap: () => onSectionChanged(AppSection.account),
          ),
          const SizedBox(width: 10),
          _HeaderAction(
            label: 'الإشعارات',
            asset: 'notification',
            onTap: () => onSectionChanged(AppSection.alerts),
          ),
        ],
      ],
    ),
  );
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.label,
    required this.asset,
    required this.onTap,
  });

  final String label;
  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: AppColors.outline)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(child: FigmaIcon(asset, size: 22)),
        ),
      ),
    ),
  );
}

class _AppNavigation extends StatelessWidget {
  const _AppNavigation({
    required this.section,
    required this.onSectionChanged,
    required this.bottomInset,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSectionChanged;
  final double bottomInset;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 90),
    padding: EdgeInsets.fromLTRB(24, 10, 24, math.max(12, bottomInset)),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.outline)),
    ),
    child: Row(
      children: AppSection.values.map((item) {
        final selected = section == item;
        final (label, asset) = switch (item) {
          AppSection.home => ('الرئيسية', 'nav_home'),
          AppSection.alerts => ('التنبيهات', 'nav_alerts'),
          AppSection.account => ('الحساب', 'nav_account'),
        };
        return Expanded(
          child: Semantics(
            selected: selected,
            button: true,
            child: InkWell(
              onTap: () => onSectionChanged(item),
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 58,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    FigmaIcon(asset, size: 24),
                    const SizedBox(height: 2),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: AppType.text(
                            13,
                            height: 25,
                            weight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    ),
  );
}
