// vertex.glsl
#version 450
#extension GL_EXT_buffer_reference : require

// layout(location = 0) in vec2 inPosition;
// layout(location = 1) in vec3 inColor;

struct Vertex {
  vec4 position;
  vec4 color;
  vec4 uv;
};

layout(buffer_reference, std430) readonly buffer VertexBuffer {
  Vertex vertices[];
};

layout(push_constant, std430) uniform pc {
  VertexBuffer vertexBuffer;
} PushConstant;

layout(location = 0) out vec3 fragColor;

void main() {
  Vertex v = PushConstant.vertexBuffer.vertices[gl_VertexIndex];
  float time = 1;
  float x = v.position.x + sin(time / 100) / 2;
  float y = v.position.y + cos(time / 100) / 2;
  float z = v.position.y + tan(time / 100) / 2;
  gl_Position = vec4(x, y, 0, 1.0);
  fragColor = vec3(x, y, z);
}
