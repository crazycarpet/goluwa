local entities = (...) or _G.entities

local COMPONENT = {}

local _debug = false
local spawned_networked = {}

COMPONENT.Name = "networked"
COMPONENT.Require = {"transform"}
COMPONENT.Events = {"Update"}

metatable.GetSet(COMPONENT, "NetworkId", -1)

do
	COMPONENT.client_synced_vars = {}
	COMPONENT.server_synced_vars = {}
	COMPONENT.server_synced_vars_stringtable = {}

	function COMPONENT:ServerSyncVar(component, key, type, rate, flags)
		self:ServerDesyncVar(component, key)
		
		local info = {
			component = component, 
			key = key,
			get_name = "Get" .. key,
			set_name = "Set" .. key,
			type = type,
			rate = rate,
			id = SERVER and network.AddString(component .. key) or (component .. key),
			flags = flags,
		}
		
		table.insert(self.server_synced_vars, info)
		
		self.server_synced_vars_stringtable[component..key] = info
	end

	function COMPONENT:ServerDesyncVar(component, key)
		for k, v in ipairs(self.server_synced_vars) do
			if v.component == component and v.key == key then
				table.remove(self.server_synced_vars, k)
				self.server_synced_vars_stringtable[component..key] = nil
				break
			end
		end
	end
	
	function COMPONENT:SetupSyncVariables()
		local done = {}
		
		for i, component in npairs(self:GetEntityComponents()) do
			if component.Network then
				for key, info in pairs(component.Network) do
					if not done[key] then
						self:ServerSyncVar(component.Name, key, unpack(info))
						done[key] = true
					end
				end
			end
		end
	end
end

function COMPONENT:OnUpdate()
	self:UpdateVars()
end

do -- synchronization server > client
	COMPONENT.last = {}
	COMPONENT.last_update = {}
	COMPONENT.queued_packets = {}

	function COMPONENT:UpdateVars(client, force_update)
		for i, info in ipairs(SERVER and self.server_synced_vars or CLIENT and self.client_synced_vars) do
			if force_update or not self.last_update[info.key] or self.last_update[info.key] < timer.GetSystemTime() then
				
				local var
				
				if info.component == "unknown" then
					var = self:GetEntity()[info.get_name](self:GetEntity())
				else
					local component = self:GetComponent(info.component)
					var = component[info.get_name](component)
				end
				
				if force_update or var ~= self.last[info.key] then
					local buffer = Buffer()
					
					buffer:WriteShort(info.id)
					buffer:WriteShort(self.NetworkId)
					buffer:WriteType(var, info.type)
					
					if _debug then logf("%s: sending %s to %s\n", self, utilities.FormatFileSize(buffer:GetSize()), client) end
					
					packet.Send("ecs_network", buffer, client, force_update and "reliable" or info.flags)
					
					self.last[info.key] = var
				end

				self.last_update[info.key] = timer.GetSystemTime() + info.rate
			end
		end

		
		if CLIENT then
			local buffer = table.remove(self.queued_packets)
			
			if buffer then
				handle_packet(buffer)
			end
		end
	end

	local function handle_packet(buffer)
		local what = buffer:ReadNetString()
		local id = buffer:ReadShort()
		local self = spawned_networked[id] or NULL
		
		if what == "entity_networked_spawn" then
			local config =  buffer:ReadString()

			local ent = entities.CreateEntity(config)
			ent:SetNetworkId(id)
			
			local self = ent:GetComponent("networked")
			self:SetupSyncVariables()
			
			spawned_networked[id] = self
			
			logf("entity %s with id %s spawned from server\n", config, id)
		elseif what == "entity_networked_remove" then
			self:GetEntity():Remove() 
		elseif self:IsValid() then
			local info = self.server_synced_vars_stringtable[what]
					
			if info then
				local var = buffer:ReadType(info.type)
				
				if info.component == "unknown" then
					local ent = self:GetEntity()
					ent[info.set_name](ent, var)
				else
					local component = self:GetComponent(info.component)
					component[info.set_name](component, var)
				end
				if _debug then logf("%s: received %s\n", self, var) end
			elseif info.flags == "reliable" then
				table.insert(self.queued_packets, buffer)
			end
		else
			---table.insert(self.queued_packets, buffer)
			--logf("received sync packet %s but entity[%s] is NULL\n", typ, id)
		end
	end

	packet.AddListener("ecs_network", handle_packet)

	if SERVER then
		table.insert(COMPONENT.Events, "ClientEntered")
		
		function COMPONENT:OnClientEntered(client)
			self:SpawnEntityOnClient(client, self.NetworkId, self:GetEntity().config)
			
			-- force send all packets once to this new client as reliable 
			-- so all the entities' positions will update properly
			self:UpdateVars(client, true)		
			
			self:SendCallOnClientToClient(client)
		end
	end
end

if SERVER then
	function COMPONENT:SpawnEntityOnClient(client, id, config)
		local buffer = Buffer()
		
		buffer:WriteNetString("entity_networked_spawn")
		buffer:WriteShort(id)
		buffer:WriteString(config)
		
		--logf("spawning entity %s with id %s for %s\n", config, id, client)
		
		packet.Send("ecs_network", buffer, client, "reliable")
	end
	
	function COMPONENT:RemoveEntityOnClient(client, id)
		local buffer = Buffer()
		
		buffer:WriteNetString("entity_networked_remove")
		buffer:WriteShort(id)
		
		packet.Broadcast("ecs_network", buffer, client, "reliable")
	end
	
	local id = 1
	
	function COMPONENT:OnAdd(ent)
		self.NetworkId = id
		
		spawned_networked[self.NetworkId] = self
		
		self:SpawnEntityOnClient(nil, self.NetworkId, ent.config)
		self:SetupSyncVariables()
		
		id = id + 1
	end
	
	function COMPONENT:OnRemove(ent)
		spawned_networked[self.NetworkId] = nil
	
		self:RemoveEntityOnClient(nil, self.NetworkId)
	end
end

do -- call on client
	if CLIENT then
		message.AddListener("ecs_network_call_on_client", function(id, component, name, ...)
			local self = spawned_networked[id] or NULL
			
			if self:IsValid() then
				if component == "unknown" then
					local ent = self:GetEntity()
					local func = ent[name]
					if func then
						func(ent, ...)
					else
						logf("call on client: function %s does not exist in entity\n", name)
						print(name, ...)
					end
				else
					local obj = self:GetComponent(component)
					if obj:IsValid() then
						local func = obj[name]
						
						if func then
							func(obj, ...)
						else
							logf("call on client: function %s does not exist in component %s\n", name, component)
							print(name, ...)
						end
					else
						logf("call on client: component %s does not exist in entity (%s)\n", component, id)
						print(name, ...)
					end
				end
			else
				logf("call on client: entity (%s) is NULL\n", id)
				print(name, ...)
			end
		end)
	end

	if SERVER then
		COMPONENT.call_on_client_persist = {}

		function COMPONENT:SendCallOnClientToClient()
			for i, args in ipairs(self.call_on_client_persist) do	
				self:CallOnClient(client, unpack(args))
			end		
		end
		
		function COMPONENT:CallOnClient(filter, component, name, ...)
			message.Send("ecs_network_call_on_client", filter, self.NetworkId, component, name, ...)
		end
		
		function COMPONENT:CallOnClients(component, name, ...)
			message.Broadcast("ecs_network_call_on_client", self.NetworkId, component, name, ...)
		end
		
		function COMPONENT:CallOnClientsPersist(component, name, ...)
			table.insert(self.call_on_client_persist, {component, name, ...})
			return self:CallOnClients(component, name, ...)
		end
	end
end

entities.RegisterComponent(COMPONENT) 