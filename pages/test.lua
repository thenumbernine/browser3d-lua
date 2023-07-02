local gl = require 'gl'
local ig = require 'imgui'

local Page = {}

Page.title = 'testing'

function Page:init()
	gl.glEnable(gl.GL_DEPTH_TEST)
	gl.glClearColor(0,0,.3,1)
end

function Page:update()
	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))

	local t = os.clock()
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

function Page:updateGUI()
	if ig.igBegin('test window', nil, 0) then
		ig.igText('test text')
		ig.igEnd()
	end
end

return Page
