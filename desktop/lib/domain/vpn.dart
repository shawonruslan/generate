/// v24.1 VPN tab domain logic (OpenVPN / WireGuard): config analysis, models, stages.
const String kVpnPath = 'dashboardSettings/vpn';

class VpnFileField {
  const VpnFileField(this.key, this.label, this.directive, this.accept);
  final String key, label, directive, accept;
}

const List<VpnFileField> kVpnFileFields = [
  VpnFileField('ca', 'CA certificate', 'ca', '.crt,.pem,.cer,.ca'),
  VpnFileField('cert', 'Client certificate', 'cert', '.crt,.pem,.cer'),
  VpnFileField('key', 'Client private key', 'key', '.key,.pem'),
  VpnFileField('tlsAuth', 'tls-auth key', 'tls-auth', '.key,.txt'),
  VpnFileField('tlsCrypt', 'tls-crypt key', 'tls-crypt', '.key,.txt'),
];

VpnFileField? vpnFieldByKey(String key) => kVpnFileFields.where((f) => f.key == key).firstOrNull;

/// `vpnFieldFor(directive)` -> field key or null.
String? vpnFieldFor(String directive) => kVpnFileFields.where((f) => f.directive == directive).firstOrNull?.key;

const List<List<String>> kVpnStages = [
  ['dispatch', 'Dispatched'],
  ['load', 'Runner started'],
  ['connecting', 'Installing / connecting'],
  ['connect', 'Tunnel up'],
  ['verify', 'IP + zedge.net verified'],
];

class VpnExternalRef {
  const VpnExternalRef(this.directive, this.file);
  final String directive;
  final String file;
}

class VpnAnalysis {
  VpnAnalysis({required this.type, required this.empty});
  String type; // openvpn | wireguard
  final bool empty;
  bool needsAuth = false;
  final List<String> inline = [];
  final List<VpnExternalRef> external = [];
  final List<String> hints = [];
  final List<String> warnings = [];
  String remote = '';
}

bool _re(String pattern, String t) => RegExp(pattern, multiLine: true, caseSensitive: false).hasMatch(t);

/// `vpnAnalyze(text, fallbackType)`
VpnAnalysis vpnAnalyze(String? text, String? fallbackType) {
  final t = text ?? '';
  final out = VpnAnalysis(type: (fallbackType == null || fallbackType.isEmpty) ? 'openvpn' : fallbackType, empty: t.trim().isEmpty);
  if (out.empty) return out;
  if (_re(r'^\s*\[Interface\]', t) && _re(r'^\s*\[Peer\]', t)) {
    out.type = 'wireguard';
    if (!_re(r'^\s*PrivateKey\s*=', t)) out.warnings.add('Missing PrivateKey in [Interface]');
    if (!_re(r'^\s*Endpoint\s*=', t)) out.warnings.add('Missing Endpoint in [Peer]');
    if (!_re(r'^\s*AllowedIPs\s*=.*0\.0\.0\.0\/0', t)) out.warnings.add('AllowedIPs has no 0.0.0.0/0 - the public IP may not change');
    if (!_re(r'^\s*DNS\s*=', t)) out.hints.add('No DNS line - 1.1.1.1 will be added on the runner');
    final ep = RegExp(r'^\s*Endpoint\s*=\s*(\S+)', multiLine: true, caseSensitive: false).firstMatch(t);
    if (ep != null) out.remote = ep.group(1)!;
    return out;
  }
  out.type = 'openvpn';
  out.needsAuth = _re(r'^\s*auth-user-pass\b', t);
  for (final d in const ['ca', 'cert', 'key', 'tls-auth', 'tls-crypt', 'pkcs12', 'tls-crypt-v2']) {
    if (RegExp('<$d>', caseSensitive: false).hasMatch(t)) out.inline.add(d);
  }
  for (final ln in t.split('\n')) {
    final m = RegExp(r'^\s*(ca|cert|key|tls-auth|tls-crypt|pkcs12|tls-crypt-v2|crl-verify)\s+(\S+)', caseSensitive: false).firstMatch(ln);
    if (m == null) continue;
    final d = m.group(1)!.toLowerCase();
    final file = m.group(2)!;
    if (file == '[inline]' || out.inline.contains(d)) continue;
    out.external.add(VpnExternalRef(d, file));
  }
  final rm = RegExp(r'^\s*remote\s+(\S+)', multiLine: true, caseSensitive: false).firstMatch(t);
  if (rm != null) out.remote = rm.group(1)!;
  if (!_re(r'^\s*remote\s+', t)) out.warnings.add("No 'remote' line found - is this a client config?");
  if (!out.needsAuth &&
      !out.inline.contains('cert') &&
      !out.inline.contains('pkcs12') &&
      !out.external.any((x) => x.directive == 'cert' || x.directive == 'pkcs12')) {
    out.hints.add('No client certificate and no auth-user-pass - if the provider needs a login, add it below');
  }
  if (out.inline.isNotEmpty) out.hints.add('Embedded: ${out.inline.map((x) => '<$x>').join(' ')} - nothing to upload');
  return out;
}

/// Per-account GitHub connection used by the VPN tab.
class VpnGhCfg {
  const VpnGhCfg({required this.owner, required this.repo, required this.branch, required this.token, required this.workflow});
  final String owner, repo, branch, token, workflow;
  bool get ready => owner.isNotEmpty && repo.isNotEmpty && token.isNotEmpty && workflow.isNotEmpty;
}

/// `vpnEmpty()` state per account.
class VpnState {
  VpnState(Map<String, dynamic>? raw) : raw = raw == null ? <String, dynamic>{} : Map<String, dynamic>.from(raw);
  final Map<String, dynamic> raw;

  String get mode => (raw['mode'] ?? 'none').toString();
  String get activeProfileId => (raw['activeProfileId'] ?? '').toString();
  bool get keepProxy => raw['keepProxy'] == true;
  Map<String, Map<String, dynamic>> get profiles {
    final m = raw['profiles'];
    final out = <String, Map<String, dynamic>>{};
    if (m is Map) {
      m.forEach((k, v) {
        if (v is Map) out['$k'] = Map<String, dynamic>.from(v);
      });
    }
    return out;
  }
  Map<String, dynamic>? get github => raw['github'] is Map ? Map<String, dynamic>.from(raw['github'] as Map) : null;
  Map<String, dynamic>? get lastTest => raw['lastTest'] is Map ? Map<String, dynamic>.from(raw['lastTest'] as Map) : null;
  Map<String, dynamic>? get activeProfile => profiles[activeProfileId];
}

String vpnFmtIp(dynamic ip) {
  if (ip == null) return '';
  if (ip is String) return ip;
  if (ip is Map) {
    final city = ip['city']?.toString(), country = ip['country']?.toString(), org = ip['org']?.toString();
    final loc = [city, country].where((x) => x != null && x.isNotEmpty).join(', ');
    return '${ip['ip'] ?? '?'}${loc.isNotEmpty ? ' ($loc)' : ''}${org != null && org.isNotEmpty ? ' - $org' : ''}';
  }
  return '$ip';
}

String vpnStatusClass(Map<String, dynamic>? r) {
  if (r == null) return 'idle';
  final s = r['status'];
  return s == 'ok' ? 'ok' : s == 'fail' ? 'fail' : 'busy';
}

/// `ghParseRepoLink(raw)` -> (owner, repo) or null.
(String, String)? ghParseRepoLink(String? raw) {
  final s = (raw ?? '').trim().replaceAll(RegExp(r'\.git$'), '').replaceAll(RegExp(r'^git@github\.com:'), '');
  final m = RegExp(r'(?:github\.com\/)?([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)(?:[\/?#]|$)').firstMatch(s);
  return m == null ? null : (m.group(1)!, m.group(2)!);
}
