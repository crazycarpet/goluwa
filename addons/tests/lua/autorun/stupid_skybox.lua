local tex = Texture(1, 255):Fill(function(x, y)
	local frac = y/255
	local frac2 = -frac+1
	
	local c = HSVToColor(frac2/5, frac^0.5, 1)
	
	return c.r * 255, c.g * 255, c.b * 255, 255
end)     

local stretch = math.pi

event.AddListener("PreDisplay", "sky", function()
	local h = window.GetSize().h
	local y = render.GetCamAng().p/90
	y = (1 + y) / 2
	surface.SetTexture(tex)
	surface.DrawRect(0,y*-h*stretch/2, 1024, h*stretch)	
end)