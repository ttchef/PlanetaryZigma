// vertex.glsl
#version 450
#extension GL_EXT_buffer_reference : require

// layout(location = 0) in vec2 inPosition;
// layout(location = 1) in vec3 inColor;

layout(set = 0, binding = 0) uniform sceneData {
  mat4 proj_view;
  float time;
} scene_data;

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
  float time = scene_data.time;
  float x = v.position.x;
  float y = v.position.y;
  float z = v.position.z;
  gl_Position = vec4(x, y, z, 1.0) * scene_data.proj_view;
  fragColor = vec3((sin(time / 10) + 1) / 2, y, z);
}
