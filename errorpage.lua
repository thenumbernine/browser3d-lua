local gl = require 'gl'
local ig = require 'imgui'

local function errorPage(browser, err)
	err = tostring(err)
	return {
		title = 'error',
		update = function(self)
			gl.glClear(gl.GL_COLOR_BUFFER_BIT)
		end,
		updateGUI = function(self)
			ig.fullscreen(function()
				ig.igText(err)
			end)
		end,
	}
end

return errorPage
