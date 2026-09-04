import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/queue_item.dart';
import '../models/schedule.dart';
import '../services/github_service.dart';
import '../services/holiday_service.dart';
import '../services/rtdb_client.dart';
import '../services/time_service.dart';

/// Firebase server timestamp placeholder (REST API).
const Map<String, String> kServerTimestamp = <String, String>{'.sv': 'timestamp'};

/// Single source of truth for the whole app: which Zedge account is live, the
/// queue rows streaming in from that account, the daily upload state, the
/// synced clock, the holiday engine and the GitHub panel settings.
class AppState extends ChangeNotifier {
  AppState({required this.holidays, required this.time});

  final HolidayService holidays;
  final TimeService time;

  ZedgeAccount _account = kAccounts.first;
  RtdbClient? _client;
  RtdbWatcher? _queueWatcher;
  RtdbWatcher? _stateWatcher;
  StreamSubscription<Map<String, dynamic>>? _queueSub;
  StreamSubscription<Map<String, dynamic>>? _stateSub;
  Timer? _clockTimer;

  List<QueueItem> _items = <QueueItem>[];
  UploadState _uploadState = UploadState.fromMap(null);
  bool _booting = true;
  bool _connecting = true;
  String? _error;
  bool _holidaysLoading = false;

  // Upload lock shared by Upload Queue + Distribute (one transfer at a time).
  bool _uploading = false;
  String _uploadStatus = '';
  double _uploadProgress = 0;

  // GitHub Control settings.
  GithubConfig _gh = const GithubConfig();
  String _ghSession = '';
  int _ghCfgTs = 0;
  int _ghSessionTs = 0;

  String _previewDeviceId = 'ios-island';

  ZedgeAccount get account => _account;
  List<QueueItem> get items => _items;
  UploadState get uploadState => _uploadState;
  bool get booting => _booting;
  bool get connecting => _connecting;
  String? get error => _error;
  bool get holidaysLoading => _holidaysLoading;
  bool get uploading => _uploading;
  String get uploadStatus => _uploadStatus;
  double get uploadProgress => _uploadProgress;
  GithubConfig get gh => _gh;
  String get ghSession => _ghSession;
  String get previewDeviceId => _previewDeviceId;

  // ---------------------------------------------------------------
  // Clock
  // ---------------------------------------------------------------
  DateTime get dhakaNow => time.nowDhaka();
  DateTime get todayDhaka {
    final DateTime n = dhakaNow;
    return DateTime(n.year, n.month, n.day);
  }
  String get todayKey => dateKeyOf(todayDhaka);
  bool get timeSynced => time.synced;

  // ---------------------------------------------------------------
  // Boot + account switching
  // ---------------------------------------------------------------
  Future<void> boot() async {
    await holidays.loadPreferences();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? saved = prefs.getString('activeProject');
    _previewDeviceId = prefs.getString('previewDeviceId') ?? _previewDeviceId;
    _gh = GithubConfig.fromJson(prefs.getString('ghCtl_v1'));
    _ghSession = prefs.getString('ghGeminiSession_v1') ?? '';
    _ghCfgTs = prefs.getInt('ghCtl_v1_ts') ?? 0;
    _ghSessionTs = prefs.getInt('ghGeminiSession_v1_ts') ?? 0;

    final ZedgeAccount start = accountById(saved ?? kAccounts.first.id);
    holidays.ensureBuiltin(<int>[
      DateTime.now().year,
      DateTime.now().year + 1,
      DateTime.now().year + 2,
    ]);
    unawaited(time.sync(start.databaseUrl).then((_) => notifyListeners()));
    await connect(start, persist: false);
    _booting = false;
    notifyListeners();
    unawaited(refreshHolidays());
    unawaited(syncGithubSettingsFromDb());
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      notifyListeners();
    });
  }

  Future<void> refreshHolidays() async {
    _holidaysLoading = true;
    notifyListeners();
    final int year = todayDhaka.year;
    try {
      await holidays.ensureYears(<int>[year, year + 1, year + 2]);
    } finally {
      _holidaysLoading = false;
      notifyListeners();
    }
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
        _items = _parse(snapshot);
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
      if (_items.isEmpty && initial.isNotEmpty) _items = _parse(initial);
      final Map<String, dynamic> st = await client.readMap(kUploadStatePath);
      if (st.isNotEmpty) _uploadState = UploadState.fromMap(st);
      _connecting = false;
      notifyListeners();
    } catch (error) {
      _connecting = false;
      _error = error.toString();
      notifyListeners();
    }
  }

  static List<QueueItem> _parse(Map<String, dynamic> snapshot) {
    final List<QueueItem> parsed = <QueueItem>[];
    snapshot.forEach((String key, Object? value) {
      if (value is Map) {
        parsed.add(QueueItem.fromMap(key, Map<String, dynamic>.from(value)));
      }
    });
    // Push ids are chronological - newest first, same as the dashboard.
    parsed.sort((QueueItem a, QueueItem b) => b.id.compareTo(a.id));
    return parsed;
  }

  // ---------------------------------------------------------------
  // Stats (queued rows only - same as the dashboard cards)
  // ---------------------------------------------------------------
  List<QueueItem> get queuedItems =>
      _items.where((QueueItem i) => i.isQueued).toList();

  int get queuedCount => queuedItems.length;

  int countBucket(String bucket) =>
      queuedItems.where((QueueItem i) => i.bucket == bucket).length;

  int get audioCount => countBucket('AUDIO');
  int get specialCount =>
      queuedItems.where((QueueItem i) => i.isSpecial).length;
  int get wallpaperCount => queuedCount - audioCount - specialCount;

  List<QueueItem> get recentItems => _items.take(4).toList();

  Map<String, int> get statusCounts {
    final Map<String, int> counts = <String, int>{};
    for (final QueueItem item in _items) {
      counts[item.status] = (counts[item.status] ?? 0) + 1;
    }
    return counts;
  }

  // ---------------------------------------------------------------
  // Schedule
  // ---------------------------------------------------------------
  ScheduleStats get scheduleStats =>
      computeScheduleStats(_uploadState, todayDhaka);

  List<ScheduleDay> buildScheduleDays() => buildSchedule(
        items: _items,
        uploadState: _uploadState,
        todayDhaka: todayDhaka,
      );

  List<QueueItem> pinnedOn(String dateKey) => _items
      .where((QueueItem i) => i.isQueued && i.scheduledDate == dateKey)
      .toList();

  List<QueueItem> get unpinnedQueued =>
      queuedItems.where((QueueItem i) => i.scheduledDate.isEmpty).toList();

  // ---------------------------------------------------------------
  // Upload lock
  // ---------------------------------------------------------------
  bool beginUpload(String status) {
    if (_uploading) return false;
    _uploading = true;
    _uploadStatus = status;
    _uploadProgress = 0;
    notifyListeners();
    return true;
  }

  void reportUpload(String status, [double? progress]) {
    _uploadStatus = status;
    if (progress != null) _uploadProgress = progress.clamp(0.0, 1.0);
    notifyListeners();
  }

  void endUpload([String status = '']) {
    _uploading = false;
    _uploadStatus = status;
    _uploadProgress = 0;
    notifyListeners();
  }

  // ---------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------
  RtdbClient _clientFor(ZedgeAccount account) {
    if (account.id == _account.id && _client != null) return _client!;
    return RtdbClient(databaseUrl: account.databaseUrl);
  }

  Future<void> updateItem(String id, Map<String, dynamic> data) async {
    final RtdbClient? client = _client;
    if (client == null) throw Exception('No database connection');
    await client.patch('$kQueuePath/$id', data);
    // Optimistic local update so the UI reacts before the stream echoes.
    final int idx = _items.indexWhere((QueueItem i) => i.id == id);
    if (idx >= 0) {
      final Map<String, dynamic> raw = Map<String, dynamic>.from(_items[idx].raw);
      data.forEach((String k, Object? v) {
        if (v == null) {
          raw.remove(k);
        } else {
          raw[k] = v;
        }
      });
      _items[idx] = QueueItem(id: id, raw: raw);
      notifyListeners();
    }
  }

  Future<void> deleteItem(String id) async {
    final RtdbClient? client = _client;
    if (client == null) throw Exception('No database connection');
    await client.delete('$kQueuePath/$id');
    _items.removeWhere((QueueItem i) => i.id == id);
    notifyListeners();
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
    await updateItem(id, <String, dynamic>{
      'scheduledDate': (dateKey == null || dateKey.isEmpty) ? null : dateKey,
    });
  }

  /// Duplicates a queue row into the other two Zedge accounts (media stays in
  /// R2, only the metadata row is copied - identical to the web modal).
  Future<int> copyToOtherAccounts(QueueItem item) async {
    int copied = 0;
    for (final ZedgeAccount target in kAccounts) {
      if (target.id == _account.id) continue;
      final RtdbClient client = RtdbClient(databaseUrl: target.databaseUrl);
      try {
        final Map<String, dynamic> payload =
            Map<String, dynamic>.from(item.raw);
        payload.remove('id');
        payload['status'] = 'queued';
        payload['error'] = null;
        payload['copiedFrom'] = _account.id;
        payload['createdAt'] = kServerTimestamp;
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

  Future<String> addQueueItem(Map<String, dynamic> data) =>
      addQueueItemTo(_account, data);

  Future<String> addQueueItemTo(
      ZedgeAccount account, Map<String, dynamic> data) async {
    final RtdbClient client = _clientFor(account);
    try {
      return await client.push(kQueuePath, data);
    } finally {
      if (client != _client) client.close();
    }
  }

  /// True when a queued row with this name exists in the active account.
  bool nameExists(String name) => _items.any(
      (QueueItem i) => i.name.toLowerCase() == name.toLowerCase());

  // ---------------------------------------------------------------
  // Preferences
  // ---------------------------------------------------------------
  Future<void> setPreviewDevice(String id) async {
    _previewDeviceId = id;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('previewDeviceId', id);
  }

  // ---------------------------------------------------------------
  // GitHub settings (local + synced on Zedge 1 `dashboardSettings/ghPanel`)
  // ---------------------------------------------------------------
  Future<void> saveGithubConfig(GithubConfig cfg) async {
    _gh = cfg;
    _ghCfgTs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('ghCtl_v1', cfg.toJson());
    await prefs.setInt('ghCtl_v1_ts', _ghCfgTs);
    unawaited(_pushGhToDb(<String, dynamic>{
      'cfg': cfg.toJson(),
      'cfgUpdatedAt': _ghCfgTs,
    }));
  }

  Future<void> saveGithubSession(String session) async {
    _ghSession = session;
    _ghSessionTs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('ghGeminiSession_v1', session);
    await prefs.setInt('ghGeminiSession_v1_ts', _ghSessionTs);
    unawaited(_pushGhToDb(<String, dynamic>{
      'session': session,
      'sessionUpdatedAt': _ghSessionTs,
    }));
  }

  Future<void> _pushGhToDb(Map<String, dynamic> data) async {
    final RtdbClient client = RtdbClient(databaseUrl: kAccounts.first.databaseUrl);
    try {
      await client.patch(kGhSettingsPath, data);
    } catch (_) {
      // Offline - local copy is still saved.
    } finally {
      client.close();
    }
  }

  /// Newer timestamp wins between the local copy and the shared DB copy.
  Future<void> syncGithubSettingsFromDb() async {
    final RtdbClient client = RtdbClient(databaseUrl: kAccounts.first.databaseUrl);
    try {
      final Map<String, dynamic> remote = await client.readMap(kGhSettingsPath);
      if (remote.isEmpty) return;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int remoteCfgTs = (remote['cfgUpdatedAt'] as num?)?.toInt() ?? 0;
      final String? remoteCfg = remote['cfg']?.toString();
      if (remoteCfg != null && remoteCfg.isNotEmpty && remoteCfgTs > _ghCfgTs) {
        _gh = GithubConfig.fromJson(remoteCfg);
        _ghCfgTs = remoteCfgTs;
        await prefs.setString('ghCtl_v1', remoteCfg);
        await prefs.setInt('ghCtl_v1_ts', remoteCfgTs);
      }
      final int remoteSesTs = (remote['sessionUpdatedAt'] as num?)?.toInt() ?? 0;
      final String? remoteSes = remote['session']?.toString();
      if (remoteSes != null && remoteSes.isNotEmpty && remoteSesTs > _ghSessionTs) {
        _ghSession = remoteSes;
        _ghSessionTs = remoteSesTs;
        await prefs.setString('ghGeminiSession_v1', remoteSes);
        await prefs.setInt('ghGeminiSession_v1_ts', remoteSesTs);
      }
      notifyListeners();
    } catch (_) {
      // ignore
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _queueSub?.cancel();
    _stateSub?.cancel();
    _queueWatcher?.close();
    _stateWatcher?.close();
    _client?.close();
    super.dispose();
  }
}
