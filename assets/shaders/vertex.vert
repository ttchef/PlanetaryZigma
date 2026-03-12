// vertex.glsl
#version 450
#extension GL_EXT_buffer_reference : require

// layout(location = 0) in vec2 inPosition;
// layout(location = 1) in vec3 inColor;

// struct  Vertex {
//     vec4 position;
//     vec4 color;
//     vec4 uv;
// };
//
//
// layout(buffer_reference, std430) readonly buffer VertexBuffer {
//     Vertex vertices[];
// };
//
//
// layout(push_constant, std430) uniform pc {
//     VertexBuffer vertexBuffer;
//     float time;
// };

layout(location = 0) out vec3 fragColor;

const vec2 positions[3] = vec2[](
    vec2(0.5, 0.0),
    vec2(0.5, 0.5),
    vec2(-0.5, 0.5)
);

const vec3 colors[3] = vec3[](
    vec3(1.0, 0.0, 0.0),
    vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, 1.0)
);

void main() {
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
    fragColor = colors[gl_VertexIndex];
}

