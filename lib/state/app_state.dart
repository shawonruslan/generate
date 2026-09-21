import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_config.dart';
import '../core/constants.dart';
import '../core/dhaka_time.dart';
import '../data/firebase_rtdb.dart';
import '../data/github_api.dart';
import '../data/meta_book.dart';
import '../data/models.dart';
import '../data/queue_repository.dart';
import '../data/r2_client.dart';
import '../domain/run_schedule.dart';
import '../domain/schedule_planner.dart';
import '../domain/special_days.dart';
import '../domain/theme_engine.dart';
import '../domain/vpn.dart';
import 'notifications.dart';

/// Toast message (`showToast(msg, kind)`), kinds: ok | err | error | warn.
class ToastMsg {
  ToastMsg(this.text, this.kind) : id = DateTime.now().microsecondsSinceEpoch;
  final int id;
  final String text;
  final String kind;
}

class GhLogLine {
  GhLogLine(this.time, this.msg, this.kind);
  final String time;
  final String msg;
  final String kind; // '' | ok | err
}

/// Queue toolbar filter (`queueFilter`).
class QueueFilter {
  String search = '';
  String type = 'ALL';
  String status = 'ALL'; // queued | processing | uploaded | failed | nometa
  String dateFrom = '';
  String dateTo = '';

  bool get isScoped => search.trim().isNotEmpty || type != 'ALL' || status != 'ALL' || dateFrom.isNotEmpty || dateTo.isNotEmpty;

  void clear() {
    search = '';
    type = 'ALL';
    status = 'ALL';
    dateFrom = '';
    dateTo = '';
  }

  String scopeText() {
    final parts = <String>[];
    if (search.trim().isNotEmpty) parts.add('search "${search.trim()}"');
    if (type != 'ALL') parts.add('type ${kQueueTypeLabels[type] ?? type}');
    if (status != 'ALL') parts.add('status $status');
    if (dateFrom.isNotEmpty || dateTo.isNotEmpty) parts.add('date ${dateFrom.isEmpty ? '…' : dateFrom} → ${dateTo.isEmpty ? '…' : dateTo}');
    return parts.join(', ');
  }
}

/// Central application state - one instance for the whole desktop app.
class AppState extends ChangeNotifier {
  AppState(this.profile)
      : dbs = {for (final a in profile.accounts) a.key: FirebaseRtdb(a)},
        r2 = R2Client(profile.r2WorkerUrl),
        schedule = RunSchedule(defaultWindows: profile.defaultUploadWindows),
        specialDays = SpecialDaysEngine(googleCalendarApiKey: profile.googleCalendarApiKey) {
    repo = QueueRepository(dbs: dbs, r2: r2, metaBook: metaBook);
  }

  final BuildProfile profile;
  final Map<String, FirebaseRtdb> dbs;
  final R2Client r2;
  final MetaBook metaBook = MetaBook();
  final RunSchedule schedule;
  final SpecialDaysEngine specialDays;
  late final QueueRepository repo;
  final NotificationCenter notifications = NotificationCenter();

  List<String> get accountKeys => dbs.keys.toList();
  String accountLabel(String key) {
    final idx = accountKeys.indexOf(key);
    return idx >= 0 ? 'Zedge ${idx + 1}' : key.replaceAll(RegExp(r'zedge(\d+)', caseSensitive: false), 'Zedge ');
  }

  String accountUpper(String key) => key.toUpperCase();
  String accountSpaced(String key) => key.replaceAll('zedge', 'ZEDGE ');

  // ------------------------------------------------------------ live data
  String activeProject = 'zedge1';
  List<QueueItem> queueItems = [];
  UploadState? uploadState;
  bool queueLoaded = false;
  bool connecting = true;
  bool liveSync = false;
  final Map<String, MetaAlertReport?> metaAlerts = {};
  final Map<String, Map<String, dynamic>?> varietyCfg = {};
  final Map<String, Map<String, dynamic>?> varietyUsed = {};
  final Map<String, GateHealth?> gateHealth = {};
  final Map<String, VpnState> vpnStates = {};
  bool vpnLive = false;

  StreamSubscription? _queueSub;
  StreamSubscription? _stateSub;
  final List<StreamSubscription> _globalSubs = [];
  bool _schedulesSubscribed = false;
  Timer? _minuteTimer;
  Timer? _secondTimer;

  /// Ticks every second - used only by clocks / countdown widgets.
  final ValueNotifier<int> clockTick = ValueNotifier<int>(0);

  // ------------------------------------------------------------ prefs
  bool metaNotify = false;
  String previewDeviceId = 'ios-island';
  int presSpeed = 3000;
  String sidebarState = 'full';
  String? _metaSeenKey;

  // ------------------------------------------------------------ theme
  final Map<String, ThemeConfig?> themeRemote = {};
  ThemeConfig themeCurrent = ThemeConfig.defaults;
  ThemeConfig themeSaved = ThemeConfig.defaults;
  bool themeEditing = false;
  ZedgePalette palette = ZedgePalette(ThemeConfig.defaults);

  // ------------------------------------------------------------ toasts
  final List<ToastMsg> toasts = [];

  // ------------------------------------------------------------ UI filters
  final QueueFilter queueFilter = QueueFilter();
  int uploadPage = 1;
  int schedulePage = 0;
  int scheduleDaysPerPage = kScheduleDaysPerPage;
  String pinFilterType = 'ALL';
  String pinSearch = '';
  String pinPickerSearch = '';
  String distVideoType = 'LIVE_WALLPAPER';
  String distImageMode = 'WALLPAPER';
  String distStatus = 'Waiting for image selection...';
  bool? distStatusOk;
  double distProgress = 0;
  String smartArchiveStatus = '';
  String smartArchiveBtn = 'Choose Archive';
  final Map<String, List<RunSlot>> schedDraft = {};
  final Map<String, VarietyConfig> varietyDraft = {};

  // ------------------------------------------------------------ GitHub panel
  GhCfg ghCfg = GhCfg();
  String ghSession = '';
  final List<GhLogLine> ghLog = [];
  String ghConnStatus = '';
  String ghConnStatusCls = '';
  String ghSessionStatus = '';
  String ghSessionStatusCls = '';
  List<Map<String, dynamic>> ghRuns = [];
  bool ghRunsLoading = false;
  String? ghRunsError;
  String ghCurrentPath = '';
  List<Map<String, dynamic>> ghFiles = [];
  bool ghFilesLoading = false;
  String? ghFilesError;

  // ------------------------------------------------------------ lifecycle
  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    activeProject = sp.getString('activeProject') ?? accountKeys.first;
    if (!dbs.containsKey(activeProject)) activeProject = accountKeys.first;
    metaNotify = sp.getString('zMetaNotify') == '1';
    previewDeviceId = sp.getString('previewDeviceId') ?? 'ios-island';
    presSpeed = int.tryParse(sp.getString('presSpeed') ?? '') ?? 3000;
    sidebarState = sp.getString('v27:sb') ?? 'full';
    ghCfg = await GhLocalStore.loadCfg();
    ghSession = await GhLocalStore.loadSession();
    await notifications.load();
    for (final k in accountKeys) {
      vpnStates[k] = VpnState(null);
    }
    themeSaved = await ThemeStore.loadLocal(activeProject) ?? ThemeConfig.defaults;
    _applyTheme(themeSaved);
    RealTime.instance.start();
    RealTime.instance.changes.listen((_) => notifyListeners());
    specialDays.changes.listen((_) => _invalidatePlan());
    specialDays.ensure();
    _secondTimer = Timer.periodic(const Duration(seconds: 1), (_) => clockTick.value++);
    _minuteTimer = Timer.periodic(const Duration(seconds: 60), (_) => notifyListeners());
    _ghSyncFromDb();
    await connectToDatabase(activeProject);
    dbs[activeProject]?.syncServerTime();
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _stateSub?.cancel();
    for (final s in _globalSubs) {
      s.cancel();
    }
    _minuteTimer?.cancel();
    _secondTimer?.cancel();
    super.dispose();
  }

  Future<void> connectToDatabase(String projectId) async {
    if (!dbs.containsKey(projectId)) return;
    activeProject = projectId;
    vpnEditorReset();
    _setThemeAccount(projectId);
    (await SharedPreferences.getInstance()).setString('activeProject', projectId);
    _queueSub?.cancel();
    _stateSub?.cancel();
    connecting = true;
    queueLoaded = false;
    _metaSeenKey = null;
    schedDraft.clear();
    varietyDraft.clear();
    uploadPage = 1;
    notifyListeners();
    _subscribeSchedules();
    final db = dbs[projectId]!;
    _stateSub = db.stream('uploadState').listen((v) {
      uploadState = v is Map ? UploadState(Map<String, dynamic>.from(v)) : null;
      _invalidatePlan();
    }, onError: (_) {});
    _queueSub = db.stream('wallpaperQueue', onConnection: (ok) {
      // v27.10: realtime link state (watchdog reconnects a dead socket and re-syncs the full snapshot)
      if (liveSync != ok && queueLoaded) {
        liveSync = ok;
        notifyListeners();
      }
    }).listen((v) {
      final data = v is Map ? v : const {};
      queueItems = data.entries.map((e) => QueueItem('${e.key}', e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{})).toList();
      queueLoaded = true;
      connecting = false;
      liveSync = true;
      _checkMetaAlerts();
      _invalidatePlan();
    }, onError: (e) {
      connecting = false;
      liveSync = false;
      showToast('Realtime connection failed: $e', 'err');
    });
  }

  void _subscribeSchedules() {
    if (_schedulesSubscribed) return;
    _schedulesSubscribed = true;
    for (final key in accountKeys) {
      final db = dbs[key]!;
      _globalSubs.add(db.stream('dashboardSettings/schedule').listen((v) {
        schedule.applySnapshot(key, v);
        _invalidatePlan();
      }, onError: (_) {}));
      _globalSubs.add(db.stream('dashboardSettings/metadataAlerts').listen((v) {
        metaAlerts[key] = v is Map ? MetaAlertReport(Map<String, dynamic>.from(v)) : null;
        notifyListeners();
      }, onError: (_) {}));
      _globalSubs.add(db.stream('dashboardSettings/variety').listen((v) {
        varietyCfg[key] = v is Map ? Map<String, dynamic>.from(v) : null;
        _invalidatePlan();   // v27.10: calendar follows mix mode
      }, onError: (_) {}));
      _globalSubs.add(db.stream('uploadState/varietyUsed').listen((v) {
        varietyUsed[key] = v is Map ? Map<String, dynamic>.from(v) : null;
        _invalidatePlan();
      }, onError: (_) {}));
      _globalSubs.add(db.stream('dashboardSettings/theme').listen((v) => _themeOnRemote(key, v), onError: (_) {}));
      _globalSubs.add(db.stream('dashboardSettings/gate').listen((v) {
        gateHealth[key] = v is Map ? GateHealth(Map<String, dynamic>.from(v)) : null;
        notifyListeners();
      }, onError: (_) {}));
      _globalSubs.add(db.stream(kVpnPath).listen((v) {
        vpnStates[key] = VpnState(v is Map ? Map<String, dynamic>.from(v) : null);
        vpnLive = true;
        notifyListeners();
      }, onError: (e) => ghLogLine('[VPN $key] realtime load failed: $e', 'err')));
    }
  }

  // ------------------------------------------------------------ plan cache
  PlannerResult? _plan;
  List<OverviewCard>? _overview;

  void _invalidatePlan() {
    _plan = null;
    _overview = null;
    notifyListeners();
  }

  PlannerResult get plan => _plan ??= buildPlan(
        queueItems: queueItems,
        uploadState: uploadState,
        schedule: schedule,
        activeProject: activeProject,
        specialDays: specialDays,
        variety: VarietyConfig.live(varietyCfg[activeProject]),   // v27.10: mix-mode aware calendar (read-only)
        varietyUsed: varietyUsed[activeProject],
      );

  List<OverviewCard> overview(int nowMs) => _overview ??= buildOverview(
        accountKeys: accountKeys,
        activeProject: activeProject,
        schedule: schedule,
        gateHealth: gateHealth,
        plan: plan,
        nowMs: nowMs,
      );

  void refreshOverview() {
    _overview = null;
    notifyListeners();
  }

  Map<String, String> get predictedDates => predictedDateMap(plan);

  // ------------------------------------------------------------ derived stats
  List<QueueItem> get queuedItems => queueItems.where((i) => i.isQueued).toList();
  List<QueueItem> get failedItems => queueItems.where((i) => i.isFailed).toList();
  List<QueueItem> get missingMetadataItems => queueItems.where((i) => i.isQueued && !i.hasRequiredMetadata).toList()
    ..sort((a, b) => (b.timeMs ?? 0).compareTo(a.timeMs ?? 0));

  QueueItem? itemById(String id) => queueItems.where((i) => i.id == id).firstOrNull;

  void _checkMetaAlerts() {
    final missing = missingMetadataItems;
    final ids = missing.map((i) => i.id).toList()..sort();
    final key = ids.join('|');
    if (_metaSeenKey != null && key.isNotEmpty && key != _metaSeenKey) {
      final prev = _metaSeenKey!.split('|').where((x) => x.isNotEmpty).toSet();
      final fresh = missing.where((i) => !prev.contains(i.id)).toList();
      if (fresh.isNotEmpty) {
        showToast('${fresh.length} file(s) without metadata - bot will skip them', 'error');
        onMetaNotification?.call(missing.length, fresh.map((i) => i.displayTitleOrId).toList());
        notifications.add('${fresh.length} file(s) without metadata will not be uploaded', 'warn', accountLabel(activeProject));
      }
    }
    _metaSeenKey = key;
  }

  /// Desktop notification hook (set by the UI layer).
  void Function(int count, List<String> names)? onMetaNotification;

  Future<void> enableMetaNotify() async {
    metaNotify = true;
    (await SharedPreferences.getInstance()).setString('zMetaNotify', '1');
    showToast('Desktop alerts enabled for missing metadata', 'ok');
    notifyListeners();
  }

  // ------------------------------------------------------------ toasts / notifications
  void showToast(String msg, [String kind = 'ok']) {
    final t = ToastMsg(msg, kind);
    toasts.add(t);
    final nk = (kind == 'err' || kind == 'error') ? 'err' : (kind == 'warn' ? 'warn' : 'ok');
    notifications.add(msg, nk, accountLabel(activeProject));
    notifyListeners();
    Timer(const Duration(milliseconds: 3400), () {
      toasts.removeWhere((x) => x.id == t.id);
      notifyListeners();
    });
  }

  int _lastFailedCount = -1;
  final int _bootAt = DateTime.now().millisecondsSinceEpoch;

  /// Mirrors the v27 "Failed uploads went up/down" notifications.
  void trackFailedCount(int n) {
    if (_lastFailedCount >= 0 && n != _lastFailedCount && DateTime.now().millisecondsSinceEpoch - _bootAt > 6000) {
      if (n > _lastFailedCount) {
        notifications.add('Failed uploads went up to $n', 'err', accountLabel(activeProject));
      } else {
        notifications.add('Failed uploads down to $n', 'ok', accountLabel(activeProject));
      }
    }
    _lastFailedCount = n;
  }

  // ------------------------------------------------------------ prefs setters
  Future<void> setPreviewDevice(String id) async {
    previewDeviceId = id;
    (await SharedPreferences.getInstance()).setString('previewDeviceId', id);
    notifyListeners();
  }

  Future<void> setPresSpeed(int ms) async {
    presSpeed = ms;
    (await SharedPreferences.getInstance()).setString('presSpeed', '$ms');
    notifyListeners();
  }

  Future<void> setSidebar(String s) async {
    sidebarState = s;
    (await SharedPreferences.getInstance()).setString('v27:sb', s);
    notifyListeners();
  }

  void touch() => notifyListeners();

  // ------------------------------------------------------------ theme engine bridge
  void _applyTheme(ThemeConfig c) {
    themeCurrent = ThemeConfig.sanitize(c.toJson());
    palette = ZedgePalette(themeCurrent);
    notifyListeners();
  }

  void _themeOnRemote(String acc, dynamic v) async {
    ThemeConfig? cfg;
    if (v is Map) {
      final m = Map<String, dynamic>.from(v);
      // v27.2: legacy yellow default ignored
      if (!(m['preset'] == 'sunflower' && (m['v271'] == null || m['v271'] == 0 || m['v271'] == false))) {
        cfg = ThemeConfig.sanitize(m);
      }
    }
    themeRemote[acc] = cfg;
    if (cfg != null) await ThemeStore.saveLocal(acc, cfg);
    if (acc == activeProject && !themeEditing) {
      themeSaved = cfg ?? await ThemeStore.loadLocal(acc) ?? ThemeConfig.defaults;
      _applyTheme(themeSaved);
    }
  }

  Future<void> _setThemeAccount(String acc) async {
    themeSaved = themeRemote[acc] ?? await ThemeStore.loadLocal(acc) ?? ThemeConfig.defaults;
    if (!themeEditing) _applyTheme(themeSaved);
  }

  /// Live preview while the Theme Studio drawer is open.
  void themePreview(ThemeConfig draft) {
    themeEditing = true;
    _applyTheme(draft);
  }

  void themeCloseDrawer({bool keep = false}) {
    themeEditing = false;
    if (!keep) _applyTheme(themeSaved);
  }

  /// `save(all)` in the drawer: local + Firebase (`dashboardSettings/theme`) for one or all accounts.
  Future<List<String>> themeSave(ThemeConfig draft, {required bool all}) async {
    final cfg = ThemeConfig.sanitize(draft.toJson());
    cfg.updatedAt = DateTime.now().millisecondsSinceEpoch;
    cfg.updatedBy = 'panel';
    cfg.v271 = 1;
    final accounts = all ? accountKeys : [activeProject];
    for (final a in accounts) {
      await ThemeStore.saveLocal(a, cfg);
      themeRemote[a] = cfg;
    }
    themeSaved = cfg;
    _applyTheme(cfg);
    await Future.wait(accounts.map((k) => dbs[k]!.set('dashboardSettings/theme', cfg.toJson())));
    return accounts;
  }

  // ------------------------------------------------------------ GitHub panel
  void ghLogLine(String msg, [String kind = '']) {
    final d = DateTime.now().toUtc().add(const Duration(hours: 6));
    String two(int n) => n.toString().padLeft(2, '0');
    ghLog.insert(0, GhLogLine('${two(d.hour)}:${two(d.minute)}:${two(d.second)}', msg, kind));
    if (ghLog.length > 200) ghLog.removeRange(200, ghLog.length);
    notifyListeners();
  }

  FirebaseRtdb get _ghDb => dbs['zedge1'] ?? dbs.values.first;

  void ghDbSync(Map<String, dynamic> patch) {
    _ghDb.update(kGhDbSettingsPath, patch).then((_) {
      ghLogLine('Synced to database: ${patch.keys.where((k) => !k.endsWith('UpdatedAt')).join(', ')}.', 'ok');
    }).catchError((err) {
      ghLogLine('DB sync failed: $err', 'err');
    });
  }

  Future<void> _ghSyncFromDb() async {
    Map<String, dynamic>? data;
    try {
      final v = await _ghDb.get(kGhDbSettingsPath);
      data = v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (err) {
      ghLogLine('DB settings load failed: $err', 'err');
      return;
    }
    final localCfg = await GhLocalStore.loadCfgRaw();
    final localSes = await GhLocalStore.loadSession();
    final localCfgTs = await GhLocalStore.loadCfgTs();
    final localSesTs = await GhLocalStore.loadSessionTs();
    final dbCfgTs = (data?['cfgUpdatedAt'] as num?)?.toInt() ?? 0;
    final dbSesTs = (data?['sessionUpdatedAt'] as num?)?.toInt() ?? 0;
    var applied = false;
    if (data != null && data['cfg'] is String && (data['cfg'] as String).isNotEmpty && dbCfgTs >= localCfgTs) {
      if (data['cfg'] != localCfg) applied = true;
      await GhLocalStore.saveCfgRaw(data['cfg'] as String, dbCfgTs);
    } else if (localCfg.isNotEmpty && localCfgTs > dbCfgTs) {
      ghDbSync({'cfg': localCfg, 'cfgUpdatedAt': localCfgTs});
    }
    if (data != null && data['session'] is String && dbSesTs >= localSesTs) {
      if (data['session'] != localSes) applied = true;
      await GhLocalStore.saveSession(data['session'] as String, dbSesTs);
    } else if (localSes.isNotEmpty && localSesTs > dbSesTs) {
      ghDbSync({'session': localSes, 'sessionUpdatedAt': localSesTs});
    }
    if (applied) {
      ghCfg = await GhLocalStore.loadCfg();
      ghSession = await GhLocalStore.loadSession();
      ghApplySavedSession();
      ghLogLine('Settings restored from database (cloud sync).', 'ok');
      notifyListeners();
    } else {
      ghApplySavedSession();
    }
  }

  void ghApplySavedSession() {
    if (ghSession.isEmpty) return;
    try {
      final info = ghSessionInfo(ghSession);
      ghSessionStatus = 'Saved: ${info.format}, ${info.cookies} cookies';
      ghSessionStatusCls = 'ok';
    } catch (_) {}
  }

  Future<void> ghSaveCfg(GhCfg cfg) async {
    ghCfg = cfg;
    final raw = cfg.toJson();
    final ts = DateTime.now().millisecondsSinceEpoch;
    await GhLocalStore.saveCfgRaw(raw, ts);
    ghLogLine('Connection settings saved.');
    ghDbSync({'cfg': raw, 'cfgUpdatedAt': ts});
    notifyListeners();
  }

  Future<dynamic> ghApi(String path, {String method = 'GET', Object? body}) {
    if (!ghCfg.ready) throw GhApiException('GitHub connection not configured (owner / repo / token)');
    return ghApiCall(token: ghCfg.token, path: path, method: method, body: body);
  }

  Future<void> ghTestConnection() async {
    ghConnStatus = 'Testing...';
    ghConnStatusCls = '';
    notifyListeners();
    try {
      final repo = await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}') as Map;
      final wfs = await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}/actions/workflows?per_page=50') as Map;
      ghConnStatus = 'Connected: ${repo['full_name']} (${repo['private'] == true ? 'private' : 'public'}) - ${wfs['total_count']} workflows';
      ghConnStatusCls = 'ok';
      ghLogLine('Connected to ${repo['full_name']} - default branch: ${repo['default_branch']}', 'ok');
      if (ghCfg.branch.trim().isEmpty) {
        ghCfg.branch = '${repo['default_branch']}';
        await ghSaveCfg(ghCfg);
      }
    } catch (e) {
      ghConnStatus = '$e';
      ghConnStatusCls = 'err';
      ghLogLine('Connection failed: $e', 'err');
    }
    notifyListeners();
  }

  Future<void> ghSaveSession(String rawIn) async {
    final raw = rawIn.trim();
    if (raw.isEmpty) {
      final clearTs = DateTime.now().millisecondsSinceEpoch;
      await GhLocalStore.saveSession('', clearTs);
      ghSession = '';
      ghSessionStatus = 'Session cleared';
      ghSessionStatusCls = '';
      ghLogLine('Gemini session cleared.');
      ghDbSync({'session': '', 'sessionUpdatedAt': clearTs});
      notifyListeners();
      return;
    }
    try {
      final info = ghSessionInfo(raw);
      final ts = DateTime.now().millisecondsSinceEpoch;
      await GhLocalStore.saveSession(raw, ts);
      ghSession = raw;
      ghDbSync({'session': raw, 'sessionUpdatedAt': ts});
      ghSessionStatus = 'Saved: ${info.format}, ${info.cookies} cookies, ${(raw.length / 1024).toStringAsFixed(1)} KB';
      ghSessionStatusCls = 'ok';
      ghLogLine('Gemini session saved (${info.format}, ${info.cookies} cookies).', 'ok');
      if (raw.length > 60000) {
        ghLogLine('Warning: session JSON is over 60 KB - workflow_dispatch may reject it. Export a cookies-only JSON instead.', 'err');
      }
    } catch (e) {
      ghSessionStatus = 'Invalid JSON';
      ghSessionStatusCls = 'err';
      ghLogLine('Session JSON invalid: $e', 'err');
    }
    notifyListeners();
  }

  Map<String, String> ghMaybeAttachSession(bool attach, Map<String, String> inputs) {
    if (attach) {
      if (ghSession.isNotEmpty) {
        inputs['gemini_session'] = ghSession;
      } else {
        ghLogLine('No saved session JSON - the run will fall back to the repo secret GEMINI_SESSION.');
      }
    }
    return inputs;
  }

  Future<void> ghTriggerWorkflow(String file, Map<String, String> inputs, String label) async {
    if (!ghCfg.ready) throw GhApiException('Configure owner / repo / token first (Connection card).');
    try {
      await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}/actions/workflows/${Uri.encodeComponent(file)}/dispatches',
          method: 'POST', body: {'ref': ghCfg.branch.isEmpty ? 'main' : ghCfg.branch, 'inputs': inputs});
      ghLogLine('$label triggered on ${ghCfg.branch.isEmpty ? 'main' : ghCfg.branch} - run appears in a few seconds.', 'ok');
      Timer(const Duration(seconds: 8), ghLoadRuns);
    } catch (e) {
      ghLogLine('$label trigger failed: $e', 'err');
      rethrow;
    }
  }

  Future<void> ghLoadRuns() async {
    ghRunsLoading = true;
    ghRunsError = null;
    notifyListeners();
    try {
      final data = await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}/actions/runs?per_page=20') as Map;
      ghRuns = ((data['workflow_runs'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      ghRunsError = '$e';
    }
    ghRunsLoading = false;
    notifyListeners();
  }

  Future<void> ghDeleteRun(Map<String, dynamic> run) async {
    try {
      await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}/actions/runs/${run['id']}', method: 'DELETE');
      ghLogLine('Deleted run #${run['run_number']}.', 'ok');
      ghRuns.removeWhere((r) => r['id'] == run['id']);
      notifyListeners();
    } catch (e) {
      ghLogLine('Run delete failed: $e', 'err');
    }
  }

  bool ghCleaning = false;
  Future<void> ghCleanRuns() async {
    if (!ghCfg.ready) throw GhApiException('Configure owner / repo / token first.');
    ghCleaning = true;
    notifyListeners();
    var deleted = 0, failed = 0;
    ghLogLine('Cleaning completed run history...');
    try {
      for (var round = 0; round < 30; round++) {
        final data = await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}/actions/runs?status=completed&per_page=100&page=1') as Map;
        final runs = (data['workflow_runs'] as List?) ?? const [];
        if (runs.isEmpty) break;
        var roundDeleted = 0;
        for (final run in runs) {
          try {
            await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}/actions/runs/${(run as Map)['id']}', method: 'DELETE');
            deleted++;
            roundDeleted++;
            if (deleted % 10 == 0) ghLogLine('... $deleted runs deleted so far');
          } catch (_) {
            failed++;
          }
        }
        if (roundDeleted == 0) break;
      }
      ghLogLine('Run history clean complete: $deleted deleted${failed > 0 ? ', $failed failed' : ''}.', 'ok');
    } catch (e) {
      ghLogLine('Clean stopped: $e ($deleted deleted)', 'err');
    } finally {
      ghCleaning = false;
      notifyListeners();
      ghLoadRuns();
    }
  }

  Future<void> ghListPath(String path) async {
    ghFilesLoading = true;
    ghFilesError = null;
    notifyListeners();
    try {
      final data = await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}/contents/${path.isNotEmpty ? ghEncodePath(path) : ''}?ref=${Uri.encodeComponent(ghCfg.branch.isEmpty ? 'main' : ghCfg.branch)}');
      final items = (data is List ? data : [data]).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      ghCurrentPath = path;
      items.sort((a, b) => a['type'] == b['type'] ? '${a['name']}'.compareTo('${b['name']}') : (a['type'] == 'dir' ? -1 : 1));
      ghFiles = items;
    } catch (e) {
      ghFilesError = '$e';
    }
    ghFilesLoading = false;
    notifyListeners();
  }

  Future<void> ghDeleteFile(Map<String, dynamic> item) async {
    try {
      await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}/contents/${ghEncodePath('${item['path']}')}', method: 'DELETE', body: {
        'message': 'chore: delete ${item['path']} (dashboard repo clean)',
        'sha': item['sha'],
        'branch': ghCfg.branch.isEmpty ? 'main' : ghCfg.branch,
      });
      ghLogLine('Deleted ${item['path']} from repo.', 'ok');
      ghListPath(ghCurrentPath);
    } catch (e) {
      ghLogLine('File delete failed: $e', 'err');
    }
  }

  Future<void> ghPushFiles(List<(String name, int size, Future<List<int>> Function() read)> files) async {
    if (!ghCfg.ready) throw GhApiException('Configure owner / repo / token first.');
    for (final f in files) {
      final (name, size, read) = f;
      try {
        if (size > 25 * 1024 * 1024) {
          ghLogLine('Skipped $name - over 25 MB (too large for the contents API).', 'err');
          continue;
        }
        final target = '${ghCurrentPath.isNotEmpty ? '$ghCurrentPath/' : ''}$name';
        ghLogLine('Pushing $target (${(size / 1024).toStringAsFixed(1)} KB)...');
        final content = base64Encode(await read());
        String? sha;
        try {
          final existing = await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}/contents/${ghEncodePath(target)}?ref=${Uri.encodeComponent(ghCfg.branch.isEmpty ? 'main' : ghCfg.branch)}');
          if (existing is Map && existing['sha'] != null) sha = '${existing['sha']}';
        } catch (_) {/* file does not exist yet - create */}
        final body = <String, dynamic>{
          'message': '${sha != null ? 'update: ' : 'add: '}$target (pushed from dashboard)',
          'content': content,
          'branch': ghCfg.branch.isEmpty ? 'main' : ghCfg.branch,
          if (sha != null) 'sha': sha,
        };
        await ghApi('/repos/${ghCfg.owner}/${ghCfg.repo}/contents/${ghEncodePath(target)}', method: 'PUT', body: body);
        ghLogLine('Pushed $target${sha != null ? ' (updated existing)' : ' (new file)'}.', 'ok');
      } catch (e) {
        ghLogLine('Push failed for $name: $e', 'err');
      }
    }
    ghListPath(ghCurrentPath);
  }

  // ------------------------------------------------------------ VPN panel
  String get vpnCurrent => activeProject;
  VpnState get vpnState => vpnStates[vpnCurrent] ?? VpnState(null);
  final Map<String, Map<String, dynamic>> vpnGhLocal = {};

  /// Editor state (`vpnFiles`, `vpnAuthForced`, edit id).
  final Map<String, String> vpnFiles = {};
  bool vpnAuthForced = false;
  String vpnEditId = '';
  int vpnEditorVersion = 0; // bump to reset editor widgets

  void vpnEditorReset() {
    vpnFiles.clear();
    vpnAuthForced = false;
    vpnEditId = '';
    vpnEditorVersion++;
  }

  void vpnLog(String msg, [String kind = '']) => ghLogLine('[VPN $vpnCurrent] $msg', kind);

  Future<VpnGhCfg> vpnGhCfg([String? key]) async {
    key ??= vpnCurrent;
    final st = vpnStates[key] ?? VpnState(null);
    final own = st.github;
    final local = vpnGhLocal[key] ?? await GhLocalStore.loadVpnGh(key);
    if (local != null) vpnGhLocal[key] = local;
    final src = <String, dynamic>{...?local, ...?own};
    if ((src['token'] ?? '').toString().isEmpty && local != null && (local['token'] ?? '').toString().isNotEmpty) src['token'] = local['token'];
    return VpnGhCfg(
      owner: '${src['owner'] ?? ''}',
      repo: '${src['repo'] ?? ''}',
      branch: '${src['branch'] ?? ''}'.isEmpty ? 'main' : '${src['branch']}',
      token: '${src['token'] ?? ''}',
      workflow: '${src['workflow'] ?? ''}'.isEmpty ? '$key.yml' : '${src['workflow']}',
    );
  }

  Future<dynamic> vpnGhApi(String key, String path, {String method = 'GET', Object? body}) async {
    final cfg = await vpnGhCfg(key);
    if (!cfg.ready) throw GhApiException('GitHub connection for ${key.toUpperCase()} is incomplete (owner / repo / token / workflow file)');
    return ghApiCall(token: cfg.token, path: path, method: method, body: body);
  }

  FirebaseRtdb vpnDb(String key) => dbs[key] ?? dbs['zedge1'] ?? dbs.values.first;

  Future<void> vpnConnSave(Map<String, dynamic> rec) async {
    rec['useGlobal'] = false;
    rec['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    vpnGhLocal[vpnCurrent] = rec;
    await GhLocalStore.saveVpnGh(vpnCurrent, rec);
    await vpnDb(vpnCurrent).update(kVpnPath, {'github': rec});
    vpnLog('GitHub connection saved for ${vpnCurrent.toUpperCase()}: ${rec['owner']}/${rec['repo']} @ ${rec['workflow']}.', 'ok');
    showToast('Connection saved for ${vpnCurrent.toUpperCase()}');
  }

  Future<void> vpnSetActive(String id, {bool silent = false}) async {
    final p = vpnState.profiles[id];
    if (p == null) return;
    try {
      await vpnDb(vpnCurrent).update(kVpnPath, {'activeProfileId': id, 'mode': p['type'], 'updatedAt': DateTime.now().millisecondsSinceEpoch});
      vpnLog('"${p['name']}" is now active - real runs use ${p['type']}.', 'ok');
      if (!silent) showToast('${p['name']} active');
    } catch (e) {
      vpnLog('Set active failed: $e', 'err');
    }
  }

  Future<void> vpnDeleteProfile(String id) async {
    final p = vpnState.profiles[id];
    if (p == null) return;
    try {
      await vpnDb(vpnCurrent).remove('$kVpnPath/profiles/$id');
      if (vpnState.activeProfileId == id) {
        await vpnDb(vpnCurrent).update(kVpnPath, {'activeProfileId': '', 'mode': 'none', 'updatedAt': DateTime.now().millisecondsSinceEpoch});
      }
      if (vpnEditId == id) {
        vpnEditorReset();
        notifyListeners();
      }
      vpnLog('Profile "${p['name']}" deleted.', 'ok');
    } catch (e) {
      vpnLog('Delete failed: $e', 'err');
    }
  }

  Future<void> vpnCopyProfile(String id) async {
    final p = vpnState.profiles[id];
    if (p == null) return;
    try {
      await Future.wait(accountKeys.where((k) => k != vpnCurrent).map((k) =>
          vpnDb(k).update('$kVpnPath/profiles/$id', {...p, 'updatedAt': DateTime.now().millisecondsSinceEpoch})));
      vpnLog('Profile "${p['name']}" copied to all accounts.', 'ok');
      showToast('Copied to all accounts');
    } catch (e) {
      vpnLog('Copy failed: $e', 'err');
    }
  }

  Future<void> vpnSaveMode(String mode, bool keepProxy) async {
    final st = vpnState;
    final act = st.activeProfile;
    if (mode != 'none' && act == null) {
      showToast('Set a profile active first', 'err');
      return;
    }
    if (mode != 'none' && act!['type'] != mode) {
      showToast('Active profile "${act['name']}" is ${act['type']} - pick the matching mode', 'err');
      return;
    }
    try {
      await vpnDb(vpnCurrent).update(kVpnPath, {'mode': mode, 'keepProxy': keepProxy, 'updatedAt': DateTime.now().millisecondsSinceEpoch});
      vpnLog('Mode -> ${mode.toUpperCase()}${keepProxy ? ' (+ proxy chain)' : ''}.', 'ok');
      showToast('Mode saved');
    } catch (e) {
      vpnLog('Save mode failed: $e', 'err');
    }
  }

  Future<void> vpnSaveProfile(Map<String, dynamic> p, {required bool copyAll}) async {
    final targets = copyAll ? accountKeys : [vpnCurrent];
    await Future.wait(targets.map((k) => vpnDb(k).update('$kVpnPath/profiles/${p['id']}', p)));
    vpnLog('Profile "${p['name']}" saved to ${targets.map((k) => k.toUpperCase()).join(', ')}.', 'ok');
    showToast('Saved ${p['name']}');
    final st = vpnState;
    if (st.profiles.isEmpty || st.activeProfileId.isEmpty) await vpnSetActive('${p['id']}', silent: true);
  }

  Timer? _vpnRunPollTimer;
  bool vpnTestBusy = false;

  /// `vpnRunTest(profileId, profileName)` - returns false when nothing was dispatched.
  Future<void> vpnRunTest(String? profileId, {required Future<bool> Function(String) confirm}) async {
    final key = vpnCurrent;
    final st = vpnState;
    final pid = (profileId == null || profileId.isEmpty) ? st.activeProfileId : profileId;
    final p = st.profiles[pid];
    if (p == null) {
      showToast('No profile selected - save one or click Test on a profile', 'err');
      return;
    }
    final cfg = await vpnGhCfg(key);
    if (!cfg.ready) {
      showToast('GitHub connection for ${key.toUpperCase()} is missing', 'err');
      return;
    }
    final lt = st.lastTest;
    if (lt != null && (lt['status'] == 'queued' || lt['status'] == 'running') && DateTime.now().millisecondsSinceEpoch - ((lt['at'] as num?)?.toInt() ?? 0) < 12 * 60 * 1000) {
      if (!await confirm('A test is already ${lt['status']} for this account. Start another one anyway?')) return;
    }
    vpnTestBusy = true;
    notifyListeners();
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      await vpnDb(key).update(kVpnPath, {
        'lastTest': {
          'status': 'queued',
          'stage': 'dispatch',
          'message': 'Workflow dispatched - waiting for the GitHub runner...',
          'profileId': pid,
          'profileName': p['name'],
          'type': p['type'],
          'at': startedAt,
          'account': key,
          'repo': '${cfg.owner}/${cfg.repo}',
          'workflow': cfg.workflow,
          'runUrl': '',
          'ipBefore': null,
          'ipAfter': null,
          'zedgeOk': null,
        }
      });
      await vpnGhApi(key, '/repos/${cfg.owner}/${cfg.repo}/actions/workflows/${Uri.encodeComponent(cfg.workflow)}/dispatches',
          method: 'POST', body: {'ref': cfg.branch, 'inputs': {'run_mode': 'vpn_test', 'vpn_profile': pid, 'os': 'windows-latest'}});
      vpnLog('Test dispatched -> ${cfg.owner}/${cfg.repo} ${cfg.workflow} (profile "${p['name']}"). Live status below.', 'ok');
      showToast('Test started for ${key.toUpperCase()}');
      _vpnFindRun(key, cfg, startedAt, 0);
    } catch (e) {
      vpnLog('Dispatch failed: $e', 'err');
      showToast('$e', 'err');
      try {
        await vpnDb(key).update('$kVpnPath/lastTest', {'status': 'fail', 'stage': 'dispatch', 'message': 'Dispatch failed: $e', 'at': DateTime.now().millisecondsSinceEpoch});
      } catch (_) {}
    } finally {
      vpnTestBusy = false;
      notifyListeners();
    }
  }

  void _vpnFindRun(String key, VpnGhCfg cfg, int startedAt, int attempt) {
    _vpnRunPollTimer?.cancel();
    if (attempt > 6) return;
    _vpnRunPollTimer = Timer(Duration(milliseconds: attempt == 0 ? 5000 : 8000), () async {
      try {
        final cur = vpnStates[key]?.lastTest ?? const {};
        if ((cur['runUrl'] ?? '').toString().isNotEmpty || cur['at'] != startedAt) return;
        final r = await vpnGhApi(key, '/repos/${cfg.owner}/${cfg.repo}/actions/workflows/${Uri.encodeComponent(cfg.workflow)}/runs?event=workflow_dispatch&per_page=3') as Map;
        final runs = (r['workflow_runs'] as List?) ?? const [];
        for (final x in runs) {
          final created = DateTime.tryParse('${(x as Map)['created_at']}')?.millisecondsSinceEpoch ?? 0;
          if (created >= startedAt - 20000) {
            await vpnDb(key).update('$kVpnPath/lastTest', {'runUrl': x['html_url'], 'runId': '${x['id']}', 'runner': x['status']});
            return;
          }
        }
      } catch (_) {}
      _vpnFindRun(key, cfg, startedAt, attempt + 1);
    });
  }
}
