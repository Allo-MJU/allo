/// Flutter → Unity 메시지 통로.
///
/// - Unity 가 `ready` 를 보내기 전에는 type 별 마지막 값만 모아 두었다가 [onReady] 때 보낸다.
/// - 같은 type 에 같은 문자열은 다시 보내지 않는다. 단 `jolt` 는 순간 사건이라 매번 보내고,
///   ready 전에 온 것은 버린다 (늦게 흔들면 어색하다).
/// - Unity 가 다시 시작해 `ready` 를 또 보내면 마지막 값을 다시 보낸다.
class ExploreLink {
  ExploreLink(this._send);

  final void Function(String json) _send;
  final _last = <String, String>{};
  bool _ready = false;

  static const _momentary = {'jolt'};

  void post(String type, String json) {
    if (_momentary.contains(type)) {
      if (_ready) _send(json);
      return;
    }
    if (_last[type] == json) return;
    _last[type] = json;
    if (_ready) _send(json);
  }

  void onReady() {
    _ready = true;
    _last.values.forEach(_send);
  }
}
