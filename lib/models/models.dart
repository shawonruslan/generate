/// Typed models for every Team Drive worker API object.
/// All `fromJson` constructors tolerate missing keys — the worker omits
/// fields based on role (admin vs member) and context.

class SessionUser {
  final String username;
  final String role; // "admin" | "member"
  final String token;
  SessionUser({required this.username, required this.role, required this.token});
  bool get isAdmin => role == 'admin';
}

// ---------------- Drive ----------------

class DriveFolder {
  final String id;
  final String name;
  final String parent;
  final int createdAt;
  DriveFolder({required this.id, required this.name, required this.parent, required this.createdAt});
  factory DriveFolder.fromJson(String id, Map<String, dynamic> j) => DriveFolder(
        id: id,
        name: (j['name'] ?? 'Untitled').toString(),
        parent: (j['parent'] ?? 'root').toString(),
        createdAt: (j['createdAt'] ?? 0) as int,
      );
}

class DriveFile {
  final String id;
  final String name;
  final String folder;
  final int size;
  final String type;
  final int uploadedAt;
  final String uploadedBy;
  final int ver;
  final int vc;
  final String? url; // absent for locked files (members)
  final Map<String, dynamic>? locked;
  final String? note;
  final int shares;
  DriveFile({
    required this.id, required this.name, required this.folder, required this.size,
    required this.type, required this.uploadedAt, required this.uploadedBy,
    required this.ver, required this.vc, this.url, this.locked, this.note, this.shares = 0,
  });
  bool get isLocked => locked != null;
  factory DriveFile.fromJson(String id, Map<String, dynamic> j) => DriveFile(
        id: id,
        name: (j['name'] ?? 'file').toString(),
        folder: (j['folder'] ?? 'root').toString(),
        size: (j['size'] ?? 0) as int,
        type: (j['type'] ?? 'application/octet-stream').toString(),
        uploadedAt: (j['uploadedAt'] ?? 0) as int,
        uploadedBy: (j['uploadedBy'] ?? 'admin').toString(),
        ver: (j['ver'] ?? 1) as int,
        vc: (j['vc'] ?? 0) as int,
        url: j['url']?.toString(),
        locked: j['locked'] is Map ? Map<String, dynamic>.from(j['locked']) : null,
        note: j['note']?.toString(),
        shares: (j['shares'] ?? 0) as int,
      );
}

class DriveStats {
  final int used;
  final int count;
  final int limit;
  final int totalUsed;
  final int? pools;
  final int quota; // members: personal quota bytes; -1 = unlimited
  DriveStats({required this.used, required this.count, required this.limit,
    required this.totalUsed, this.pools, required this.quota});
  factory DriveStats.fromJson(Map<String, dynamic> j) => DriveStats(
        used: (j['used'] ?? 0) as int,
        count: (j['count'] ?? 0) as int,
        limit: (j['limit'] ?? 0) as int,
        totalUsed: (j['totalUsed'] ?? j['used'] ?? 0) as int,
        pools: j['pools'] as int?,
        quota: (j['quota'] ?? -1) as int,
      );
}

class Announcement {
  final String id;
  final String text;
  final String type; // info | success | warning | urgent
  final int createdAt;
  final int? exp;
  final bool? active;
  Announcement({required this.id, required this.text, required this.type,
    required this.createdAt, this.exp, this.active});
  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'].toString(),
        text: (j['text'] ?? '').toString(),
        type: (j['type'] ?? 'info').toString(),
        createdAt: (j['createdAt'] ?? 0) as int,
        exp: j['exp'] as int?,
        active: j['active'] as bool?,
      );
}

class DriveData {
  final Map<String, DriveFolder> folders;
  final Map<String, DriveFile> files;
  final DriveStats stats;
  final int linkExpires;
  final int maxVersions;
  final List<Announcement> announcements;
  final Map<String, String> avatars;
  final int ticketsOpen;
  final int ticketsUnread;
  DriveData({
    required this.folders, required this.files, required this.stats,
    required this.linkExpires, required this.maxVersions,
    required this.announcements, required this.avatars,
    required this.ticketsOpen, required this.ticketsUnread,
  });
  factory DriveData.fromJson(Map<String, dynamic> j) {
    final folders = <String, DriveFolder>{};
    (j['folders'] as Map<String, dynamic>? ?? {}).forEach(
        (k, v) => folders[k] = DriveFolder.fromJson(k, Map<String, dynamic>.from(v)));
    final files = <String, DriveFile>{};
    (j['files'] as Map<String, dynamic>? ?? {}).forEach(
        (k, v) => files[k] = DriveFile.fromJson(k, Map<String, dynamic>.from(v)));
    final t = j['tickets'] as Map<String, dynamic>?;
    return DriveData(
      folders: folders,
      files: files,
      stats: DriveStats.fromJson(Map<String, dynamic>.from(j['stats'] ?? {})),
      linkExpires: (j['linkExpires'] ?? 0) as int,
      maxVersions: (j['maxVersions'] ?? 10) as int,
      announcements: ((j['announcements'] as List?) ?? [])
          .map((e) => Announcement.fromJson(Map<String, dynamic>.from(e))).toList(),
      avatars: ((j['avatars'] as Map<String, dynamic>?) ?? {}).map((k, v) => MapEntry(k, v.toString())),
      ticketsOpen: (t?['open'] ?? 0) as int,
      ticketsUnread: (t?['unread'] ?? 0) as int,
    );
  }
}

class FileVersion {
  final int ver;
  final int size;
  final String type;
  final int uploadedAt;
  final String uploadedBy;
  final String? note;
  final bool current;
  final String? url;
  FileVersion({required this.ver, required this.size, required this.type,
    required this.uploadedAt, required this.uploadedBy, this.note,
    required this.current, this.url});
  factory FileVersion.fromJson(Map<String, dynamic> j) => FileVersion(
        ver: (j['ver'] ?? 0) as int,
        size: (j['size'] ?? 0) as int,
        type: (j['type'] ?? '').toString(),
        uploadedAt: (j['uploadedAt'] ?? 0) as int,
        uploadedBy: (j['uploadedBy'] ?? '').toString(),
        note: j['note']?.toString(),
        current: (j['current'] ?? false) as bool,
        url: j['url']?.toString(),
      );
}

// ---------------- Group feed ----------------

class GroupFile {
  final String key;
  final String? st;
  final String name;
  final int size;
  final String type;
  final String? url;
  GroupFile({required this.key, this.st, required this.name, required this.size,
    required this.type, this.url});
  factory GroupFile.fromJson(Map<String, dynamic> j) => GroupFile(
        key: j['key'].toString(),
        st: j['st']?.toString(),
        name: (j['name'] ?? 'file').toString(),
        size: (j['size'] ?? 0) as int,
        type: (j['type'] ?? 'application/octet-stream').toString(),
        url: j['url']?.toString(),
      );
  Map<String, dynamic> toJson() => {
        'key': key, if (st != null) 'st': st, 'name': name, 'size': size, 'type': type,
      };
}

class GroupPost {
  final String id;
  final String by;
  final String role;
  final String caption;
  final bool pinned;
  final int pinnedAt;
  final int ts;
  final Map<String, int> seen; // username -> first-seen ms
  final GroupFile? file;
  GroupPost({required this.id, required this.by, required this.role, required this.caption,
    required this.pinned, required this.pinnedAt, required this.ts,
    required this.seen, this.file});
  factory GroupPost.fromJson(Map<String, dynamic> j) => GroupPost(
        id: j['id'].toString(),
        by: (j['by'] ?? '').toString(),
        role: (j['role'] ?? 'member').toString(),
        caption: (j['caption'] ?? '').toString(),
        pinned: (j['pinned'] ?? false) as bool,
        pinnedAt: (j['pinnedAt'] ?? 0) as int,
        ts: (j['ts'] ?? 0) as int,
        seen: ((j['seen'] as Map<String, dynamic>?) ?? {}).map((k, v) => MapEntry(k, (v as num).toInt())),
        file: j['file'] is Map ? GroupFile.fromJson(Map<String, dynamic>.from(j['file'])) : null,
      );
}

class GroupFeed {
  final List<GroupPost> posts;
  final Map<String, String> avatars;
  GroupFeed({required this.posts, required this.avatars});
  factory GroupFeed.fromJson(Map<String, dynamic> j) => GroupFeed(
        posts: ((j['posts'] as List?) ?? [])
            .map((e) => GroupPost.fromJson(Map<String, dynamic>.from(e))).toList(),
        avatars: ((j['avatars'] as Map<String, dynamic>?) ?? {}).map((k, v) => MapEntry(k, v.toString())),
      );
}

/// Descriptor returned by POST /api/group/upload — passed to POST /api/group.
class GroupUploadDescriptor extends GroupFile {
  final String storage;
  GroupUploadDescriptor({required super.key, super.st, required super.name,
    required super.size, required super.type, required this.storage});
  factory GroupUploadDescriptor.fromJson(Map<String, dynamic> j) => GroupUploadDescriptor(
        key: j['key'].toString(),
        st: j['st']?.toString(),
        name: (j['name'] ?? 'file').toString(),
        size: (j['size'] ?? 0) as int,
        type: (j['type'] ?? 'application/octet-stream').toString(),
        storage: (j['storage'] ?? '').toString(),
      );
}

// ---------------- Notes ----------------

class NoteItem {
  String t;
  bool d;
  NoteItem({required this.t, required this.d});
  factory NoteItem.fromJson(Map<String, dynamic> j) =>
      NoteItem(t: (j['t'] ?? '').toString(), d: (j['d'] ?? false) as bool);
  Map<String, dynamic> toJson() => {'t': t, 'd': d};
}

class Note {
  String? id;
  String title;
  String body;
  List<NoteItem>? items;
  String? color;
  bool pinned;
  bool archived;
  List<String> labels;
  Note({this.id, this.title = '', this.body = '', this.items, this.color,
    this.pinned = false, this.archived = false, this.labels = const []});
  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id']?.toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        items: (j['items'] as List?)?.map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e))).toList(),
        color: j['color']?.toString(),
        pinned: (j['pinned'] ?? false) as bool,
        archived: (j['archived'] ?? false) as bool,
        labels: ((j['labels'] as List?) ?? []).map((e) => e.toString()).toList(),
      );
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'title': title, 'body': body,
        if (items != null) 'items': items!.map((e) => e.toJson()).toList(),
        if (color != null) 'color': color,
        'pinned': pinned, 'archived': archived, 'labels': labels,
      };
}

// ---------------- Tickets ----------------

class TicketMessage {
  final String by;
  final String text;
  final int at;
  TicketMessage({required this.by, required this.text, required this.at});
  factory TicketMessage.fromJson(Map<String, dynamic> j) => TicketMessage(
        by: (j['by'] ?? '').toString(),
        text: (j['text'] ?? '').toString(),
        at: (j['at'] ?? 0) as int,
      );
}

class Ticket {
  final String id;
  final String user;
  final String subject;
  final String cat;
  final String pri;
  final String status; // open | closed
  final int createdAt;
  final int updatedAt;
  final int unread; // worker-computed unread count for the viewer
  final List<TicketMessage> msgs;
  Ticket({required this.id, required this.user, required this.subject, required this.cat,
    required this.pri, required this.status, required this.createdAt,
    required this.updatedAt, this.unread = 0, required this.msgs});
  bool get isOpen => status == 'open';
  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        id: j['id'].toString(),
        user: (j['user'] ?? '').toString(),
        subject: (j['subject'] ?? '').toString(),
        cat: (j['cat'] ?? '').toString(),
        pri: (j['pri'] ?? '').toString(),
        status: (j['status'] ?? 'open').toString(),
        createdAt: (j['createdAt'] ?? 0) as int,
        updatedAt: (j['updatedAt'] ?? 0) as int,
        unread: (j['unread'] ?? 0) as int,
        msgs: ((j['msgs'] as List?) ?? [])
            .map((e) => TicketMessage.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}

// ---------------- Database / records ----------------

class RecordColumn {
  final String k;
  final String name;
  final bool match;
  RecordColumn({required this.k, required this.name, required this.match});
  factory RecordColumn.fromJson(Map<String, dynamic> j) => RecordColumn(
        k: j['k'].toString(),
        name: (j['name'] ?? j['k']).toString(),
        match: (j['match'] ?? false) as bool,
      );
  Map<String, dynamic> toJson() => {'k': k, 'name': name, 'match': match};
}

class RecordList {
  final String id;
  final String name;
  final List<RecordColumn> cols;
  final bool memberAdd;
  RecordList({required this.id, required this.name, required this.cols, this.memberAdd = false});
  factory RecordList.fromJson(Map<String, dynamic> j) => RecordList(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        cols: ((j['cols'] as List?) ?? [])
            .map((e) => RecordColumn.fromJson(Map<String, dynamic>.from(e))).toList(),
        memberAdd: (j['memberAdd'] ?? false) as bool,
      );
}

class RecordRow {
  final String rid;
  final String owner;
  final Map<String, dynamic> cells;
  final int at;
  final String by;
  final bool canEdit;
  RecordRow({required this.rid, required this.owner, required this.cells,
    required this.at, required this.by, this.canEdit = true});
  factory RecordRow.fromJson(String rid, Map<String, dynamic> j) => RecordRow(
        rid: rid,
        owner: (j['owner'] ?? '').toString(),
        cells: Map<String, dynamic>.from(j['cells'] ?? {}),
        at: (j['at'] ?? 0) as int,
        by: (j['by'] ?? '').toString(),
        canEdit: (j['canEdit'] ?? true) as bool,
      );
  /// Worker returns rows as a list with `id` inside each object.
  factory RecordRow.fromJsonMap(Map<String, dynamic> j) =>
      RecordRow.fromJson(j['id']?.toString() ?? '', j);
}

class RecordCheckMatch {
  final String list;
  final String listName;
  final String col;
  final String colName;
  final String rid;
  final String owner;
  final bool own;
  final int at;
  RecordCheckMatch({required this.list, required this.listName, required this.col,
    required this.colName, required this.rid, required this.owner,
    required this.own, required this.at});
  factory RecordCheckMatch.fromJson(Map<String, dynamic> j) => RecordCheckMatch(
        list: j['list'].toString(),
        listName: (j['listName'] ?? '').toString(),
        col: j['col'].toString(),
        colName: (j['colName'] ?? '').toString(),
        rid: j['rid'].toString(),
        owner: (j['owner'] ?? '').toString(),
        own: (j['own'] ?? false) as bool,
        at: (j['at'] ?? 0) as int,
      );
}

class RecordCheckResult {
  final String value;
  final List<RecordCheckMatch> matches;
  final bool more;
  RecordCheckResult({required this.value, required this.matches, this.more = false});
  factory RecordCheckResult.fromJson(Map<String, dynamic> j) => RecordCheckResult(
        value: (j['value'] ?? '').toString(),
        matches: ((j['matches'] as List?) ?? [])
            .map((e) => RecordCheckMatch.fromJson(Map<String, dynamic>.from(e))).toList(),
        more: (j['more'] ?? false) as bool,
      );
}

// ---------------- Diary ----------------

class DiarySticker {
  final String id;
  final double x, y, w, a, r;
  final String? k;
  final String? url;
  DiarySticker({required this.id, required this.x, required this.y, required this.w,
    required this.a, required this.r, this.k, this.url});
  factory DiarySticker.fromJson(Map<String, dynamic> j) => DiarySticker(
        id: (j['id'] ?? '').toString(),
        x: (j['x'] ?? 0).toDouble(),
        y: (j['y'] ?? 0).toDouble(),
        w: (j['w'] ?? 80).toDouble(),
        a: (j['a'] ?? 1).toDouble(),
        r: (j['r'] ?? 0).toDouble(),
        k: j['k']?.toString(),
        url: j['u']?.toString(),
      );
  Map<String, dynamic> toJson() => {
        'id': id, 'x': x, 'y': y, 'w': w, 'a': a, 'r': r,
        if (k != null) 'k': k, if (url != null) 'u': url,
      };
}

class DiaryEntry {
  final String date; // YYYY-MM-DD
  String text;
  String mood;
  int at;
  String? html;
  String? draw;
  List<DiarySticker> stickers;
  DiaryEntry({required this.date, this.text = '', this.mood = '', this.at = 0,
    this.html, this.draw, List<DiarySticker>? stickers})
      : stickers = stickers ?? [];
  factory DiaryEntry.fromJson(String date, Map<String, dynamic> j) => DiaryEntry(
        date: date,
        text: (j['text'] ?? '').toString(),
        mood: (j['mood'] ?? '').toString(),
        at: (j['at'] ?? 0) as int,
        html: j['html']?.toString(),
        draw: j['draw']?.toString(),
        stickers: ((j['stk'] as List?) ?? [])
            .map((e) => DiarySticker.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
  Map<String, dynamic> toJson() => {
        'date': date, 'text': text, 'mood': mood,
        if (html != null) 'html': html,
        if (draw != null) 'draw': draw,
        if (stickers.isNotEmpty) 'stk': stickers.map((s) => s.toJson()).toList(),
      };
}

class DiaryYear {
  final int year;
  final Map<String, DiaryEntry> entries; // date -> entry
  final Map<String, int> years; // year -> entry count
  DiaryYear({required this.year, required this.entries, required this.years});
  factory DiaryYear.fromJson(Map<String, dynamic> j) => DiaryYear(
        year: (j['year'] ?? 0) as int,
        entries: ((j['entries'] as Map<String, dynamic>?) ?? {}).map(
            (k, v) => MapEntry(k, DiaryEntry.fromJson(k, Map<String, dynamic>.from(v)))),
        years: ((j['years'] as Map<String, dynamic>?) ?? {})
            .map((k, v) => MapEntry(k, (v as num).toInt())),
      );
}

class DiaryImage {
  final String id;
  final String url;
  DiaryImage({required this.id, required this.url});
  factory DiaryImage.fromJson(Map<String, dynamic> j) =>
      DiaryImage(id: j['id'].toString(), url: (j['url'] ?? '').toString());
}

// ---------------- Members / storage / shares ----------------

class TeamMember {
  final String username;
  final int createdAt;
  final int lastLogin;
  final bool disabled;
  final String folder;
  final int files;
  final int size;
  final double? quotaGB;
  final int quota; // bytes, -1 = unlimited
  final String pool;
  TeamMember({required this.username, required this.createdAt, required this.lastLogin,
    required this.disabled, required this.folder, required this.files, required this.size,
    this.quotaGB, required this.quota, required this.pool});
  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        username: j['username'].toString(),
        createdAt: (j['createdAt'] ?? 0) as int,
        lastLogin: (j['lastLogin'] ?? 0) as int,
        disabled: (j['disabled'] ?? false) as bool,
        folder: (j['folder'] ?? '').toString(),
        files: (j['files'] ?? 0) as int,
        size: (j['size'] ?? 0) as int,
        quotaGB: (j['quotaGB'] as num?)?.toDouble(),
        quota: (j['quota'] ?? -1) as int,
        pool: (j['pool'] ?? '').toString(),
      );
}

class StoragePool {
  final String id;
  final String name;
  final String kind;
  final String bucket;
  final int used;
  final int limit;
  final int files;
  final bool readOnly;
  final bool ok;
  final String? error;
  StoragePool({required this.id, required this.name, required this.kind, required this.bucket,
    required this.used, required this.limit, required this.files,
    required this.readOnly, required this.ok, this.error});
  factory StoragePool.fromJson(Map<String, dynamic> j) => StoragePool(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        kind: (j['kind'] ?? '').toString(),
        bucket: (j['bucket'] ?? '').toString(),
        used: (j['used'] ?? 0) as int,
        limit: (j['limit'] ?? 0) as int,
        files: (j['files'] ?? 0) as int,
        readOnly: (j['readOnly'] ?? false) as bool,
        ok: (j['ok'] ?? true) as bool,
        error: j['error']?.toString(),
      );
}

class ShareLink {
  final String id;
  final String fileId;
  final String fileName;
  final int size;
  final int? exp; // ms epoch, null = never
  final int? max; // max downloads, null = unlimited
  final int dl; // downloads so far
  final int createdAt;
  final bool hasPw;
  final bool disabled;
  final String? url; // public /s/<id> URL (present in list responses)
  ShareLink({required this.id, required this.fileId, required this.fileName,
    this.size = 0, this.exp, this.max, required this.dl, required this.createdAt,
    required this.hasPw, this.disabled = false, this.url});
  factory ShareLink.fromJson(Map<String, dynamic> j) => ShareLink(
        id: j['id'].toString(),
        fileId: (j['fileId'] ?? '').toString(),
        fileName: (j['fileName'] ?? '').toString(),
        size: (j['size'] ?? 0) as int,
        exp: j['expiresAt'] as int?,
        max: j['maxDownloads'] as int?,
        dl: (j['downloads'] ?? j['dl'] ?? 0) as int,
        createdAt: (j['createdAt'] ?? 0) as int,
        hasPw: (j['hasPassword'] ?? j['hasPw'] ?? false) as bool,
        disabled: (j['disabled'] ?? false) as bool,
        url: j['url']?.toString(),
      );
}
