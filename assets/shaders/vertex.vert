// vertex.glsl
#version 450
#extension GL_EXT_buffer_reference : require

// layout(location = 0) in vec2 inPosition;
// layout(location = 1) in vec3 inColor;

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

layout(location = 0) out vec3 fragColor;

const vec3 positions[3] = vec3[](
    vec3(0.0, 0.0, 1.0),
    vec3(0.5, 0.5, 0.0),
    vec3(-0.5, 0.5, 0.0)
);

const vec3 colors[3] = vec3[](
    vec3(1.0, 0.0, 0.0),
    vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, 1.0)
);

void main() {
    float x = positions[gl_VertexIndex].x + sin(time/10)/2;
    float y = positions[gl_VertexIndex].y + cos(time/10)/2;
    float z = positions[gl_VertexIndex].z + tan(time/100)/2;
    gl_Position = vec4(x,y, z, 1.0);
    fragColor = colors[gl_VertexIndex] * (cos(time/10) + 1)/2;
}

