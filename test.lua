local gl = require 'gl'
return {
	title = 'testing',
	update = function(self)
		gl.glClearColor(0,0,.3,1)
		gl.glClear(gl.GL_COLOR_BUFFER_BIT)
	end,
}
