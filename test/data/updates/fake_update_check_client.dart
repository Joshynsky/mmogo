import 'package:mmogo/data/updates/release_info.dart';
import 'package:mmogo/data/updates/update_check_client.dart';

/// Test double for the network layer: nothing here opens a socket.
class FakeUpdateCheckClient implements UpdateCheckSource {
  FakeUpdateCheckClient({this.result, this.error});

  final ReleaseInfo? result;
  final Object? error;
  int calls = 0;

  @override
  Future<ReleaseInfo> fetchLatest() async {
    calls++;
    if (error != null) throw error!;
    return result!;
  }
}
