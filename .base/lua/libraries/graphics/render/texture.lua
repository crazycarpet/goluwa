local gl = require("lj-opengl") -- OpenGL

local render = (...) or _G.render

render.textures = render.textures or setmetatable({}, { __mode = 'v' })

function render.GetTextures()
	return render.textures
end


local diffuse_suffixes = {
	"_diff",
	"_d",
}

function render.FindTextureFromSuffix(path, ...)
	path = path:lower()
	
	local suffixes = {...}

	-- try to find the normal texture
	for _, suffix in pairs(suffixes) do
		local new = path:gsub("(.+)(%.)", "%1" .. suffix .. "%2")
		
		if new ~= path and vfs.Exists(new) then
			return new
		end
	end
	
	-- try again without the __diff suffix
	for _, diffuse_suffix in pairs(diffuse_suffixes) do
		for _, suffix in pairs(suffixes) do
			local new = path:gsub(diffuse_suffix .. "%.", suffix ..".")
			
			if new ~= path and vfs.Exists(new) then
				return new
			end
		end
	end
end

do -- texture binding
	do
		local base = gl.e.GL_TEXTURE0 
		local last
		function render.ActiveTexture(id)
			if id ~= last then
				gl.ActiveTexture(base + id)
				last = id
			end
		end
	end

	do
		local last
		
		function render.BindTexture(tex)			
			if tex ~= last then				
				gl.BindTexture(tex.format.type, tex.override_texture and tex.override_texture.id or tex.id) 				
				last = tex
			end
		end
	end
end

do -- texture object
	local CHECK_FIELD = function(t, str) 
		if type(str) == "number" then
			return str
		end
		
		return render.TranslateStringToEnum("texture", t, str, 5) 
	end

	local META = metatable.CreateTemplate("texture")
	
	function META:__tostring()
		return ("texture[%s]"):format(self.id)
	end
	
	function META:GetSize()
		return self.size
	end

	function META:Download(level, format)
		local f = self.format
		local buffer = self:CreateBuffer()

		gl.BindTexture(f.type, self.id)
			gl.PixelStorei(gl.e.GL_PACK_ALIGNMENT, f.stride)
			gl.PixelStorei(gl.e.GL_UNPACK_ALIGNMENT, f.stride)
			gl.GetTexImage(f.type, level or 0, f.upload_format, format or f.format_type, buffer)
		gl.BindTexture(f.type, 0)

		return buffer
	end
	
	function META:CreateBuffer()
		-- +1 to height cause there seems to always be some noise on the last line :s
		local length = self.size.w * (self.size.h+1) * self.format.stride
		local buffer = ffi.malloc(self.format.buffer_type, length)
		ffi.fill(buffer, length)
		--local buffer = ffi.new(self.format.buffer_type.."[?]", length)
		
		return buffer, length
	end
	
	function META:Clear(val, level)	
		level = level or 0
		local f = self.format
		
		local buffer, length = self:CreateBuffer()

		ffi.fill(buffer, length, val)
		
		gl.BindTexture(f.type, self.id)			

		gl.TexSubImage2D(
			f.type, 
			level, 
			0,
			0,
			self.size.w,
			self.size.h, 
			f.upload_format, 
			f.format_type, 
			buffer
		)
		
		if f.mip_map_levels > 0 then
			gl.GenerateMipmap(f.type)
		end
		
		gl.BindTexture(f.type, 0)			
				
		return self
	end
	
	function META:UpdateFormat()
		local f = self.format	
		
		f.min_filter = CHECK_FIELD("min_filter", f.min_filter) or gl.e.GL_LINEAR_MIPMAP_LINEAR
		f.mag_filter = CHECK_FIELD("mag_filter", f.mag_filter) or gl.e.GL_LINEAR				
		
		f.wrap_s = CHECK_FIELD("wrap", f.wrap_s) or gl.e.GL_REPEAT
		f.wrap_t = CHECK_FIELD("wrap", f.wrap_t) or gl.e.GL_REPEAT
		
		do
			local largest = ffi.new("float[1]")
			gl.GetFloatv(gl.e.GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, largest)
			f.anisotropy = CHECK_FIELD("anisotropy", f.anisotropy) or largest[0]
		end
		
		if f.type == gl.e.GL_TEXTURE_3D then
			f.wrap_r = CHECK_FIELD("wrap", f.wrap_r) or gl.e.GL_REPEAT
		end

		for k,v in pairs(render.GetAvaibleEnums("texture", "parameters")) do
			if f[k:lower()] then
				gl.TexParameterf(f.type, v, f[k:lower()])
			end
		end
		
		-- only really used for caching..
		self.format_string = {}
		for k,v in pairs(f) do
			table.insert(self.format_string, tostring(k) .. " == " .. tostring(v))
		end
		self.format_string = table.concat(self.format_string, "\n")		
	end 
	
	function META:Upload(buffer, format_override)
		local f = format_override or self.format		
		local f2 = self.format
		
		if typex(buffer) == "texture" then
			f = buffer.format
			buffer = buffer:Download()
		end
		
		if format_override then
			for k, v in pairs(format_override) do
				format_override[k] = CHECK_FIELD(k, v) or v
			end
		end
		
		gl.BindTexture(f2.type, self.id)			
	
			gl.PixelStorei(gl.e.GL_PACK_ALIGNMENT, f.stride or f2.stride)
			gl.PixelStorei(gl.e.GL_UNPACK_ALIGNMENT, f.stride or f2.stride)
				
			self:UpdateFormat()
		
			if f2.clear then
				if f2.clear == true then
					self:Clear(nil)
				else
					self:Clear(f2.clear)
				end
			end
			
			if self.compressed then
				gl.CompressedTexSubImage2D(
					f2.type, 
					f.level or 0, 
					f.x or 0, 
					f.y or 0,
					f.w or self.size.w, 
					f.h or self.size.h, 
					f.upload_format or f2.upload_format, 
					f.size, 
					buffer
				)
			else
				gl.TexSubImage2D(
					f2.type, 
					f.level or 0, 
					f.x or 0, 
					f.y or 0,
					f.w or self.size.w, 
					f.h or self.size.h, 
					f.upload_format or f2.upload_format, 
					f.format_type or f2.format_type,
					buffer
				)
			end
			
			if f2.mip_map_levels > 0 then
				gl.GenerateMipmap(f2.type)
			end
			
		gl.BindTexture(f2.type, 0)
		
		return self
	end
	
	local colors = ffi.new("char[4]")

	function META:Fill(callback, write_only, read_only)
		check(callback, "function")
		
		if write_only == nil then
			write_only = true
		end
		
		local width = self.size.w
		local height = self.size.h		
		local stride = self.format.stride
		local x, y = 0, 0
		

		local buffer
		
		if write_only then
			buffer = self:CreateBuffer()
		else
			buffer = self:Download()
		end	
	
		for y = 0, height-1 do
		for x = 0, width-1 do
			local pos = (y * width + x) * stride
			
			if write_only then
				colors[0], colors[1], colors[2], colors[3] = callback(x, y, pos)
			else
				local temp = {}
				for i = 0, stride-1 do
					temp[i] = buffer[pos+i]
				end
				if read_only then
					if callback(x, y, pos, unpack(temp)) ~= nil then return end
				else
					colors[0], colors[1], colors[2], colors[3] = callback(x, y, pos, unpack(temp))
				end
			end
		
			if not read_only then
				for i = 0, stride-1 do
					buffer[pos+i] = colors[i]
				end
			end
		end
		end

		if not read_only then
			self:Upload(buffer)
		end
		
		return self
	end
	
	local cache = {}
	local fbos = {}
	
	function META:Shade(fragment_shader, vars)
		
		if not cache[fragment_shader] then
		
			local data = {
				name = "shade_texture_" .. self.id .. "_" .. tostring(timer.GetSystemTime()),
				shared = {
					uniform = vars,
				},
				
				vertex = {
					uniform = {
						pwm_matrix = "mat4",
					},			
					attributes = {
						{pos = "vec2"},
						{uv = "vec2"},
					},	
					source = "gl_Position = pwm_matrix * vec4(pos, 0, 1);"
				},
				
				fragment = { 
					uniform = {
						self = self,
						size = "vec2",
					},		
					attributes = {
						{uv = "vec2"},
					},			
					source = fragment_shader,
				} 
			} 
				
			local shader = render.CreateShader(data)
			shader.pwm_matrix = render.GetPVWMatrix2D

			local mesh = shader:CreateVertexBuffer({
				{pos = {0, 0}, uv = {0, 1}},
				{pos = {0, 1}, uv = {0, 0}},
				{pos = {1, 1}, uv = {1, 0}},

				{pos = {1, 1}, uv = {1, 0}},
				{pos = {1, 0}, uv = {1, 1}},
				{pos = {0, 0}, uv = {0, 1}},
			})
			
			local fb = render.CreateFrameBuffer(4, 4)
			
			cache[fragment_shader] = function(self, vars)				
				do -- bind uniforms
					shader.self = self
					shader.size = Vec2(surface.GetScreenSize())
					
					for k,v in pairs(vars) do
						shader[k] = v
					end				
				end
				

					fb:Begin()
						gl.FramebufferTexture2D(gl.e.GL_FRAMEBUFFER, gl.e.GL_COLOR_ATTACHMENT0_EXT, gl.e.GL_TEXTURE_2D, self.id, 0)
						gl.ReadBuffer(gl.e.GL_COLOR_ATTACHMENT0_EXT)
							
							render.Start2D(0, 0, self.w, self.h)
								fb:Clear(1,0,0,1)
								shader:Bind()
								mesh:Draw()
							render.End2D()
							
						--gl.FramebufferTexture2D(gl.e.GL_FRAMEBUFFER, gl.e.GL_COLOR_ATTACHMENT0_EXT, gl.e.GL_TEXTURE_2D, 0, 0)								
					fb:End()			
			end
		end
		
		cache[fragment_shader](self, vars)
	end
	
	local SUPPRESS_GC = false
	
	function META:Replace(data, w, h)
		gl.DeleteTextures(1, ffi.new("GLuint[1]", self.id))
		
		SUPPRESS_GC = true
		local new = render.CreateTexture(w, h, data, self.format)
		SUPPRESS_GC = false
		
		for k, v in pairs(new) do
			self[k] = v
		end
	end
	
	function META:Remove()
		if self.format.no_remove then return end
		gl.DeleteTextures(1, ffi.new("GLuint[1]", self.id))
		utilities.MakeNULL(self)
	end
	
	function META:IsLoading()
		return self.loading
	end
	
	function META:MakeError()
		local err = render.GetErrorTexture()
		buffer = err:Download()
		w = err.w
		h = err.h
		self:Replace(buffer, w, h)
		self.loading = nil
		self.override_texture = nil
	end
	
	function render.CreateTexture(width, height, buffer, format)
		if type(width) == "string" and not buffer and not format and (not height or type(height) == "table") then
			return render.CreateTextureFromPath(width, height)
		end
										
		local buffer_size
		
		if type(width) == "table" and not height and not buffer and not format then
			format = width.parameters
			buffer = width.buffer
			height = width.height
			buffer_size = width.size
			width = width.width
		end
		
		check(width, "number")
		check(height, "number")
		check(buffer, "nil", "cdata")
		check(format, "table", "nil")
				
		if width == 0 or height == 0 then
			errorf("bad texture size (w = %i, h = %i)", 2, width, height)
		end
				
		format = format or {}

		for k, v in pairs(format) do
			format[k] = CHECK_FIELD(k, v) or v
		end
		
		format.type = format.type or gl.e.GL_TEXTURE_2D
		format.upload_format = format.upload_format or gl.e.GL_BGRA
		format.internal_format = format.internal_format or gl.e.GL_RGBA8
		format.format_type = format.format_type or gl.e.GL_UNSIGNED_BYTE
		format.filter = format.filter ~= nil
		format.stride = format.stride or 4
		format.buffer_type = format.buffer_type or "unsigned char"
		format.channel = format.channel or 0

		format.mip_map_levels = format.mip_map_levels or 3 --ATI doesn't like level under 3
		
		-- create a new texture
		local id = gl.GenTexture()

		local self = META:New(
			{
				id = id, 
				size = Vec2(width, height), 
				format = format,
				w = width,
				h = height,
			},
			SUPPRESS_GC
		)
		
		if gl.FindInEnum(format.upload_format, "compress") or gl.FindInEnum(format.internal_format, "compress") then	
			self.compressed = true
		end		
		
		self.texture_channel = gl.e.GL_TEXTURE0 + format.channel
		self.texture_channel_uniform = format.channel
		
		gl.BindTexture(format.type, self.id)

		self:UpdateFormat()
		
		if self.compressed then
			gl.CompressedTexImage2D(
				format.type, 
				format.mip_map_levels, 
				format.upload_format, 
				self.size.w, 
				self.size.h, 
				0, 
				buffer_size, 
				nil
			)
		elseif gl.TexStorage2D then
			gl.TexStorage2D(
				format.type, 
				format.mip_map_levels, 
				format.internal_format, 
				self.size.w, 
				self.size.h
			)
		else
			gl.TexImage2D(
				format.type,
				format.mip_map_levels,
				format.stride,
				self.size.w,
				self.size.h,
				0,
				format.format,
				format.internal_format,
				nil
			)
				
		end
		
		if buffer then	
			self:Upload(buffer, {size = buffer_size})
		end
		
		gl.BindTexture(format.type, 0)
						
		if render.debug then
			logf("creating texture w = %s h = %s buffer size = %s\n", self.w, self.h, utilities.FormatFileSize(buffer and ffi.sizeof(buffer) or 0)) --The texture size was never broken... someone used two non-existant variables w,h
		end
		
		render.textures[id] = self
		
		return self
	end
end

render.texture_path_cache = setmetatable({}, { __mode = 'v' })

function render.CreateTextureFromPath(path, format)
	if render.texture_path_cache[path] then 
		return render.texture_path_cache[path] 
	end
			
	format = format or {}
	
	local loading = render.GetLoadingTexture()
	local self = render.CreateTexture(loading.w, loading.h, nil, format)

	self.override_texture = loading
	self.loading = true

	if not vfs.ReadAsync(path, function(data)
		self.loading = false
		self.override_texture = nil
		
		local buffer, w, h, info = render.DecodeTexture(data, path)
		
		if buffer == nil or w == 0 or h == 0 then
			self:MakeError()
		else
			if info.format then
				table.merge(self.format, info.format)
				self:UpdateFormat()
			end
			
			render.texture_path_cache[path] = self			
			vfs.UncacheAsync(path)
			
			self:Replace(buffer, w, h)
		end
		
		self.decode_info = info
	end) then
		self:MakeError()
	end
	
	return self
end


render.texture_decoders = render.texture_decoders or {}

function render.AddTextureDecoder(id, callback)
	render.RemoveTextureDecoder(id)
	table.insert(render.texture_decoders, {id = id, callback = callback})
end

function render.RemoveTextureDecoder(id)
	for k,v in pairs(render.texture_decoders) do
		if v.id == id then
			table.remove(render.texture_decoders)
			return true
		end
	end
end

function render.DecodeTexture(data, path_hint)
	for i, decoder in ipairs(render.texture_decoders) do
		local ok, buffer, w, h, info = pcall(decoder.callback, data, path_hint)
		if ok then 
			if buffer and w then
				return buffer, w, h, info or {}
			elseif not w:find("unknown format") then
				logf("[render] %s failed to decode %s: %s\n", decoder.id, path_hint or "", w)
			end
		else
			logf("[render] decoder %q errored: %s\n", decoder.id, buffer)
		end
	end
end

Texture = render.CreateTexture -- reload!
