#ifndef UNIVERSAL_FLOW_INCLUDED
#define UNIVERSAL_FLOW_INCLUDED

float3 FlowUvw(float2 uv, float2 flowVector, float2 jump, float tiling, float flowOffset, float time, bool flowB)
{
    float phaseOffset = flowB ? 0.5 : 0.0;
    float progress = frac(time + phaseOffset);
    float3 uvw;
    uvw.xy = uv - flowVector * (progress + flowOffset);
    uvw.xy *= tiling;
    uvw.xy += phaseOffset;
    uvw.xy += (time - progress) * jump;
    uvw.z = 1.0 - abs(1.0 - progress * 2.0);
    return uvw;
}

#endif