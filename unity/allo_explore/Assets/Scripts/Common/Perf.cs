using UnityEngine;

namespace Allo
{
    /// 휴대폰에서 부드럽게 돌도록 그리기 부담을 줄인다.
    /// - 해상도: 화면 짧은 쪽 720px 로 그려 확대한다 (2400×1080 그대로는 픽셀이 너무 많다)
    /// - 그림자: 차 안(6m)만, 단단한 그림자
    /// - 프레임: 60 목표, 수직 동기화 끔
    public static class Perf
    {
        public const int TargetShortSide = 720;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Apply()
        {
            Application.targetFrameRate = 60;
            QualitySettings.vSyncCount = 0;
            QualitySettings.shadowDistance = 6;
            QualitySettings.shadows = ShadowQuality.HardOnly;
            QualitySettings.shadowResolution = ShadowResolution.Medium;
            QualitySettings.antiAliasing = 0;
            QualitySettings.pixelLightCount = 2;
            if (Object.FindFirstObjectByType<FpsLog>() == null)
                new GameObject("FpsLog").AddComponent<FpsLog>();
#if !UNITY_EDITOR
            var w = Screen.width;
            var h = Screen.height;
            var shortSide = Mathf.Min(w, h);
            if (shortSide > TargetShortSide)
            {
                var k = (float)TargetShortSide / shortSide;
                Screen.SetResolution(Mathf.RoundToInt(w * k), Mathf.RoundToInt(h * k), true);
            }
#endif
        }
    }

    /// 10초마다 평균 fps 와 가장 길었던 프레임(ms)을 로그로 남긴다 (`adb logcat -s Unity | grep Perf`). 실기기 측정용 (#77)
    public sealed class FpsLog : MonoBehaviour
    {
        float _t, _worst;
        int _n;

        void Update()
        {
            var dt = Time.unscaledDeltaTime;
            _t += dt; _n++;
            if (dt > _worst) _worst = dt;
            if (_t < 10) return;
            Debug.Log($"[Perf] fps={_n / _t:F1} worst={_worst * 1000:F0}ms");
            _t = 0; _n = 0; _worst = 0;
        }
    }
}
