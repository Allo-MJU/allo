// 차 유리: 옅은 색 + 비 올 때 빗방울·흘러내리는 물줄기 (_Rain 0~1, WorldDirector 가 와이퍼 단에 맞춰 넣는다).
// 빗방울은 텍스처 없이 격자마다 하나씩 그린다. 유리 평면의 UV(0~1)를 _Tiling 칸으로 나눈다.
Shader "Allo/Glass"
{
    Properties
    {
        _Color ("Tint", Color) = (0.66, 0.86, 0.85, 0.12)
        _Rain ("Rain", Range(0, 1)) = 0
        _Tiling ("Drop Grid (x, y)", Vector) = (40, 18, 0, 0)
        _DropColor ("Drop Color", Color) = (0.9, 0.95, 1, 0.36)
        _FogTex ("Fog (R, FogGlass 가 그린다)", 2D) = "black" {}
        _FogColor ("Fog Color", Color) = (0.93, 0.95, 0.97, 0.78)
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" "IgnoreProjector"="True" }
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            fixed4 _Color, _DropColor, _FogColor;
            sampler2D _FogTex;
            half _Rain;
            float4 _Tiling;

            struct v2f { float4 pos : SV_POSITION; float2 uv : TEXCOORD0; };
            v2f vert (appdata_base v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = v.texcoord.xy;
                return o;
            }

            float hash (float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

            // 한 칸 안의 빗방울: 칸마다 자리·크기·떨어지는 속도가 다르다. 0~1 (가장자리 부드럽게)
            half drops (float2 uv, float t, float scale)
            {
                float2 g = uv * _Tiling.xy * scale;
                float2 id = floor(g);
                float2 f = frac(g);
                float h = hash(id);
                // 흘러내림: 칸 안에서 아래로 움직이고, 칸마다 시작점이 다르다
                float fall = frac(t * (0.12 + h * 0.25) + h * 7);
                float2 center = float2(0.2 + hash(id + 3.1) * 0.6, 1 - fall);
                float2 d = (f - center) * float2(1, 0.7);
                float r = 0.04 + hash(id + 9.7) * 0.1;
                half drop = smoothstep(r, r * 0.55, length(d));
                // 물줄기: 방울 위로 가늘게 남는 자국
                half trail = smoothstep(0.018, 0.0, abs(f.x - center.x)) * smoothstep(0, 0.4, f.y - center.y) * (1 - fall) * 0.4;
                // 모든 칸에 방울이 있지는 않다
                half present = step(0.3, h);
                return saturate(drop + trail) * present;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 c = _Color;
                if (_Rain > 0.001)
                {
                    float t = _Time.y;
                    half d = drops(i.uv, t, 1) + drops(i.uv + 0.37, t * 1.3, 1.7) * 0.55;
                    d = saturate(d) * saturate(_Rain * 1.5);
                    // 방울 가운데는 밝고 가장자리는 살짝 어두운 테 (유리 위 물방울의 굴절 느낌)
                    half ring = smoothstep(0.55, 1.0, d) ;
                    c.rgb = lerp(c.rgb, lerp(_DropColor.rgb * 0.7, _DropColor.rgb, ring), saturate(d * 1.4));
                    c.a = saturate(c.a + d * _DropColor.a);
                }
                // 김서림: 뿌옇게 + 아주 옅은 얼룩. 손가락으로 지운 곳은 맑게
                half fog = tex2D(_FogTex, i.uv).r;
                if (fog > 0.002)
                {
                    half grain = 0.85 + 0.15 * hash(floor(i.uv * float2(90, 50)));
                    c.rgb = lerp(c.rgb, _FogColor.rgb * grain, saturate(fog * 1.1));
                    c.a = max(c.a, fog * _FogColor.a);
                }
                return c;
            }
            ENDCG
        }
    }
    Fallback "Legacy Shaders/Transparent/Diffuse"
}
