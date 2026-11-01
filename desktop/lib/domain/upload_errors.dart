/// `explainUploadError(raw)` - human readable hint for a failed queue item.
String explainUploadError(String? raw) {
  final e = raw ?? '';
  final l = e.toLowerCase();
  if (e.isEmpty) return 'No error message was recorded for this item.';
  if (l.contains('profile-list')) {
    final m = RegExp(r'\.nth\((\d+)\)').firstMatch(e);
    final idx = m != null ? int.tryParse(m.group(1)!) : null;
    return idx != null
        ? 'Profile #${idx + 1} does not exist on this Zedge account. The bot was run with a higher "total_profiles" than the account actually has - re-run the workflow with the correct profile count.'
        : 'Could not find the profile card on the Zedge Profiles page. Check that the account has an approved profile and "total_profiles" matches.';
  }
  if (l.contains('stale processing claim')) return 'The bot crashed repeatedly while this item was being processed (stale claim). Requeue to try again.';
  if (l.contains('from r2') && (l.contains('download') || l.contains('http 404'))) {
    return 'Source file is missing in R2 storage - it was probably deleted after another account uploaded it (shared copy). Re-upload the file from the panel.';
  }
  if (l.contains('missing both fileurl')) return 'This queue entry has no file attached. Delete it and upload the file again.';
  // v30 API-only bot errors
  final pm = RegExp(r'profile #(\d+) not found \(account has (\d+)\)', caseSensitive: false).firstMatch(e);
  if (pm != null) return 'Profile #${pm.group(1)} does not exist on this Zedge account (it has ${pm.group(2)}). Re-run the workflow with total_profiles = ${pm.group(2)}.';
  if (l.contains("isn't published") || l.contains('is not published') || l.contains('profile not published')) {
    return 'This Zedge profile is not approved (PUBLISHED) yet, so Zedge rejects uploads to it. Wait for approval or use another profile.';
  }
  final cm = RegExp(r'category "([^"]+)" not found for (\w+)', caseSensitive: false).firstMatch(e);
  if (cm != null) return 'Category "${cm.group(1)}" does not exist for ${cm.group(2)} on Zedge. Fix the category in the metadata and requeue.';
  final lm = RegExp(r'upload limit reached \((\d+) per (\d+) days?\)', caseSensitive: false).firstMatch(e);
  if (lm != null) return 'Zedge upload limit reached for this account (${lm.group(1)} uploads per ${lm.group(2)} day${lm.group(2) == '1' ? '' : 's'}). It works again when the limit resets.';
  if (l.contains('local file(s) missing') || RegExp(r'needs \d+ images, got \d+').hasMatch(l)) {
    return 'The bot could not get all files of this item (download failed or the set is incomplete). Upload the file(s) again and requeue.';
  }
  if (l.contains('authentication object was not found') || l.contains('(auth)') || l.contains('gave no accesstoken')) {
    return 'Zedge session / token expired during the run. Requeue - the next run logs in again.';
  }
  if (l.contains('not supported') || l.contains('no api mapping')) return 'This content type is not supported by the API bot. Check the content type of the item.';
  final fm = RegExp(r'field "(\w+)" is not defined', caseSensitive: false).firstMatch(e);
  if (fm != null) return 'Zedge changed its API (field "${fm.group(1)}" no longer exists). The bot needs an update.';
  if (l.contains('timeout') && (l.contains('apirequestcontext') || l.contains('api upload failed') || l.contains('api:'))) {
    return 'Zedge API did not answer in time (slow network / VPN / proxy). Requeue and try again.';
  }
  if (l.contains('login') || l.contains('sign in') || l.contains('password') || l.contains('credential')) {
    return 'Zedge login failed - check the email / password inputs of the workflow.';
  }
  if (l.contains('captcha') || l.contains('verify you are human')) return 'Zedge showed a captcha / bot check. Try again later or with a different proxy / user-agent.';
  if (l.contains('daily limit') || l.contains('limit reached')) return 'Zedge daily upload limit was reached for this account. It will work again tomorrow.';
  if (l.contains('proxy') || l.contains('err_tunnel') || l.contains('econnrefused') || l.contains('net::err')) {
    return 'Network / proxy problem while reaching Zedge. Check the proxy settings and re-run.';
  }
  if (l.contains('file too large') || l.contains('exceeds') || l.contains('too big')) return 'Zedge rejected the file size. Re-encode / compress the file and upload again.';
  if (l.contains('unsupported') || l.contains('invalid file') || l.contains('format')) return 'Zedge rejected the file format. Check the file type for this content type.';
  if (l.contains('waiting for locator') || l.contains('waitfor') || l.contains('timeout')) {
    final m = RegExp(r'locator\(([^)]*)\)').firstMatch(e);
    final loc = m != null ? m.group(1)! : '';
    return 'Timed out waiting for a page element${m != null ? ' (${loc.length > 80 ? loc.substring(0, 80) : loc})' : ''}. Zedge may have changed its layout or loaded slowly - requeue and try again.';
  }
  if (l.contains('api upload failed')) return 'Zedge API rejected the upload - see the reason in the raw message below. Requeue to retry.';
  return 'Upload failed with a technical error - see the raw message below. Requeue to retry.';
}
