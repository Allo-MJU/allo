// 화면 후처리 (AlloPost.cs 가 쓴다): 블룸 + 색감 보정.
//   Pass 0: 밝은 부분만 1/4 크기로 추출   Pass 1: 한 방향 흐림 (가로·세로 두 번)   Pass 2: 합성 + 채도·대비·비네트
// 휴대폰에서 돌도록 전체 해상도 패스는 마지막 하나뿐이다.
Shader "Hidden/Allo/Post"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        CGINCLUDE
        #include "UnityCG.cginc"
        sampler2D _MainTex, _Bloom;
        float4 _MainTex_TexelSize;
        float4 _Dir;
        half _Threshold, _BloomStrength, _Saturation, _Contrast, _Vignette;
        half4 _Lift;

        struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
        v2f vert (appdata_img v)
        {
            v2f o;
            o.pos = UnityObjectToClipPos(v.vertex);
            o.uv = v.texcoord;
            return o;
        }

        // 밝은 부분만: 문턱 아래는 0, 위는 부드럽게 (soft knee)
        fixed4 fragPrefilter (v2f i) : SV_Target
        {
            fixed3 c = tex2D(_MainTex, i.uv).rgb;
            half b = max(c.r, max(c.g, c.b));
            half knee = _Threshold * 0.5 + 1e-4;
            half soft = clamp(b - _Threshold + knee, 0, 2 * knee);
            soft = soft * soft / (4 * knee);
            half w = max(soft, b - _Threshold) / max(b, 1e-4);
            return fixed4(c * w, 1);
        }

        // 5탭 가우시안 (_Dir 이 텍셀 단위 방향)
        fixed4 fragBlur (v2f i) : SV_Target
        {
            float2 d = _Dir.xy;
            fixed3 c = tex2D(_MainTex, i.uv).rgb * 0.227;
            c += (tex2D(_MainTex, i.uv + d * 1.385).rgb + tex2D(_MainTex, i.uv - d * 1.385).rgb) * 0.316;
            c += (tex2D(_MainTex, i.uv + d * 3.231).rgb + tex2D(_MainTex, i.uv - d * 3.231).rgb) * 0.070;
            return fixed4(c, 1);
        }

        fixed4 fragComposite (v2f i) : SV_Target
        {
            fixed3 c = tex2D(_MainTex, i.uv).rgb;
            c += tex2D(_Bloom, i.uv).rgb * _BloomStrength;
            // 색감은 눈에 보이는(감마) 공간에서 만진다
            c = pow(max(c, 0), 1 / 2.2);
            half luma = dot(c, half3(0.299, 0.587, 0.114));
            c = lerp(luma.xxx, c, _Saturation);
            c = lerp(half3(0.5, 0.5, 0.5), c, _Contrast);
            c += _Lift.rgb;
            float2 v = i.uv - 0.5;
            c *= 1 - _Vignette * smoothstep(0.35, 0.95, dot(v, v) * 2);
            c = pow(saturate(c), 2.2);
            return fixed4(c, 1);
        }
        ENDCG

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragPrefilter
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragBlur
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment fragComposite
            ENDCG
        }
    }
    Fallback Off
}
