local gl = require 'gl'
local ig = require 'imgui'
local function errorPage(err)
	return {
		title = 'error',
		update = function(self)
			gl.glClear(gl.GL_COLOR_BUFFER_BIT)
		end,
		updateGUI = function(self)
			if ig.igBegin('error window', nil, 0) then
				ig.igText(err)
				ig.igEnd()
			end	
		end,
	}
end

return errorPage
