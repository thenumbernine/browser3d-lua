local gl = require 'gl'
local sdl = require 'ffi.sdl'
local ig = require 'imgui'

local Page = {}

Page.title = 'testing'

function Page:updateGUI()
	if ig.igBegin('test window', nil, 0) then
		ig.igText('test text')
		ig.igEnd()
	end
end
	
function Page:update()
	gl.glClearColor(0,0,.3,1)
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)

	local t = sdl.SDL_GetTicks() * 1e-3
	gl.glRotatef(t * 30, 0, 1, 0)

	gl.glBegin(gl.GL_TRIANGLES)
	gl.glColor3f(1, 0, 0)
	gl.glVertex3f(-5, -4, 0)
	gl.glColor3f(0, 1, 0)
	gl.glVertex3f(5, -4, 0)
	gl.glColor3f(0, 0, 1)
	gl.glVertex3f(0, 6, 0)
	gl.glEnd()
end

return Page
