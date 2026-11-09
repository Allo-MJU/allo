using Allo.Bridge;
using UnityEngine;

/// 연동 검증용: 장면 메시지가 오면 큐브 색을 바꾼다. Task 5 에서 차 내부 장면으로 바뀌며 지운다.
public sealed class SpikeSceneTint : MonoBehaviour
{
    void OnEnable() => FlutterBridge.SceneChanged += Apply;
    void OnDisable() => FlutterBridge.SceneChanged -= Apply;

    void Apply(SceneState s)
    {
        var c = s.kind switch
        {
            "coast" => new Color(0.36f, 0.66f, 0.85f),
            "mountain" => new Color(0.37f, 0.57f, 0.31f),
            "city" => new Color(0.85f, 0.6f, 0.45f),
            "tunnel" => new Color(0.9f, 0.6f, 0.2f),
            _ => Color.white,
        };
        if (s.night) c *= 0.5f;
        GetComponent<Renderer>().material.color = c;
    }
}
