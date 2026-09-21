import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/ui/components.dart';

class NotificationEntry {
  const NotificationEntry({
    required this.id,
    required this.fireReportId,
    required this.eventType,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final int id;
  final int fireReportId;
  final String eventType;
  final String title;
  final String body;
  final DateTime createdAt;

  factory NotificationEntry.fromJson(Map<String, dynamic> json) =>
      NotificationEntry(
        id: json['id'] as int,
        fireReportId: json['fire_report_id'] as int,
        eventType: json['event_type'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

abstract interface class NotificationHistoryRepository {
  Future<List<NotificationEntry>> getUserNotifications();
  Future<List<NotificationEntry>> getMunicipalityNotifications();
}

class ApiNotificationHistoryRepository
    implements NotificationHistoryRepository {
  ApiNotificationHistoryRepository(this._userApi, this._municipalityApi);

  final ApiClient _userApi;
  final ApiClient _municipalityApi;

  @override
  Future<List<NotificationEntry>> getUserNotifications() =>
      _load(_userApi, '/notifications/me');

  @override
  Future<List<NotificationEntry>> getMunicipalityNotifications() =>
      _load(_municipalityApi, '/municipalities/auth/notifications');

  Future<List<NotificationEntry>> _load(ApiClient api, String path) async {
    final response = await api.get<List<dynamic>>(path, requiresAuth: true);
    final items = response.data;
    if (items == null) throw const FormatException('Invalid notifications');
    return List.unmodifiable(
      items.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid notification');
        }
        return NotificationEntry.fromJson(item);
      }),
    );
  }
}

class NotificationHistoryView extends StatefulWidget {
  const NotificationHistoryView({
    super.key,
    required this.load,
    required this.onOpenReport,
  });

  final Future<List<NotificationEntry>> Function() load;
  final Future<void> Function(int reportId) onOpenReport;

  @override
  State<NotificationHistoryView> createState() =>
      _NotificationHistoryViewState();
}

class _NotificationHistoryViewState extends State<NotificationHistoryView> {
  List<NotificationEntry> _items = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await widget.load();
      if (mounted) setState(() => _items = items);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(int reportId) async {
    await widget.onOpenReport(reportId);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('real-notification-history'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(child: PageTitle('التنبيهات')),
          IconButton(
            key: const ValueKey('refresh-notifications'),
            tooltip: 'تحديث التنبيهات',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (_failed)
        SurfaceCard(
          warning: true,
          child: Column(
            children: [
              const Text(
                'تعذّر تحميل التنبيهات. تحقق من الاتصال وحاول مجددًا.',
              ),
              AppButton('إعادة المحاولة', onPressed: _reload),
            ],
          ),
        )
      else if (_items.isEmpty)
        const SurfaceCard(child: Text('لا توجد تنبيهات حتى الآن.'))
      else
        for (final item in _items) ...[
          SurfaceCard(
            child: ListTile(
              key: ValueKey('notification-${item.id}'),
              title: Text(item.title),
              subtitle: Text(item.body),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _open(item.fireReportId),
            ),
          ),
          const SizedBox(height: 10),
        ],
    ],
  );
}
