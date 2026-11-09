using System;

namespace Allo.Bridge
{
    // Flutter → Unity 메시지 (v1). 설계: docs/superpowers/specs/2026-11-09-car-explore-design.md 3.1
    // JsonUtility 는 필드 이름으로 읽고, 모르는 필드는 무시한다.
    //
    // Unity → Flutter (FlutterBridge.Send): ready · close · tap{id} · feed · endTrip · spotted{id}
    // 판정은 모두 Flutter(allo_core) 가 한다. Unity 는 의도만 보내고 보이는 반응만 그린다.

    [Serializable]
    sealed class Envelope
    {
        public int v;
        public string type;
    }

    [Serializable]
    public sealed class SceneState
    {
        public string kind;      // road | coast | mountain | city | tunnel
        public bool night;
        public bool highway;
        public int rain;         // 0 = 비 없음, 1~3 = 와이퍼 단
        public float speedKph;
        public bool moving;
    }

    [Serializable]
    public sealed class CastMember
    {
        public string id;
        public string sprite;
        public string attribute;
    }

    [Serializable]
    public sealed class CastState
    {
        public CastMember companion;   // 동행 캐릭터. 없으면 null 또는 id 가 빈 값
        public CastMember[] friends;   // 모은 친구, 최대 3
    }

    [Serializable]
    public sealed class JoltState
    {
        public string kind;      // brake | steer
    }

    [Serializable]
    public sealed class SettingsState
    {
        public bool gyro;
        public bool reducedMotion;
        public bool canEndTrip;  // 체험(Fake) 주행이라 Unity 안 "주행 종료" 버튼을 보여도 되는지
    }

    /// Flutter 가 보여 달라는 짧은 문구 (동행 반응 "맛있게 먹었어요!" 등). 글은 Flutter 가 정한다
    [Serializable]
    public sealed class ToastState
    {
        public string text;
        public int seq;          // 같은 글이 연달아 와도 다시 보이게 하는 번호
    }
}
