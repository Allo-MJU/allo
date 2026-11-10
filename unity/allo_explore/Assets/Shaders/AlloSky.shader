// 하늘: 위 → 지평선 → 아래 그라데이션 + 해. 장면마다 색만 바꾼다 (WorldDirector.Atmosphere)
Shader "Allo/SkyGradient"
{
    Properties
    {
        _Top ("Top", Color) = (0.24, 0.55, 0.95, 1)
        _Horizon ("Horizon", Color) = (0.78, 0.9, 1, 1)
        _Bottom ("Bottom", Color) = (0.55, 0.7, 0.55, 1)
        _SunDir ("Sun Direction", Vector) = (0.3, 0.6, 0.5, 0)
        _SunColor ("Sun Color", Color) = (1, 0.96, 0.85, 1)
        _SunSize ("Sun Size", Range(0, 0.1)) = 0.012
        _Exponent ("Gradient Curve", Range(0.1, 2)) = 0.55
    }
    SubShader
    {
        Tags { "Queue"="Background" "RenderType"="Background" "PreviewType"="Skybox" }
        Cull Off ZWrite Off
        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            fixed4 _Top, _Horizon, _Bottom, _SunColor;
            float4 _SunDir;
            half _SunSize, _Exponent;
            struct v2f { float4 pos : SV_POSITION; float3 dir : TEXCOORD0; };
            v2f vert (appdata_base v) { v2f o; o.pos = UnityObjectToClipPos(v.vertex); o.dir = v.vertex.xyz; return o; }
            fixed4 frag (v2f i) : SV_Target
            {
                float3 d = normalize(i.dir);
                float h = d.y;
                fixed3 c = h > 0 ? lerp(_Horizon.rgb, _Top.rgb, pow(saturate(h), _Exponent))
                                 : lerp(_Horizon.rgb, _Bottom.rgb, saturate(-h * 6));
                float s = dot(d, normalize(_SunDir.xyz));
                c += _SunColor.rgb * (smoothstep(1 - _SunSize, 1 - _SunSize * 0.6, s) + 0.22 * pow(saturate(s), 40));
                return fixed4(c, 1);
            }
            ENDCG
        }
    }
}
