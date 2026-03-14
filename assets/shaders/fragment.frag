
#version 450
#extension GL_EXT_buffer_reference : require

layout (location = 0) in vec3 inColor;
layout (location = 0) out vec4 outFragColor;

struct  Vertex {
    vec4 position;
    vec4 color;
    vec4 uv;
};


layout(buffer_reference, std430) readonly buffer VertexBuffer {
    Vertex vertices[];
};


layout(push_constant, std430) uniform pc {
    VertexBuffer vertexBuffer;
    float time;
};
void main(){
  outFragColor = vec4(inColor,1);
}
