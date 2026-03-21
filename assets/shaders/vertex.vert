// vertex.glsl
#version 450
#extension GL_EXT_buffer_reference : require

layout(set = 0, binding = 0) uniform sceneData {
  mat4 proj_view;
  float time;
} scene_data;

struct Vertex {
  vec3 position;
  float uv_x;
  vec3 normal;
  float uv_y;
  vec4 color;
};

layout(buffer_reference, std430) readonly buffer VertexBuffer {
  Vertex vertices[];
};

layout(push_constant, std430) uniform pc {
  VertexBuffer vertexBuffer;
} PushConstant;

layout(location = 0) out vec3 fragColor;
layout(location = 1) out vec2 outUv;

void main() {
  Vertex v = PushConstant.vertexBuffer.vertices[gl_VertexIndex];
  float time = scene_data.time;
  float x = v.position.x;
  float y = v.position.y;
  float z = v.position.z;
  // gl_Position = scene_data.proj_view * vec4(x, y, -1 * (sin(time / 10) + 1) / 2 - 0.1, 1.0);
  gl_Position = scene_data.proj_view * vec4(x, y, z * sin(scene_data.time / 10) - 1.2, 1.0);

  vec3 uv = vec3(v.uv_x, v.uv_y, v.uv_x);
  vec3 col = 0.5 + 0.5 * cos(scene_data.time / 100 + uv + vec3(0, 2, 4));

  // fragColor = vec3((sin(time / 10) + 1) / 2, y, z);
  outUv = uv.xy;
  fragColor = col;
}
