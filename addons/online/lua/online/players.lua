players = players or {}
players.active_players = players.active_players or {}

function players.GetAll()
	local out = {}
	for key, ply in pairs(players.active_players) do
		if ply:IsValid() then
			table.insert(out, ply)
		else
			players.active_players[key] = nil
		end
	end
	return out
end

function players.GetByUniqueID(id)
	return players.active_players[id] or NULL
end

function players.GetLocalPlayer()
	return players.local_player or NULL
end
	
function players.BroadcastLua(str)
	for key, ply in pairs(players.GetAll()) do
		ply:SendLua(str)
	end
end
	
local ref_count = 1

do -- player meta
	local META

	META = {}
	META.__index = META
	
	META.Type = "player"
	META.ClassName = "player"
		
	class.GetSet(META, "UniqueID", "???")
	class.GetSet(META, "ID", -1)
	
	nvars.GetSet(META, "Nick", "???", "cl_nick")
	
	function META:GetNick()
		for key, ply in pairs(players.GetAll()) do
			if ply ~= self and ply.nv.Nick == self.nv.Nick then
				return ("%s(%i)"):format(self.nv.Nick, self.ID)
			end
		end
		
		return self.nv.Nick
	end

	function META:__tostring()
		return string.format("player[%s][%i]", self:GetName(), self:GetID())
	end
	
	function META:IsValid() 
		return true
	end

	function META:GetName()	
		return self.nv and self.nv.Nick or SERVER and self.socket:GetIPPort() or CLIENT and self:GetUniqueID()
	end
	
	function META:Remove(reason)
		if self.remove_me then return end
		
		players.active_players[self:GetUniqueID()] = nil
				
		self.remove_me = true
		self.IsValid = function() return false end
		timer.Simple(0, function() utilities.MakeNULL(self) end)
		
	end	
	
	if SERVER then
		function META:Kick(reason)
			network.HandleEvent(self.socket, e.USER_DISCONNECT, self.socket:GetIPPort(), reason)
		end
	end
	
	do -- ping pong	
		nvars.GetSet(META, "Ping", 0)
			
		function META:GetTimeout()
			return self.last_ping and (os.clock() - self.last_ping) or 0
		end
		
		function META:IsTimingOut()
			return self:GetTimeout() > 3
		end
	
		if CLIENT then
			message.AddListener("ping", function(...)
				message.Send("pong", ...)
				
				players.GetLocalPlayer().last_ping = os.clock()
			end)
		end
		
		if SERVER then			
			message.AddListener("pong", function(ply, time)
				local ms = (os.clock() - tonumber(time)) * 100
				
				ply:SetPing(ms)
				ply.last_ping = os.clock()
			end)
		end		
		
		timer.Create("ping_pong_players", 0.25, 0, function()
			if not network.IsStarted() then return end
						
			for key, ply in pairs(players.GetAll()) do
				message.Send("ping", ply, tostring(os.clock()))
				
				if ply:IsTimingOut() then
				
					if SERVER then
						ply:Kick("timeout")
					end
					
					if CLIENT then
						logn("timed out..")
						
						if ply:IsTimingOut() then
							network.Disconnect()
						end
					end
				end
			end
		end)

	end
	
	do -- send lua
		if CLIENT then
			message.AddListener("sendlua", function(code, env)
				local data = easylua.RunLua(me, code, env or "server")
				if data.error then
					print(data.error)
				end
			end)
		end

		if SERVER then
			function META:SendLua(code)
				message.Send("sendlua", self, code, env)
			end
			
			function META:Cexec(str)
				self:SendLua("console.RunString('"..str.."')")
			end
		end
	end
	
	do -- networked input
		local function add_event(name, check)	
			input.SetupAccessorFunctions(META, name)
			
			if CLIENT then
				event.AddListener("On" .. name .. "Input", "player_" .. name .. "_event", function(key, press)
					local ply = players.GetLocalPlayer()
					
					if ply:IsValid() then						
						if check and not check[key] then return end
						
						input.CallOnTable(ply, name, key, press, nil, nil, true)
						message.Send("Player" .. name .. "Event", key, press)
						
						return event.Call("Player" .. name .. "Event", ply, key, press)
					end
				end, print)
			end
			
			if SERVER then
				message.AddListener("Player" .. name .. "Event", function(ply, key, press)
					if ply:IsValid() then
						if check and not check[key] then return end

						input.CallOnTable(ply, name, key, press, nil, nil, true)
					
						event.Call("Player" .. name .. "Event", ply, key, press)
					end
				end, print)
			end
		end
				
		add_event("Key")
		add_event("Char")
	end
		
	players.player_meta = META

	function Player(uniqueid)
		local self = players.active_players[uniqueid] or NULL

		if self:IsValid() then
			return self
		end
		
		self = setmetatable({}, players.player_meta)
		ref_count = ref_count + 1
			
		self:SetUniqueID(uniqueid)
		self.ID = ref_count
			
		players.active_players[self.UniqueID] = self
				
		-- add a networked table to the player
		self.nv = nvars.CreateObject(uniqueid)
			
		return self
	end
end

network.AddEncodeDecodeType("player", function(var, encode)
	if encode then
		local var = var:GetUniqueID()
		return var
	else
		local var = players.GetByUniqueID(var)
		if var:IsValid() then
			return var
		end
	end
end) 