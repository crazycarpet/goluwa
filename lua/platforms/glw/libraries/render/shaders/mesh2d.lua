local SHADER = {	
	vertex = {
		uniform = {
			camera_matrix = "mat4",
			model_matrix = "mat4",
		},			
		attributes = {
			{pos = "vec2"},
			{uv = "vec2"},
			{color = "vec4"},
		},
		source = "gl_Position = camera_matrix * model_matrix * vec4(pos, 0.0, 1.0);"
	},
	
	fragment = { 
		uniform = {
			global_color = Color(1, 1, 1, 1), 
			texture = "sampler2D",
		},
		attributes = {
			uv = "vec2",
			color = "vec4",
		},			
		source = [[
			out vec4 frag_color;

			vec4 texel = texture2D(texture, uv);

			void main()
			{	
				frag_color = texel * color * global_color;
			}
		]]
	} 
}

function render.CreateMesh2D(data)
	render.mesh_2d_shader = render.mesh_2d_shader or render.CreateSuperShader("mesh_2d", SHADER)
	
	local mesh = render.mesh_2d_shader:CreateVertexBuffer(data)
	
	mesh.model_matrix = render.GetModelMatrix
	mesh.camera_matrix = render.GetCameraMatrix
	
	return mesh
end

-- for reloading
if render.mesh_2d_shader then
	render.mesh_2d_shader = render.CreateSuperShader("mesh_2d", SHADER)
	surface.Initialize()
end