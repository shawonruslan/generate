// Pure logic smoke tests - no network, no Firebase, safe for CI.
import 'package:flutter_test/flutter_test.dart';
import 'package:zedge_studio/app_config.dart';
import 'package:zedge_studio/services/media_service.dart';

void main() {
  test('battery set exposes the 6 dashboard slots', () {
    expect(kSetSlots['WALLPAPER_BATTERY'], hasLength(6));
    expect(kSetSlots['WALLPAPER_24H'], hasLength(4));
    expect(kSetSlots['WALLPAPER_DUAL'], hasLength(2));
  });

  test('type helpers agree with the dashboard type cycle', () {
    for (final String type in kTypeCycle) {
      expect(metaFor(type).label, isNotEmpty);
    }
    expect(isSetType('WALLPAPER_24H'), isTrue);
    expect(isVideoType('LIVE_WALLPAPER'), isTrue);
    expect(isAudioType('RINGTONE'), isTrue);
  });

  test('media name detection', () {
    expect(MediaService.isImageName('sunset.JPG'), isTrue);
    expect(MediaService.isVideoName('clip.mov'), isTrue);
    expect(MediaService.isAudioName('tone.mp3'), isTrue);
    expect(MediaService.isImageName('tone.mp3'), isFalse);
  });

  test('every configured account has a database url', () {
    expect(kAccounts, isNotEmpty);
    for (final ZedgeAccount a in kAccounts) {
      expect(a.databaseUrl, startsWith('https://'));
    }
  });
}
