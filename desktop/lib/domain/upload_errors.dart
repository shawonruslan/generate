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
  return 'Upload failed with a technical error - see the raw message below. Requeue to retry.';
}
