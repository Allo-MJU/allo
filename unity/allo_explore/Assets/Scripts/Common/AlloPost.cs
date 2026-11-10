using UnityEngine;

namespace Allo
{
    /// 화면 후처리: 블룸(밤 불빛·가로등·전조등이 번진다) + 채도·대비·비네트.
    /// 장면에 따라 WorldDirector 가 값을 바꾼다 (밤·터널은 블룸 강하게, 낮은 약하게).
    /// 휴대폰 부담을 줄이려고 블룸은 1/4 해상도에서 만들고, 전체 해상도 패스는 합성 한 번뿐이다.
    [RequireComponent(typeof(Camera))]
    public sealed class AlloPost : MonoBehaviour
    {
        [Tooltip("Hidden/Allo/Post 셰이더 재질 (장면 빌드가 채운다)")] public Material material;
        [Range(0, 2)] public float bloom = 0.25f;
        [Range(0, 1.5f)] public float threshold = 0.9f;
        [Range(0, 2)] public float saturation = 1.15f;
        [Range(0.5f, 1.5f)] public float contrast = 1.06f;
        [Tooltip("전체에 더하는 색 (따뜻하게/차갑게)")] public Color lift = Color.black;
        [Range(0, 1)] public float vignette = 0.15f;

        static readonly int Threshold = Shader.PropertyToID("_Threshold"), Dir = Shader.PropertyToID("_Dir"),
            Bloom = Shader.PropertyToID("_Bloom"), BloomStrength = Shader.PropertyToID("_BloomStrength"),
            Saturation = Shader.PropertyToID("_Saturation"), Contrast = Shader.PropertyToID("_Contrast"),
            Lift = Shader.PropertyToID("_Lift"), Vignette = Shader.PropertyToID("_Vignette");

        void OnRenderImage(RenderTexture src, RenderTexture dst)
        {
            // 셰이더가 이 기기에서 안 돌면(지원 안 함·컴파일 실패) 후처리 없이 그대로 보여 준다. 검은 화면보다 낫다
            if (material == null || material.shader == null || !material.shader.isSupported)
            {
                Graphics.Blit(src, dst);
                return;
            }
            var w = Mathf.Max(1, src.width / 4);
            var h = Mathf.Max(1, src.height / 4);
            var a = RenderTexture.GetTemporary(w, h, 0, src.format);
            var b = RenderTexture.GetTemporary(w, h, 0, src.format);
            a.filterMode = b.filterMode = FilterMode.Bilinear;
            material.SetFloat(Threshold, threshold);
            Graphics.Blit(src, a, material, 0);
            material.SetVector(Dir, new Vector4(1f / w, 0, 0, 0));
            Graphics.Blit(a, b, material, 1);
            material.SetVector(Dir, new Vector4(0, 1f / h, 0, 0));
            Graphics.Blit(b, a, material, 1);
            material.SetTexture(Bloom, a);
            material.SetFloat(BloomStrength, bloom);
            material.SetFloat(Saturation, saturation);
            material.SetFloat(Contrast, contrast);
            material.SetColor(Lift, lift);
            material.SetFloat(Vignette, vignette);
            Graphics.Blit(src, dst, material, 2);
            RenderTexture.ReleaseTemporary(a);
            RenderTexture.ReleaseTemporary(b);
        }
    }
}
