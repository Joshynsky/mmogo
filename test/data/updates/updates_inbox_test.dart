// ignore_for_file: text_direction_code_point_in_literal
// B26: the Updates inbox in shared_preferences (key updates_inbox_v1).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

Notice n(String tag, {int at = 1000, String notes = 'n', bool read = false}) => Notice(
      tag: tag,
      notes: notes,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(at),
      read: read,
    );

Future<List<dynamic>> stored() async {
  final p = await SharedPreferences.getInstance();
  return jsonDecode(p.getString(UpdatesInbox.storageKey)!) as List<dynamic>;
}

void main() {
  UpdatesInbox make() => UpdatesInbox(installedVersion: () => '0.1.1');
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('storage key is updates_inbox_v1', () {
    expect(UpdatesInbox.storageKey, 'updates_inbox_v1');
    expect(UpdatesInbox.maxNotices, 10);
  });

  test('empty by default, nothing unread', () async {
    final i = make();
    await i.load();
    expect(i.notices, isEmpty);
    expect(i.unreadCount.value, 0);
  });

  test('add stores a notice, unread, and persists it', () async {
    final i = make();
    expect(await i.add(n('v0.2.0')), isTrue);
    expect(i.unreadCount.value, 1);
    final again = make();
    await again.load();
    expect(again.notices.single.tag, 'v0.2.0');
    expect(again.notices.single.read, isFalse);
    expect(again.unreadCount.value, 1);
  });

  test('same_tag_twice_is_stored_once (also v-prefix variants)', () async {
    final i = make();
    expect(await i.add(n('v0.2.0')), isTrue);
    expect(await i.add(n('v0.2.0', at: 5000)), isFalse);
    expect(await i.add(n('0.2.0', at: 6000)), isFalse);
    expect(i.notices, hasLength(1));
    expect(await stored(), hasLength(1));
  });

  test('eleven_notices_keep_ten_newest_first_and_drop_the_oldest', () async {
    final i = make();
    for (var k = 0; k < 11; k++) {
      expect(await i.add(n('0.2.$k', at: 1000 + k)), isTrue);
    }
    expect(i.notices, hasLength(10));
    expect(i.notices.first.tag, '0.2.10');
    expect(i.notices.last.tag, '0.2.1');
    expect(i.notices.any((x) => x.tag == '0.2.0'), isFalse);
    expect(await stored(), hasLength(10));
    // The dropped tag can come back later as a new notice.
    expect(await i.add(n('0.2.0', at: 9000)), isTrue);
    expect(i.notices, hasLength(10));
    expect(i.notices.first.tag, '0.2.0');
  });

  test('notes are sanitised at store', () async {
    final i = make();
    await i.add(n('0.2.0', notes: 'a‮b\u0000c ${'z' * 3000}'));
    expect(i.notices.single.notes, startsWith('abc z'));
    expect(i.notices.single.notes.runes.length, 1500);
    final raw = (await stored()).single as Map;
    expect((raw['notes'] as String).contains('‮'), isFalse);
  });

  test('a bad tag is refused', () async {
    final i = make();
    expect(await i.add(n('1.2.3-rc1')), isFalse);
    expect(await i.add(n('latest')), isFalse);
    expect(i.notices, isEmpty);
  });

  test('markAllRead clears the unread count and persists', () async {
    final i = make();
    await i.add(n('0.2.0'));
    await i.add(n('0.3.0', at: 2000));
    expect(i.unreadCount.value, 2);
    await i.markAllRead();
    expect(i.unreadCount.value, 0);
    final again = make();
    await again.load();
    expect(again.unreadCount.value, 0);
    expect(again.notices.every((x) => x.read), isTrue);
  });

  test('unreadCount notifier fires on add and on read', () async {
    final i = make();
    final seen = <int>[];
    i.unreadCount.addListener(() => seen.add(i.unreadCount.value));
    await i.add(n('0.2.0'));
    await i.markAllRead();
    expect(seen, [1, 0]);
  });

  group('corrupt storage is tolerated', () {
    for (final raw in [
      'not json',
      '{"a":1}',
      '"x"',
      '123',
      'null',
      '[1,2,"x",null]',
      '[{"tag":"nope","notes":"x","receivedAt":1}]',
      '[{"tag":"0.2.0","notes":"x","receivedAt":"1"}]',
      '[{"tag":5,"receivedAt":1}]',
      '[',
    ]) {
      test('treated as empty: $raw', () async {
        SharedPreferences.setMockInitialValues({UpdatesInbox.storageKey: raw});
        final i = make();
        await i.load();
        expect(i.notices, isEmpty);
        expect(i.unreadCount.value, 0);
        // And the inbox still works afterwards.
        expect(await i.add(n('0.2.0')), isTrue);
      });
    }

    test('oversized stored value is treated as empty', () async {
      final big = jsonEncode([
        {'tag': '0.2.0', 'notes': 'a' * (UpdatesInbox.maxStoredChars + 10), 'receivedAt': 1}
      ]);
      SharedPreferences.setMockInitialValues({UpdatesInbox.storageKey: big});
      final i = make();
      await i.load();
      expect(i.notices, isEmpty);
    });

    test('wrong-typed value under the key (an int) does not throw', () async {
      SharedPreferences.setMockInitialValues({UpdatesInbox.storageKey: 7});
      final i = make();
      await i.load();
      expect(i.notices, isEmpty);
    });

    test('good entries survive next to bad ones; stored notes are re-sanitised', () async {
      SharedPreferences.setMockInitialValues({
        UpdatesInbox.storageKey: jsonEncode([
          {'tag': '0.2.0', 'notes': 'x‮y', 'receivedAt': 5, 'read': true},
          {'tag': 'bad', 'receivedAt': 6},
        ])
      });
      final i = make();
      await i.load();
      expect(i.notices.single.tag, '0.2.0');
      expect(i.notices.single.notes, 'xy');
      expect(i.notices.single.read, isTrue);
      expect(i.unreadCount.value, 0);
    });

    test('a stored list over the cap or with duplicate tags is cut and deduplicated at load', () async {
      SharedPreferences.setMockInitialValues({
        UpdatesInbox.storageKey: jsonEncode([
          for (var k = 0; k < 14; k++) {'tag': '0.3.$k', 'notes': '', 'receivedAt': k},
          {'tag': 'v0.3.5', 'notes': '', 'receivedAt': 99},
        ])
      });
      final i = make();
      await i.load();
      expect(i.notices, hasLength(10));
      expect(i.notices.map((x) => x.tag).toSet(), hasLength(10));
    });
  });

  test('notices not newer than the installed version are removed at load', () async {
    SharedPreferences.setMockInitialValues({
      UpdatesInbox.storageKey: jsonEncode([
        {'tag': '0.1.0', 'notes': '', 'receivedAt': 1},
        {'tag': 'v0.1.1', 'notes': '', 'receivedAt': 2},
        {'tag': '0.1.2', 'notes': '', 'receivedAt': 3},
      ])
    });
    final i = make();
    await i.load();
    expect(i.notices.map((x) => x.tag), ['0.1.2']);
    expect((await stored()), hasLength(1)); // rewritten
  });

  test('add before load does not wipe what was stored', () async {
    SharedPreferences.setMockInitialValues({
      UpdatesInbox.storageKey: jsonEncode([
        {'tag': '0.3.0', 'notes': 'old', 'receivedAt': 1},
      ])
    });
    final i = make();
    await i.add(n('0.4.0', at: 2));
    expect(i.notices.map((x) => x.tag), ['0.4.0', '0.3.0']);
  });
}
