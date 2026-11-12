using UnityEngine;

namespace Allo.Critters
{
    /// 캐릭터 3D 모델 프리팹(Resources/Characters/C_{종 ID})의 머리 정보. AlloBuild.ImportCharacters 가 채운다.
    /// 프리팹 원점은 발밑 가운데, 앞은 +Z, 키는 height(m) 로 맞춰 둔다.
    public sealed class CharacterModel : MonoBehaviour
    {
        public float height = 0.3f;
        /// 발밑 그림자·탭 상자에 쓰는 가로·세로 크기 (m, 키를 맞춘 뒤)
        public Vector2 footprint = new(0.25f, 0.25f);

        public static GameObject Find(string speciesId)
        {
            if (string.IsNullOrEmpty(speciesId)) return null;
            return Resources.Load<GameObject>($"Characters/C_{speciesId}");
        }

        /// 프리팹을 만들고 키를 targetHeight 로 맞춘다 (차 안 0.28m, 창밖 1.3m)
        public static CharacterModel Spawn(GameObject prefab, Transform parent, float targetHeight)
        {
            var go = Instantiate(prefab, parent, false);
            go.name = prefab.name;
            var m = go.GetComponent<CharacterModel>();
            var k = targetHeight / Mathf.Max(0.01f, m.height);
            go.transform.localScale = Vector3.one * k;
            m.Scale = k;
            return m;
        }

        /// Spawn 이 곱한 배율 (프리팹 기준 키 → 원하는 키)
        public float Scale { get; private set; } = 1;
    }
}
