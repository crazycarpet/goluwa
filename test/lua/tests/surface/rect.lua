window.Open(500, 500)

local tex = Texture(64,64):Fill(function() 
	return math.random(255), math.random(255), math.random(255), math.random(255) 
end)  

event.AddListener("Draw2D", "lol", function()
	surface.SetColor(1,1,1,1)
	surface.SetTexture(tex)

	surface.DrawRect(90, 50, 100, 100)
end) 