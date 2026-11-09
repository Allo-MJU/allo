// 툰 셰이딩: 빛·그림자 2단(부드러운 경계), 그림자는 푸른 기운, 가장자리 빛(림), 선택적 외곽선.
// _WorldUV > 0 이면 텍스처를 월드 xz 로 깐다 (넓은 땅에 풀 무늬가 늘어나지 않게).
Shader "Allo/Toon"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Texture", 2D) = "white" {}
        _ShadowTint ("Shadow Tint", Color) = (0.62, 0.66, 0.9, 1)
        _RampSoft ("Ramp Softness", Range(0.001, 0.6)) = 0.12
        _RimColor ("Rim Color", Color) = (1, 0.97, 0.9, 1)
        _RimPower ("Rim Power", Range(0.5, 8)) = 3.5
        _RimStrength ("Rim Strength", Range(0, 1)) = 0.35
        _OutlineColor ("Outline Color", Color) = (0.16, 0.13, 0.12, 1)
        _OutlineWidth ("Outline Width (m)", Range(0, 0.1)) = 0
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
            float _OutlineWidth;
            fixed4 _OutlineColor;
            struct v2f { float4 pos : SV_POSITION; UNITY_FOG_COORDS(0) };
            v2f vert (appdata_base v)
            {
                v2f o;
                float4 p = v.vertex;
                p.xyz += normalize(v.normal) * _OutlineWidth;
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
        fixed4 _Color, _ShadowTint, _RimColor, _EmissionColor;
        half _RampSoft, _RimPower, _RimStrength;
        float _WorldUV;

        struct Input { float2 uv_MainTex; float3 worldPos; float3 viewDir; };

        half4 LightingToon (SurfaceOutput s, half3 lightDir, half3 viewDir, half atten)
        {
            half ndl = dot(s.Normal, lightDir);
            half4 c;
            if (_WorldSpaceLightPos0.w == 0)
            {
                // 해: 빛·그림자 2단, 그림자는 푸른 기운
                half lit = smoothstep(0, _RampSoft, ndl) * smoothstep(0.2, 0.55, atten);
                c.rgb = s.Albedo * _LightColor0.rgb * lerp(_ShadowTint.rgb, 1, lit);
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
            float2 uv = _WorldUV > 0 ? IN.worldPos.xz * _WorldUV : IN.uv_MainTex;
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
