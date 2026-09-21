import 'package:automation_hub_desktop/config/build_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('build profile is configured', () {
    expect(kProfiles, isNotEmpty);
    final p = BuildProfile.byId(BuildProfile.compileTimeId);
    expect(p.accounts, isNotEmpty);
  });
}
