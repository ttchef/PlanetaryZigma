#version 450
#extension GL_EXT_buffer_reference : require
layout(set = 0, binding = 0) uniform SceneData {
	mat4 view;
	mat4 proj;
	mat4 viewproj;
	vec4 ambientColor;
	vec4 sunlightDirection; //w for sun power
	vec4 sunlightColor;
} sceneData;

struct Vertex {
	vec3 position;
	float uv_x;
	vec3 normal;
  float uv_y;
	vec4 color;
}; 

layout(buffer_reference, std430) readonly buffer VertexBuffer{ 
	Vertex vertices[];
};

//push constants block
layout(push_constant) uniform constants {
	mat4 render_matrix;
	VertexBuffer vertexBuffer;
} PushConstants;

void main(){
  Vertex v = PushConstants.vertexBuffer.vertices[gl_VertexIndex];
  vec4 position = vec4(v.position, 1.0f);
  gl_Position = sceneData.viewproj * PushConstants.render_matrix * position;
}
