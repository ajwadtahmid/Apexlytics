import 'dart:io';

import 'package:apexlytics/utils/storage/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp; // stands in for the app's cache / tmp folder
  late Directory elsewhere; // stands in for the user's own folder

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('picker_cache');
    elsewhere = await Directory.systemTemp.createTemp('picker_user');
    addTearDown(() async {
      for (final d in [temp, elsewhere]) {
        if (await d.exists()) await d.delete(recursive: true);
      }
    });
  });

  Future<File> fileIn(Directory dir, String name) async =>
      File(p.join(dir.path, name)).create(recursive: true);

  test('removes the picker\'s copy and the folder it sat in', () async {
    final copy = await fileIn(temp, p.join('a1b2-uuid', 'backup.gz'));

    await deletePickerCopy(copy.path, temp);

    expect(await copy.exists(), isFalse);
    expect(await copy.parent.exists(), isFalse);
    expect(await temp.exists(), isTrue, reason: 'the cache itself stays');
  });

  test('leaves the folder alone when something else is in it', () async {
    final copy = await fileIn(temp, p.join('shared', 'backup.gz'));
    final other = await fileIn(temp, p.join('shared', 'other.bin'));

    await deletePickerCopy(copy.path, temp);

    expect(await copy.exists(), isFalse);
    expect(await other.exists(), isTrue);
  });

  test('never touches a file outside the cache, i.e. the user\'s original', () async {
    final original = await fileIn(elsewhere, 'my-backup.gz');

    await deletePickerCopy(original.path, temp);

    expect(await original.exists(), isTrue);
  });

  test('also removes a copy in the second root, as iOS leaves it in tmp/', () async {
    final cache = await Directory.systemTemp.createTemp('picker_ios_cache');
    addTearDown(() => cache.delete(recursive: true));
    final copy = await fileIn(temp, p.join('app.id-Inbox', 'backup.gz'));

    await deletePickerCopy(copy.path, cache, alsoWithin: temp);

    expect(await copy.exists(), isFalse);
    expect(await copy.parent.exists(), isFalse);
    expect(await temp.exists(), isTrue, reason: 'tmp/ itself stays');
  });

  test('the second root does not widen what is deleted', () async {
    final original = await fileIn(elsewhere, 'my-backup.gz');

    await deletePickerCopy(original.path, temp, alsoWithin: temp);

    expect(await original.exists(), isTrue);
  });

  test('a missing file is not an error', () async {
    await deletePickerCopy(p.join(temp.path, 'gone', 'x.gz'), temp);
  });
}
