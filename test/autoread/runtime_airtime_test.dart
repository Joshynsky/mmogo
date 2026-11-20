// The one shared airtime switch controller and the Remembered page's extra-tab
// interface. Invented data only; no database.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/runtime.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/ui/screens/remembered/remembered_extra_tab.dart';

import '../support/pending_store_stand_in.dart';

class _FakeTab implements RememberedExtraTab {
  final _n = ValueNotifier<int>(0);
  @override
  Listenable get listenable => _n;
  @override
  String get pageTitle => 'T';
  @override
  String get recipientsTabLabel => 'R';
  @override
  String tabLabel() => 'X ${_n.value}';
  @override
  String get forgetAllLabel => 'F';
  @override
  String get forgetAllNote => 'N';
  @override
  RememberedExtraHelp get help => const RememberedExtraHelp('Second help', ['second para']);
  @override
  Widget buildBody(BuildContext context) => const SizedBox();
}

void main() {
  tearDown(() => AutoReadRuntime.airtime = null);

  test('the field starts empty and holds the repository controller itself', () {
    expect(AutoReadRuntime.airtime, isNull);
    final bridge = FakeAutoReadBridge(now: DateTime.now);
    final store = InMemoryPendingStore();
    final repo = RealWaitingRepository(
      bridge: bridge,
      store: store,
      service: AutoReadService(
          bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => throw StateError('no db')), now: DateTime.now),
      database: () async => throw StateError('no db'),
      timer: (after, fire) => Timer(const Duration(days: 365), () {}),
      readAirtimeAuto: () async => false,
      writeAirtimeAuto: (v) async {},
      readAirtimeAutoOther: () async => false,
      writeAirtimeAutoOther: (v) async {},
    );
    AutoReadRuntime.airtime = repo.airtime;
    expect(identical(AutoReadRuntime.airtime, repo.airtime), isTrue);
    var heard = 0;
    repo.airtime.addListener(() => heard++);
    AutoReadRuntime.airtime!.setOnOther(true); // flipped through the shared field
    expect(repo.airtime.onOther, isTrue);
    expect(heard, 1);
  });

  test('the extra-tab interface can be implemented without the auto-read folder', () {
    final RememberedExtraTab tab = _FakeTab();
    expect(tab.tabLabel(), 'X 0');
    expect(tab.pageTitle, 'T');
  });
}
