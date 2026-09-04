import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/queue_item.dart';
import '../services/holiday_service.dart';
import '../services/rtdb_client.dart';

/// Single source of truth for the whole app: which Zedge account is live, the
/// queue rows streaming in from that account, the daily upload state and the
/// holiday engine.
class AppState extends ChangeNotifier {
  AppState({required this.holidays});

  final HolidayService holidays;

  ZedgeAccount _account = kAccounts.first;
  RtdbClient? _client;
  RtdbWatcher? _queueWatcher;
  RtdbWatcher? _stateWatcher;
  StreamSubscription<Map<String, dynamic>>? _queueSub;
  StreamSubscription<Map<String, dynamic>>? _stateSub;

  List<QueueItem> _items = <QueueItem>[];
  UploadState _uploadState = UploadState.fromMap(null);
  bool _connecting = true;
  String? _error;
  String _search = '';
  String _typeFilter = 'ALL';
  String _statusFilter = 'ALL';

  ZedgeAccount get account => _account;
  List<QueueItem> get items => _items;
  UploadState get uploadState => _uploadState;
  bool get connecting => _connecting;
  String? get error => _error;
  String get search => _search;
  String get typeFilter => _typeFilter;
  String get statusFilter => _statusFilter;

  String get todayKey => DateFormat('yyyy-MM-dd').format(DateTime.now());
  String get todayType => _uploadState.typeForToday(todayKey);
  int get uploadsToday => _uploadState.uploadsToday(todayKey);

  // ---------------------------------------------------------------
  // Boot + account switching
  // ---------------------------------------------------------------
  Future<void> boot() async {
    await holidays.loadPreferences();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('activeProject');
    final ZedgeAccount start = kAccounts.firstWhere(
      (ZedgeAccount candidate) => candidate.id == saved,
      orElse: () => kAccounts.first,
    );
    await connect(start, persist: false);
    refreshHolidays();
  }

  Future<void> refreshHolidays() async {
    final int year = DateTime.now().year;
    await holidays.ensureYears(<int>[year, year + 1]);
    notifyListeners();
  }

  Future<void> connect(ZedgeAccount account, {bool persist = true}) async {
    _account = account;
    _connecting = true;
    _error = null;
    _items = <QueueItem>[];
    _uploadState = UploadState.fromMap(null);
    notifyListeners();

    await _queueSub?.cancel();
    await _stateSub?.cancel();
    await _queueWatcher?.close();
    await _stateWatcher?.close();
    _client?.close();

    if (persist) {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('activeProject', account.id);
    }

    final RtdbClient client = RtdbClient(databaseUrl: account.databaseUrl);
    _client = client;

    _queueWatcher = client.watchMap(kQueuePath);
    _queueSub = _queueWatcher!.stream.listen(
      (Map<String, dynamic> snapshot) {
        final List<QueueItem> parsed = <QueueItem>[];
        snapshot.forEach((String key, Object? value) {
          if (value is Map) {
            parsed.add(QueueItem.fromMap(key, Map<String, dynamic>.from(value)));
          }
        });
        parsed.sort((QueueItem a, QueueItem b) {
          final int byDate = b.createdAt.compareTo(a.createdAt);
          if (byDate != 0) return byDate;
          return b.id.compareTo(a.id);
        });
        _items = parsed;
        _connecting = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object error) {
        _connecting = false;
        _error = error.toString();
        notifyListeners();
      },
    );

    _stateWatcher = client.watchMap(kUploadStatePath);
    _stateSub = _stateWatcher!.stream.listen((Map<String, dynamic> snapshot) {
      _uploadState = UploadState.fromMap(snapshot);
      notifyListeners();
    });

    // Safety net: if the stream is slow, show whatever REST returns.
    try {
      final Map<String, dynamic> initial = await client.readMap(kQueuePath);
      if (_items.isEmpty && initial.isNotEmpty) {
        final List<QueueItem> parsed = <QueueItem>[];
        initial.forEach((String key, Object? value) {
          if (value is Map) {
            parsed.add(QueueItem.fromMap(key, Map<String, dynamic>.from(value)));
          }
        });
        parsed.sort((QueueItem a, QueueItem b) => b.createdAt.compareTo(a.createdAt));
        _items = parsed;
      }
      _connecting = false;
      notifyListeners();
    } catch (error) {
      _connecting = false;
      _error = error.toString();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------
  // Filtering helpers used by the queue screen
  // ---------------------------------------------------------------
  void setSearch(String value) {
    _search = value;
    notifyListeners();
  }

  void setTypeFilter(String value) {
    _typeFilter = value;
    notifyListeners();
  }

  void setStatusFilter(String value) {
    _statusFilter = value;
    notifyListeners();
  }

  List<QueueItem> get filteredItems {
    final String needle = _search.trim().toLowerCase();
    return _items.where((QueueItem item) {
      if (_typeFilter != 'ALL' && item.contentType != _typeFilter) return false;
      if (_statusFilter != 'ALL' && item.status != _statusFilter) return false;
      if (needle.isEmpty) return true;
      return item.displayTitle.toLowerCase().contains(needle) ||
          item.tags.toLowerCase().contains(needle) ||
          item.category.toLowerCase().contains(needle) ||
          item.name.toLowerCase().contains(needle);
    }).toList();
  }

  Map<String, int> get statusCounts {
    final Map<String, int> counts = <String, int>{};
    for (final QueueItem item in _items) {
      counts[item.status] = (counts[item.status] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> get typeCounts {
    final Map<String, int> counts = <String, int>{};
    for (final QueueItem item in _items) {
      counts[item.contentType] = (counts[item.contentType] ?? 0) + 1;
    }
    return counts;
  }

  List<QueueItem> itemsForDateKey(String dateKey) => _items
      .where((QueueItem item) => item.scheduledDate == dateKey)
      .toList();

  List<QueueItem> get unscheduledItems => _items
      .where((QueueItem item) => item.scheduledDate.isEmpty)
      .toList();

  // ---------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------
  Future<void> updateItem(String id, Map<String, dynamic> data) async {
    final RtdbClient? client = _client;
    if (client == null) return;
    await client.patch('$kQueuePath/$id', data);
  }

  Future<void> deleteItem(String id) async {
    final RtdbClient? client = _client;
    if (client == null) return;
    await client.delete('$kQueuePath/$id');
  }

  Future<void> requeueItem(String id) async {
    await updateItem(id, <String, dynamic>{
      'status': 'queued',
      'error': null,
      'failedAt': null,
      'processingAt': null,
    });
  }

  Future<void> setScheduledDate(String id, String? dateKey) async {
    await updateItem(id, <String, dynamic>{'scheduledDate': dateKey});
  }

  /// Duplicates a queue row into the other two Zedge accounts. The media stays
  /// in R2, so only the metadata row is copied.
  Future<int> copyToOtherAccounts(QueueItem item) async {
    int copied = 0;
    for (final ZedgeAccount target in kAccounts) {
      if (target.id == _account.id) continue;
      final RtdbClient client = RtdbClient(databaseUrl: target.databaseUrl);
      try {
        final Map<String, dynamic> payload =
            Map<String, dynamic>.from(item.raw);
        payload['status'] = 'queued';
        payload['error'] = null;
        payload['copiedFrom'] = _account.id;
        payload['timestamp'] = DateTime.now().millisecondsSinceEpoch;
        await client.push(kQueuePath, payload);
        copied++;
      } catch (_) {
        // Keep going - one unreachable account must not block the others.
      } finally {
        client.close();
      }
    }
    return copied;
  }

  Future<String> addQueueItem(Map<String, dynamic> data) async {
    final RtdbClient? client = _client;
    if (client == null) throw Exception('No database connection');
    return client.push(kQueuePath, data);
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _stateSub?.cancel();
    _queueWatcher?.close();
    _stateWatcher?.close();
    _client?.close();
    super.dispose();
  }
}
