local entities = (...) or _G.entities

local COMPONENT = {}

COMPONENT.Name = "transform"

metatable.AddParentingTemplate(COMPONENT)

metatable.GetSet(COMPONENT, "TRMatrix", Matrix44())
metatable.GetSet(COMPONENT, "ScaleMatrix", Matrix44())

metatable.StartStorable()		
	metatable.GetSet(COMPONENT, "Position", Vec3(0, 0, 0), "InvalidateTRMatrix")
	metatable.GetSet(COMPONENT, "Angles", Ang3(0, 0, 0), "InvalidateTRMatrix")
	
	metatable.GetSet(COMPONENT, "Scale", Vec3(1, 1, 1), "InvalidateScaleMatrix")
	metatable.GetSet(COMPONENT, "Shear", Vec3(0, 0, 0), "InvalidateScaleMatrix")
	metatable.GetSet(COMPONENT, "Size", 1, "InvalidateScaleMatrix")
metatable.EndStorable()

metatable.GetSet(COMPONENT, "OverridePosition", nil, "InvalidateTRMatrix")
metatable.GetSet(COMPONENT, "OverrideAngles", nil, "InvalidateTRMatrix")
	
COMPONENT.Network = {
	Position = {"vec3", 1/30, "unreliable"},
	Angles = {"ang3", 1/30, "unreliable"},
	Scale = {"vec3", 1/15},
	Size = {"float", 1/15},
}

function COMPONENT:OnAdd(ent, parent)
	if parent and parent:HasComponent("transform") then
		self:SetParent(parent:GetComponent("transform"))
	end
end

function COMPONENT:OnRemove(ent)

end

do
	COMPONENT.temp_scale = Vec3(1, 1, 1)
	
	function COMPONENT:SetScale(vec3) 
		self.Scale = vec3
		self.temp_scale = vec3 * self.Size
		self:InvalidateScaleMatrix()
	end
			
	function COMPONENT:SetSize(num) 
		self.Size = num
		self.temp_scale = num * self.Scale
		self:InvalidateScaleMatrix()
	end
end

function COMPONENT:InvalidateScaleMatrix()
	self.rebuild_scale_matrix = true
end

function COMPONENT:InvalidateTRMatrix()
	self.rebuild_tr_matrix = true
	
	for _, child in ipairs(self:GetChildren(true)) do
		self.rebuild_tr_matrix = true
	end
end

function COMPONENT:GetTRAngles()

end

function COMPONENT:GetTRPosition()
	local x, y, z = self.TRMatrix:GetTranslation()
	return Vec3(-y, -x, -z)
end

function COMPONENT:GetTRAngles()
	local p, y, r = self.TRMatrix:GetAngles()
	
	return Ang3(p, y, r):Deg()
end

function COMPONENT:RebuildMatrix()			
	if self.rebuild_tr_matrix then				
		self.TRMatrix:Identity()

		local pos = self.Position
		local ang = self.Angles
		
		if self.OverrideAngles then
			ang = self.OverrideAngles
		end
		
		if self.OverridePosition then
			pos = self.OverridePosition
		end
		
		self.TRMatrix:Translate(-pos.y, -pos.x, -pos.z)
		
		self.TRMatrix:Rotate(-ang.y, 0, 0, 1)
		self.TRMatrix:Rotate(-ang.p + 90, 1, 0, 0)
		self.TRMatrix:Rotate(ang.r + 180, 0, 0, 1)	
		
		if self:HasParent() then
			self.temp_matrix = self.temp_matrix or Matrix44()
			
			--self.TRMatrix = self.TRMatrix * self.Parent.TRMatrix
			self.TRMatrix:Multiply(self.Parent.TRMatrix, self.temp_matrix)
			self.TRMatrix, self.temp_matrix = self.temp_matrix, self.TRMatrix
		end
		
		self.rebuild_tr_matrix = false
	end

	if self.rebuild_scale_matrix and not (self.temp_scale.x == 1 and self.temp_scale.y == 1 and self.temp_scale.z == 1) then
		self.ScaleMatrix:Identity()
		self.ScaleMatrix:Scale(self.temp_scale.x, self.temp_scale.z, self.temp_scale.y)
		--self.ScaleMatrix:Shear(self.Shear)
		
		self.rebuild_scale_matrix = false
	end
end

function COMPONENT:GetMatrix()
	self:RebuildMatrix()
	
	if self.temp_scale.x == 1 and self.temp_scale.y == 1 and self.temp_scale.z == 1 then
		return self.TRMatrix 
	end
	
	return self.ScaleMatrix * self.TRMatrix 
end

entities.RegisterComponent(COMPONENT)