local event = _G.event or {}

e.EVENT_DESTROY = "??|___EVENT_DESTROY___|??" -- unique what

event.active = event.active or {}
event.errors = event.errors or {}
event.profil = event.profil or {}
event.destroy_tag = e.EVENT_DESTROY

function event.AddListener(event_type, id, callback, config)	
	if type(event_type) == "table" then
		config = event_type
	end
		
	if not callback and type(id) == "function" then
		callback = id
		id = nil
	end
		
	config = config or {}
	
	config.event_type = config.event_type or event_type
	config.id = config.id or id
	config.callback = config.callback or callback
	config.priority = config.priority or 0
	
	-- useful for initialize events
	if config.id == nil then
		config.id = tostring(callback)
		config.remove_after_one_call = true
	end
	
	event.RemoveListener(config.event_type, config.id)
	
	event.active[config.event_type] = event.active[config.event_type] or {}
	
	table.insert(event.active[config.event_type], config)
		
	event.SortByPriority()
end

function event.RemoveListener(event_type, id)

	if type(event_type) == "table" then
		id = id or event_type.id
		event_type = event_type or event_type.event_type
	end

	if id ~= nil and event.active[event_type] then
		for index, val in pairs(event.active[event_type]) do
			if id == val.id then
				-- we can't use table.remove here because this might be called during
				-- an event which will mess up the ipairs loop and skip all the other events
				-- of the same type
				event.active[event_type][index] = nil
				
				do -- repair the table
					local temp = {}
					
					for k,v in pairs(event.active[event_type]) do
						table.insert(temp, v)
						event.active[event_type][k] = nil
					end
					
					for k,v in pairs(temp) do
						table.insert(event.active[event_type], v)
					end
				end
				
				break
			end
		end
	else
		--logn(("Tried to remove non existing event '%s:%s'"):format(event, tostring(unique)))
	end
	
	event.SortByPriority()
end

function event.SortByPriority()
	for key, tbl in pairs(event.active) do
		local new = {}
		for k,v in pairs(tbl) do table.insert(new, v) end
		table.sort(new, function(a, b) return a.priority > b.priority end)
		event.active[key] = new
	end
end

function event.GetTable()
	return event.active
end

local blacklist = {
	Update = true,
	PreDisplay = true,
	NetworkMessageReceived = true,
	NetworkPacketReceived = true,
	PostDisplay = true,
	Draw2D = true,
	Draw3DGeometry = true,
	Draw3DLights = true,
	DrawHUD = true,
	PostDrawMenu = true,
	PreDrawMenu = true,
}

local status, a,b,c,d,e,f,g,h
local time = 0

function event.Call(event_type, ...)
	if event.debug then
		if not blacklist[event_type] then
			event.call_count = event.call_count or 0
				print(event.call_count, event_type, ...)
			event.call_count = event.call_count + 1
		end
	end
	if event.active[event_type] then
		for index, data in ipairs(event.active[event_type]) do
			
			if data.self_arg then
				if data.self_arg:IsValid() then
					if data.self_arg_with_callback then
						status, a,b,c,d,e,f,g,h = xpcall(data.callback, data.on_error or system.OnError, ...)
					else
						status, a,b,c,d,e,f,g,h = xpcall(data.callback, data.on_error or system.OnError, data.self_arg, ...)
					end
				else
					event.RemoveListener(event_type, data.id)

					event.active[event_type][index] = nil
					event.SortByPriority()
					logf("event [%q][%q] removed because self is invalid\n", event_type, data.unique)
					return
				end
			else
				status, a,b,c,d,e,f,g,h = xpcall(data.callback, data.on_error or system.OnError, ...)
			end
			
			if a == event.destroy_tag or data.remove_after_one_call then
				event.RemoveListener(event_type, data.id)
			else
				if status == false then		
					if type(data.on_error) == "function" then
						data.on_error(a, event_type, data.id)
					else
						event.RemoveListener(event_type, data.id)
						logf("event [%q][%q] removed\n", event_type, data.id)
					end

					event.errors[event_type] = event.errors[event_type] or {}
					table.insert(event.errors[event_type], {id = data.id, error = a, time = os.date("*t")})
				end

				if a ~= nil then
					return a,b,c,d,e,f,g,h
				end
			end
		end
	end
end

function event.GetErrorHistory()
	return event.errors
end

function event.DisableAll()
	if event.enabled == false then
		logn("events are already disabled.")
	else
		event.enabled = true
		event.__backup_events = table.copy(event.GetTable())
		table.empty(event.GetTable())
	end
end

function event.EnableAll()
	if event.enabled == true then
		logn("events are already enabled.")
	else
		event.enabled = false
		table.merge(event.GetTable(), event.__backup_events)
		event.__backup_events = nil
	end
end

function event.Dump()
	local h=0
	for k,v in pairs(event.GetTable()) do
		logn("> "..k.." ("..table.Count(v).." events):")
		for name,data in pairs(v) do
			h=h+1
			logn("   \""..name.."\" \t "..tostring(debug.getinfo(data.callback).source)..":")
			logn(" Line:"..tostring(debug.getinfo(data.callback).linedefined))
		end
		logn("")
	end
	logn("")
	logn(">>> Total events: "..h..".")
end

do -- timers
	event.timers = event.timers or {}

	do -- timer meta
		local META = {}
		META.__index = META
		
		function META:Pause()
			self.paused = true
		end
		function META:Start()
			self.paused = false
		end
		function META:IsPaused()
			return self.paused
		end
		function META:SetRepeats(num)
			self.times_ran = num
		end
		function META:GetRepeats()
			return self.times_ran
		end
		function META:SetInterval(num)
			self.time = num
		end
		function META:GetInterval()
			return self.time
		end
		function META:SetCallback(callback)
			self.callback = callback
		end
		function META:GetCallback()
			return self.callback
		end
		function META:Call(...)
			return xpcall(self.callback, system.OnError, ...)
		end
		function META:SetNextThink(num)
			self.realtime = timer.GetElapsedTime() + num
		end
		function META:Remove()
			self.__remove_me = true
		end
		
		event.TimerMeta = META
	end
	
	local function remove_timer(key)
		for k,v in ipairs(event.timers) do
			if v.key == key then
				table.remove(event.timers, k)
				break
			end
		end
	end

	function event.CreateThinker(callback, speed, in_seconds, run_now)	
		if run_now and callback() ~= nil then
			return
		end
		
		remove_timer(callback)
		
		table.insert(event.timers, {
			key = callback,
			type = "thinker", 
			realtime = timer.GetElapsedTime(), 
			callback = callback, 
			speed = speed, 
			in_seconds = in_seconds
		})
	end

	function event.Delay(time, callback, obj)
		check(time, "number", "function")
		check(callback, "function", "nil")

		if not callback then
			callback = time
			time = 0
		end
		
		if hasindex(obj) and obj.IsValid then
			local old = callback
			callback = function(...)
				if obj:IsValid() then
					return old(...)
				end
			end
		end

		table.insert(event.timers, {
			key = callback,
			type = "delay", 
			callback = callback, 
			realtime = timer.GetElapsedTime() + time
		})
	end
	
	function event.DeferExecution(callback, time, ...)
		local data
		
		for k,v in ipairs(event.timers) do 
			if v.key == id then 
				return
			end 
		end
		
		table.insert(event.timers, {
			type = "delay",
			callback = callback,
			args = {...},
			realtime = timer.GetElapsedTime() + (time or 0),
		})
	end

	function event.CreateTimer(id, time, repeats, callback, run_now)
		check(time, "number")
		check(repeats, "number", "function")
		check(callback, "function", "nil")
		
		if not callback then 
			callback = repeats 
			repeats = 0
		end

		id = tostring(id)
		time = math.abs(time)
		repeats = math.max(repeats, 0)

		local data
		
		for k,v in ipairs(event.timers) do 
			if v.key == id then 
				data = v 
				break 
			end 
		end
		
		data = data or {}
		
		data.key = id
		data.type = "timer"
		data.realtime = timer.GetElapsedTime() + time
		data.id = id
		data.time = time
		data.repeats = repeats
		data.callback = callback
		data.times_ran = 1
		data.paused = false
		
		event.timers[id] = data
		
		setmetatable(data, event.TimerMeta)	
		
		if run_now then
			callback(repeats-1)
			data.repeats = data.repeats - 1
		end
		
		return data
	end

	function event.RemoveTimer(id)
		remove_timer(id)
	end
	
	local remove_these = {}
	
	function event.UpdateTimers(...)
		local cur = timer.GetElapsedTime()
				
		for i, data in ipairs(event.timers) do
			if data.type == "thinker" then
				if data.in_seconds and data.speed then
					if data.realtime < cur then
						local ok, res = xpcall(data.callback, system.OnError)
						if not ok or res ~= nil then
							table.insert(remove_these, i)
							break
						end
						data.realtime = cur + data.speed
					end
				elseif data.speed then
					for i=0, data.speed do
						local ok, res = xpcall(data.callback, system.OnError)
						if not ok or res ~= nil then
							table.insert(remove_these, i)
							break
						end	
					end
				else
					local ok, res = xpcall(data.callback, system.OnError)
					if not ok or res ~= nil then
						table.insert(remove_these, i)
						break
					end
				end
			elseif data.type == "delay" then
				if data.realtime < cur then
					if data.args then
						xpcall(data.callback, system.OnError, unpack(data.args))
					else
						xpcall(data.callback, system.OnError)
					end
					table.insert(remove_these, i)
					break
				end
			elseif data.type == "timer" then
				if not data.paused and data.realtime < cur then
					local ran, msg = data:Call(data.times_ran - 1, ...)
					
					if ran then
						if msg == "stop" then
							table.insert(remove_these, i)
							break
						end
						if msg == "restart" then
							data.times_ran = 1
						end
						if type(msg) == "number" then
							data.realtime = cur + msg
						end
					else
						logn(data.id, msg)
						table.insert(remove_these, i)
						break
					end

					if data.times_ran == data.repeats then
						table.insert(remove_these, i)
						break
					else
						data.times_ran = data.times_ran + 1
						data.realtime = cur + data.time
					end
				end
			end
		end
		
		if #remove_these > 0 then
			for k, v in ipairs(remove_these) do
				event.timers[v] = nil
			end
			table.fixindices(event.timers)
			table.clear(remove_these)
		end
	end
end

event.events = setmetatable({}, {
	__index = function(_, id)
		return setmetatable({}, {
			__newindex = function(_, event_name, callback)
				event.AddListener(event_name, id, callback)
			end,
		})
	end,
	__newindex = function(_, event_name, callback)
		event.AddListener(event_name, nil, callback)
	end,
})

return event