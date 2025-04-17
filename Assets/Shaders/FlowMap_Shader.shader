Shader "My URP Shader/Flow Map"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white"{}
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        [NoScaleOffset] _FlowMap ("Flow Map(RG Flow Vector, A Noise)", 2D) = "black"{}
        [Normal][NoScaleOffset] _NormalMap ("Normal Map", 2D) = "bump"{}
        _UJump ("U Jump", Range(-0.25, 0.25)) = 0
        _VJump ("V Jump", Range(-0.25, 0.25)) = 0
        _Tiling ("Tiling", Float) = 1
        _Speed ("Speed", Float) = 1
        _FlowStrength ("Flow Strength", Float) = 1
        _FlowOffset ("Flow Offset", Float) = 0
        _SpecularColor ("Specular Color", Color) = (1, 1, 1, 1)
        _Smoothness ("Smoothness", Range(1, 256)) = 10
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
        }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
        float4 _BaseMap_ST;
        half4 _BaseColor;
        half _UJump;
        half _VJump;
        float _Tiling;
        float _Speed;
        float _FlowStrength;
        float _FlowOffset;
        half4 _SpecularColor;
        float _Smoothness;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Tags
            {
                "LightMode"="UniversalForward"
            }
            
            HLSLPROGRAM
            #pragma vertex FlowMapVert
            #pragma fragment FlowMapFrag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Flow.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 tangentWS : TEXCOORD2;
                float3 positionWS : TEXCOORD3;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_FlowMap);
            SAMPLER(sampler_FlowMap);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            Varyings FlowMapVert(Attributes IN)
            {
                Varyings OUT;

                VertexPositionInputs vertexPositionInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionHCS = vertexPositionInputs.positionCS;
                OUT.positionWS = vertexPositionInputs.positionWS;
                
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                VertexNormalInputs vertexNormalInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
                OUT.normalWS = vertexNormalInputs.normalWS;
                OUT.tangentWS = float4(vertexNormalInputs.tangentWS, IN.tangentOS.w * GetOddNegativeScale());
                
                return OUT;
            }

            half4 FlowMapFrag(Varyings IN) : SV_Target
            {
                // Flow Uv
                float4 flowMap = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, IN.uv);
                float2 flowVector = flowMap.xy * 2.0 - 1.0;
                flowVector *= _FlowStrength;
                float noise = flowMap.w;
                float time = _Time.y * _Speed + noise;
                float2 jump = float2(_UJump, _VJump);
                float3 uvwA = FlowUvw(IN.uv, flowVector, jump, _Tiling, _FlowOffset, time, false);
                float3 uvwB = FlowUvw(IN.uv, flowVector, jump, _Tiling, _FlowOffset, time, true);

                // sample _BaseMap
                half4 baseMapA = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvwA.xy) * uvwA.z;
                half4 baseMapB = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uvwB.xy) * uvwB.z;
                half4 baseMap = baseMapA + baseMapB;
                
                // sample _NormalMap
                float3 normalMapA = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvwA.xy)) * uvwA.z;
                float3 normalMapB = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvwB.xy)) * uvwB.z;
                float3 normalTS = normalize(normalMapA + normalMapB);

                // Calculate actual normal
                float3 normalWS = normalize(IN.normalWS);
                float3 tangentWS = normalize(IN.tangentWS.xyz);
                float3 bitangentWS = normalize(cross(normalWS, tangentWS) * IN.tangentWS.w);
                float3x3 T_tbn = float3x3(tangentWS, bitangentWS, normalWS);
                float3 nDirWS = normalize(mul(normalTS, T_tbn));

                // Calculate Lighting
                Light mainLight = GetMainLight();
                float3 lDirWS = mainLight.direction;
                float3 vDirWS = normalize(GetCameraPositionWS() - IN.positionWS);
                float3 hDirWS = normalize(lDirWS + vDirWS);
                // diffuse
                float NdotL = saturate(dot(nDirWS, lDirWS));
                half3 diffuse = mainLight.color * NdotL * baseMap * _BaseColor;
                // specular
                float NdotH = saturate(dot(nDirWS, hDirWS));
                float blinPhong = pow(NdotH, _Smoothness);
                half3 specular = mainLight.color * blinPhong * _SpecularColor;

                half3 finalRGB = diffuse + specular;
                
                return half4(finalRGB, 1.0);
            }
            
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            
            Tags
            {
                "LightMode"="DepthNormals"
            }
            
            ZWrite On
            
            HLSLPROGRAM
            #pragma vertex DepthNormalsVert
            #pragma fragment DepthNormalsFrag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normal : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            Varyings DepthNormalsVert(Attributes IN)
            {
                Varyings OUT;

                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normal);
                
                return OUT;
            }

            half4 DepthNormalsFrag(Varyings IN) : SV_Target
            {
                return half4(NormalizeNormalPerPixel(IN.normalWS), 0.0);
            }
            
            ENDHLSL
        }
    }
}
