// 캐릭터 그림(빌보드). 그림에 이미 명암이 있으므로 장면 빛은 밝기만 살짝 따른다.
// 텍스처는 premultiplied alpha 로 올린다 (SpriteLoader.Prepare). 그래야 반투명 가장자리가 밉맵·필터링에서 검게 번지지 않는다.
Shader "Allo/Sprite"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1, 1, 1, 1)
        _Lit ("Scene light amount", Range(0, 1)) = 0.55
        _Floor ("Darkest", Range(0, 1)) = 0.42
        _GroundShade ("Ground shade", Range(0, 1)) = 0.5
    }
    SubShader
    {
        Tags { "Queue" = "Transparent" "RenderType" = "Transparent" "IgnoreProjector" = "True" }
        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            Cull Off
            ZWrite Off
            Blend One OneMinusSrcAlpha

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _Color;
            half _Lit, _Floor, _GroundShade;

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                half3 tint : TEXCOORD1;
                UNITY_FOG_COORDS(2)
            };

            v2f vert(appdata_base v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
                half3 light = ShadeSH9(half4(0, 1, 0, 1)) + _LightColor0.rgb * 0.8;
                half3 lit = clamp(light, _Floor, 1);
                o.tint = lerp(half3(1, 1, 1), lit, _Lit) * _Color.rgb;
                UNITY_TRANSFER_FOG(o, o.pos);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 c = tex2D(_MainTex, i.uv) * _Color.a;
                c.rgb *= i.tint;
                // 그림 아래쪽(발·배 밑)을 바닥 그늘처럼 어둡게: 밝은 배 밑이 어두운 시트 위에서 흰 판처럼 보이지 않게
                c.rgb *= lerp(1 - _GroundShade, 1, smoothstep(0.0, 0.16, i.uv.y));
                UNITY_APPLY_FOG_COLOR(i.fogCoord, c, fixed4(unity_FogColor.rgb * c.a, 0));
                return c;
            }
            ENDCG
        }
    }
}
