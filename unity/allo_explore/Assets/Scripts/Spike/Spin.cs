using UnityEngine;

/// 연동 검증(spike)용: 큐브를 돌린다. Task 5 에서 차 내부 장면으로 바뀌며 지운다.
public sealed class Spin : MonoBehaviour
{
    public float degreesPerSecond = 60f;

    void Update() => transform.Rotate(0f, degreesPerSecond * Time.deltaTime, 0f, Space.World);
}
