local gl = require 'gl'
local ig = require 'imgui'

local function errorPage(err)
	err = tostring(err)
	return {
		title = 'error',
		update = function(self)
			gl.glClear(gl.GL_COLOR_BUFFER_BIT)
		end,
		updateGUI = function(self)
			ig.fullscreen(function()
				ig.igText(err)
			end, 18)
		end,
	}
end

return errorPage
