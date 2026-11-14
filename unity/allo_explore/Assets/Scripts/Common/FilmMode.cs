using UnityEngine;
using Rig = Allo.CameraRig.CameraRig;

namespace Allo
{
    /// 영상 촬영용: 화면 위 UI(버튼·패널·HUD)를 그리지 않고 장면만 보인다. UI 코드는 건드리지 않고 캔버스만 끈다.
    /// - 진입 연출(CameraRig.Intro) 동안은 늘 가린다
    /// - 촬영 모드를 켜면 차 안에서는 계속 가리고, 차 안에 들어올 때마다 진입 연출을 다시 보여 준다
    /// 켜고 끄기: 세 손가락으로 화면을 한 번 누른다. 또는 기기에 파일을 둔다 (지우면 꺼진다, 앱 다시 시작).
    /// 파일에 배경 이름(road | coast | mountain | city | highway)을 적으면 그 배경으로 고정한다
    ///   adb shell "echo coast > /sdcard/Android/data/ai.allo.allo_phone/files/film"
    public sealed class FilmMode : MonoBehaviour
    {
        public static bool On;

        readonly System.Collections.Generic.List<Canvas> _hidden = new System.Collections.Generic.List<Canvas>();
        bool _threeDown;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            var file = System.IO.Path.Combine(Application.persistentDataPath, "film");
            On = System.IO.File.Exists(file);
            if (On)
            {
                var kind = System.IO.File.ReadAllText(file).Trim();
                if (System.Array.IndexOf(new[] { "road", "coast", "mountain", "city", "highway" }, kind) >= 0) World.WorldDirector.FilmKind = kind;
            }
            Rig.IntroEveryTime = On;
            var go = new GameObject("FilmMode");
            DontDestroyOnLoad(go);
            go.AddComponent<FilmMode>();
        }

        void Update()
        {
            var three = Input.touchCount == 3;
            if (three && !_threeDown) { On = !On; Rig.IntroEveryTime = On; }
            _threeDown = three;
        }

        void LateUpdate()
        {
            var rig = Camera.main != null ? Camera.main.GetComponent<Rig>() : null;
            var cabin = rig != null && rig.enabled;
            var hide = Rig.IntroActive || On && cabin;
            if (!hide)
            {
                foreach (var c in _hidden) if (c != null) c.enabled = true;
                _hidden.Clear();
                return;
            }
            // 연출·촬영 중에 새로 생긴 캔버스도 가린다 (화면 위에 얹는 것만. 말풍선 같은 장면 속 캔버스는 둔다)
            foreach (var c in FindObjectsByType<Canvas>(FindObjectsSortMode.None))
                if (c.enabled && c.isRootCanvas && c.renderMode != RenderMode.WorldSpace) { c.enabled = false; _hidden.Add(c); }
        }
    }
}
