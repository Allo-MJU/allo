// 툰 셰이딩: 빛·그림자 2단(또렷한 경계), 그림자는 푸른 기운, 2단 하이라이트(광택), 가장자리 빛(림), 선택적 외곽선.
// 외곽선은 _OutlineDist > 0 이면 멀수록 굵게 그려 화면에서 비슷한 두께로 보인다 (가까운 물체만 두껍고 먼 물체는 사라지는 것을 막는다).
// _WorldUV > 0 이면 텍스처를 도로 좌표(xz)로 깐다 (넓은 땅에 풀 무늬가 늘어나지 않게).
//   도로 좌표 = 세상 뿌리(WorldRoot) 기준 로컬 xz + 달린 거리(_AlloTravel). 차는 제자리고 조각이 뒤로 흐르므로
//   월드 xz 그대로 쓰면 무늬가 제자리에 멈춰 보인다. WorldDirector 가 _AlloWorldToRoot·_AlloTravel 을 전역으로 넣는다.
Shader "Allo/Toon"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _ShadowTint ("Shadow Tint", Color) = (0.62, 0.66, 0.9, 1)
        _RampSoft ("Ramp Softness", Range(0.001, 0.6)) = 0.05
        _HiColor ("Highlight Color", Color) = (1, 0.98, 0.92, 1)
        _HiSize ("Highlight Size (0 = off)", Range(0, 1)) = 0
        _HiStrength ("Highlight Strength", Range(0, 1)) = 0.5
        _RimColor ("Rim Color", Color) = (1, 0.97, 0.9, 1)
        _RimPower ("Rim Power", Range(0.5, 8)) = 3.5
        _RimStrength ("Rim Strength", Range(0, 1)) = 0.35
        _OutlineColor ("Outline Color", Color) = (0.16, 0.13, 0.12, 1)
        _OutlineWidth ("Outline Width (m)", Range(0, 0.1)) = 0
        _OutlineDist ("Outline Distance Scale (0 = constant)", Range(0, 1)) = 0
        _WorldUV ("World UV Scale (0 = mesh UV)", Float) = 0
        _EmissionColor ("Emission", Color) = (0,0,0,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        Pass
        {
            Name "OUTLINE"
            Cull Front
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "UnityCG.cginc"
            float _OutlineWidth, _OutlineDist;
            fixed4 _OutlineColor;
            struct v2f { float4 pos : SV_POSITION; UNITY_FOG_COORDS(0) };
            v2f vert (appdata_base v)
            {
                v2f o;
                float4 p = v.vertex;
                // 거리에 따라 굵게: 10m 에서 1배(_OutlineDist 0.1 기준), 가까우면 그대로, 멀면 최대 6배
                float depth = -UnityObjectToViewPos(v.vertex).z;
                float k = _OutlineDist > 0 ? clamp(depth * _OutlineDist, 1, 6) : 1;
                p.xyz += normalize(v.normal) * _OutlineWidth * k;
                o.pos = UnityObjectToClipPos(p);
                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }
            fixed4 frag (v2f i) : SV_Target
            {
                clip(_OutlineWidth - 0.0001);
                fixed4 c = _OutlineColor;
                UNITY_APPLY_FOG(i.fogCoord, c);
                return c;
            }
            ENDCG
        }

        CGPROGRAM
        #pragma surface surf Toon fullforwardshadows
        #pragma target 3.0
        sampler2D _MainTex;
        fixed4 _Color, _ShadowTint, _RimColor, _EmissionColor, _HiColor;
        half _RampSoft, _RimPower, _RimStrength, _HiSize, _HiStrength;
        float _WorldUV;
        float4x4 _AlloWorldToRoot;
        float _AlloTravel;

        struct Input { float2 uv_MainTex; float3 worldPos; float3 viewDir; };

        half4 LightingToon (SurfaceOutput s, half3 lightDir, half3 viewDir, half atten)
        {
            half ndl = dot(s.Normal, lightDir);
            half4 c;
            if (_WorldSpaceLightPos0.w == 0)
            {
                // 해: 빛·그림자 2단, 경계는 또렷하게, 그림자는 푸른 기운
                half lit = smoothstep(0, _RampSoft, ndl) * smoothstep(0.35, 0.5, atten);
                c.rgb = s.Albedo * _LightColor0.rgb * lerp(_ShadowTint.rgb, 1, lit);
                // 2단 하이라이트: 빛 쪽 가장 밝은 부분에 한 단 더 (구름 윗면·차 광택)
                if (_HiSize > 0)
                {
                    half h = dot(s.Normal, normalize(lightDir + viewDir));
                    half hi = smoothstep(1 - _HiSize, 1 - _HiSize + 0.03, h) * lit;
                    c.rgb += _HiColor.rgb * _LightColor0.rgb * hi * _HiStrength;
                }
            }
            else
            {
                // 전조등·가로등: 닿는 만큼만 더한다 (거리·원뿔 감쇠를 그대로 쓴다)
                c.rgb = s.Albedo * _LightColor0.rgb * smoothstep(0, _RampSoft, ndl) * atten;
            }
            c.a = s.Alpha;
            return c;
        }

        void surf (Input IN, inout SurfaceOutput o)
        {
            float2 uv = IN.uv_MainTex;
            if (_WorldUV > 0)
            {
                float3 lp = mul(_AlloWorldToRoot, float4(IN.worldPos, 1)).xyz;
                uv = (lp.xz + float2(0, _AlloTravel)) * _WorldUV;
            }
            fixed4 t = tex2D(_MainTex, uv) * _Color;
            o.Albedo = t.rgb;
            half rim = pow(1 - saturate(dot(normalize(IN.viewDir), o.Normal)), _RimPower);
            o.Emission = _RimColor.rgb * rim * _RimStrength * t.rgb + _EmissionColor.rgb;
            o.Alpha = 1;
        }
        ENDCG
    }
    Fallback "Diffuse"
}
