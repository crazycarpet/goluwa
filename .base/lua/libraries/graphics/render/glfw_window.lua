local gl = require("lj-opengl") -- OpenGL
local glfw = require("lj-glfw") -- window manager

local render = (...) or _G.render

function timer.GetSystemTime()
	return glfw.GetTime()
end

local calllbacks = {}

for line in glfw.header:gmatch("(.-)\n") do
	local name = line:match("(glfwSet.-Callback)")
	
	if name then
		local nice = "On" .. name:match("glfwSet(.-)Callback")
		nice = nice:gsub("Window", "")		
		
		calllbacks[nice] = glfw.lib[name]
	end
end

calllbacks.OnError(function(code, str) logn("[glfw] ", ffi.string(str)) end)
calllbacks.OnError = nil

calllbacks.OnMonitor(function() event.Call("OnMonitorConnected") end)
calllbacks.OnMonitor = nil

do -- window meta
	local META = metatable.CreateTemplate("render_window")

	function META:Remove()
		if self.OnRemove then self:OnRemove() end
		
		event.RemoveListener("Update", self)
		
		glfw.DestroyWindow(self.__ptr)
		
		utilities.MakeNULL(self)
	end

	local x = ffi.new("int[1]")
	local y = ffi.new("int[1]")
	
	function META:GetSize()
		glfw.GetWindowSize(self.__ptr, x, y)
		return Vec2(x[0], y[0])
	end
		
	function META:SetSize(pos)
		glfw.SetWindowSize(self.__ptr, pos:Unpack())
	end

	function META:SetTitle(title)
		glfw.SetWindowTitle(self.__ptr, title)
	end
	
	local x, y = ffi.new(sdl and "int[1]" or "double[1]"), ffi.new(sdl and "int[1]" or "double[1]")
	
	function META:GetMousePos()
		glfw.GetCursorPos(self.__ptr, x, y)			
		return Vec2(x[0], y[0])
	end

	function META:SetMousePos(pos)
		glfw.SetCursorPos(self.__ptr, pos:Unpack())
	end
	
	function META:HasFocus()
		return self.focused
	end
	
	function META:ShowCursor(b)
		if b then
			glfw.SetInputMode(self.__ptr, glfw.e.GLFW_CURSOR, glfw.e.GLFW_CURSOR_NORMAL)
		else
			glfw.SetInputMode(self.__ptr, glfw.e.GLFW_CURSOR, glfw.e.GLFW_CURSOR_HIDDEN)
		end
		self.cursor_visible = b
	end	
	
	function META:IsCursorVisible()
		return self.cursor_visible
	end

	function META:SetMouseTrapped(b)
		self.mouse_trapped = b
		
		glfw.SetInputMode(self.__ptr, glfw.e.GLFW_CURSOR, b and glfw.e.GLFW_CURSOR_DISABLED or glfw.e.GLFW_CURSOR_NORMAL)
		
		self:UpdateMouseDelta()
	end

	function META:GetMouseTrapped()
		return self.mouse_trapped
	end
	
	function META:GetMouseDelta()
		return self.mouse_delta or Vec2()
	end
		 
	function META:UpdateMouseDelta()	
		local pos = self:GetMousePos()
	
		if self.last_mpos then
			self.mouse_delta = (pos - self.last_mpos)
		end
		
		self.last_mpos = pos
		
		if self.mouse_trapped then
			--self:SetMousePos(self:GetSize() / 2)
		end
	end
	
	function META:MakeContextCurrent()
		glfw.MakeContextCurrent(self.__ptr) 
	end
	
	function META:SwapBuffers()
		glfw.SwapBuffers(self.__ptr)
	end
	
	function META:SwapInterval(b)
		glfw.SwapInterval(b and 1 or 0)
	end

	function META:OnUpdate(delta)
		
	end
	
	function META:OnFocus(focused)
		
	end
	
	function META:OnClose()
		
	end
	
	function META:OnCursorPos(x, y)

	end
	
	function META:OnFileDrop(paths)
	
	end
	
	function META:OnCharInput(str)
	
	end
	
	function META:OnKeyInput(key, press)
	
	end
	
	function META:OnKeyInputRepeat(key, press)
	
	end
	
	function META:OnMouseInput(key, press)
		
	end
	
	function META:OnMouseScroll(x, y)
	
	end
	
	function META:OnCursorEnter()
	
	end
	
	function META:OnRefresh()
		
	end
	
	function META:OnFramebufferResized(width, height)
	
	end
	
	function META:OnMove(x, y)
	
	end
	
	function META:OnIconify()
	
	end
	
	function META:OnResize(width, height)
		
	end
	
	function META:OnTextEditing(str)
		
	end
	
	local count = ffi.new("int[1]")
	
	function META:GetJoystickState(i)
		if glfw.JoystickPresent(i) == 0 then return end
			
		local out = {axes = {}, buttons = {}}
		if glfw.JoystickPresent(i) ~= 0 then
		
		out.name = ffi.string(glfw.GetJoystickName(i))
	
		local axes = glfw.GetJoystickAxes(i, count)
		for i = 0, count[0] do
			out.axes[i+1] = axes[i]
		end
		
		local buttons = glfw.GetJoystickButtons(i, count)
		for i = 0, count[0] do
			out.buttons[i+1] = buttons[i]
		end
		
		return out
	end
	end
		
	function render.CreateWindow(width, height, title)	
		width = width or 800
		height = height or 600
		title = title or ""
		
		glfw.Init()
		
		--glfw.WindowHint(glfw.e.GLFW_CONTEXT_VERSION_MAJOR, 2)
		--glfw.WindowHint(glfw.e.GLFW_CONTEXT_VERSION_MINOR, 0)
		--glfw.WindowHint(glfw.e.GLFW_CLIENT_API, glfw.e.GLFW_OPENGL_ES_API)
		
		glfw.WindowHint(glfw.e.GLFW_SAMPLES, 4)

		local ptr = glfw.CreateWindow(width, height, title, nil, nil)
		glfw.MakeContextCurrent(ptr)
		gl.GetProcAddress = glfw.GetProcAddress

		logn("glfw version: ", ffi.string(glfw.GetVersionString()))
		
		-- this needs to be initialized once after a context has been created..
		if gl and gl.InitMiniGlew and not gl.gl_init then
			gl.gl_init = true
			gl.InitMiniGlew()
		end

		local self = META:New()
		
		self.last_mpos = Vec2()
		self.mouse_delta = Vec2()
		self.__ptr = ptr
				
		event.AddListener("Update", self, function(dt)
			self:UpdateMouseDelta()
			self:OnUpdate(dt)
		end)
		
		do -- calllbacks
			self.availible_callbacks = {}

			for nice, func in pairs(calllbacks) do
				self.availible_callbacks[nice] = nice
				
				local event_name = "Window" .. nice:sub(3)
				
				if nice == "OnDrop" then
					func(ptr, function(ptr, count, strings)
						local t = {}
						for i = 1, count do
							t[i] = ffi.string(strings[i-1])
						end
						
						if self:OnFileDrop(self, t) ~= false then
							event.Call("WindowFileDrop", self, t)
						end
					end)					
				elseif nice == "OnChar" then
					func(ptr, function(ptr, uint)
						local char = utf8.char(uint)
						
						if self:OnCharInput(self, char) ~= false then
							event.DeferExecution(function()
								event.Call("WindowCharInput", self, char)
							end)
						end
					end)					
				elseif nice == "OnKey" then
					func(ptr, function(ptr, key_, scancode, action, mods)
						local key, press = glfw.KeyToString(key_), action == glfw.e.GLFW_PRESS or action == glfw.e.GLFW_REPEAT
						
						if self:OnKeyInputRepeat(key, press) ~= false then
							event.Call("WindowKeyInputRepeat", self, key, press)
						end
						
						if action ~= glfw.e.GLFW_REPEAT then 
							local key, press = glfw.KeyToString(key_), action == glfw.e.GLFW_PRESS
							
							if self:OnKeyInput(key, press) ~= false then
								event.Call("WindowKeyInput", self, key, press)
							end
						end
					end)
				elseif nice == "OnMouseButton" then
					func(ptr, function(ptr, button, action, mods)
						local key, press = glfw.MouseToString(button), action == glfw.e.GLFW_PRESS
						
						if self:OnMouseInput(key, press) ~= false then
							event.Call("WindowMouseInput", self, key, press)
						end
					end)
				elseif nice == "OnScroll" then
					func(ptr, function(ptr, x, y)
						if self:OnMouseScroll(x, y) ~= false then	
							event.Call("WindowMouseScroll", self, x, y)
						end
					end)
				elseif nice == "OnClose" then
					func(ptr, function(ptr)
						if self:OnClose() ~= false then
							event.Call(event_name, self)
						end
						self:Remove()
					end)
				elseif nice == "OnFocus" then
					func(ptr, function(ptr, b)	
						self.focused = b
						if self:OnFocus() ~= false then
							event.Call(event_name, self, b)
						end
					end)
				elseif nice == "OnFramebufferSize" then
					func(ptr, function(ptr, w, h)	
						if self:OnFramebufferResized(w, h) ~= false then
							event.Call("WindowFramebufferResized", self, w, h)
						end
					end)
				elseif nice == "OnSize" then
					func(ptr, function(ptr, w, h)	
						if self:OnResize(w, h) ~= false then
							event.Call("WindowResized", self, w, h)
						end
					end)
				elseif nice == "OnPos" then
					func(ptr, function(ptr, x, y)	
						if self:OnMove(x, y) ~= false then
							event.Call("WindowMoved", self, w, h)
						end
					end)
				else
					func(ptr, function(ptr, ...)
						if not self[nice] then print(nice) return end 
						if self[nice](self, ...) ~= false then
							event.Call(event_name, self, ...)
						end
					end)
				end
			end
		end
		
		if not render.current_window:IsValid() then
			render.current_window = self
		end
				
		render.context_created = true
		render.Initialize()
				
		return self
	end
end

-- this is needed regardless of whether a window exists or not or else the console will freeze..???
event.CreateTimer("glfw_pollevents", 1/60, 0, function() glfw.PollEvents() end)