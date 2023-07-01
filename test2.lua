local gl = require 'gl'
local Program = require 'gl.program'
local sdl = require 'ffi.sdl'
local ig = require 'imgui'

local Page ={}

Page.title = 'testing 2'

function Page:init()
	self.shader = Program{
		vertexCode = [[
#version 460
uniform mat4 modelViewMatrix, projectionMatrix;
in vec3 pos, color;
out vec2 posv;
out vec4 colorv;
void main() {
	posv = pos.xy;
	vec4 vtxWorld = modelViewMatrix * vec4(pos, 1.);
	gl_Position = projectionMatrix * vtxWorld;
	colorv = vec4(color, 1.) + sin(30. * vtxWorld);
}
]],
		fragmentCode = [[
#version 460
in vec2 posv;
in vec4 colorv;
out vec4 colorf;
//layout(binding=0) uniform sampler2D tex;
void main() {
	vec2 texcoord = posv.xy;
	vec4 texcolor = vec4(texcoord, 0., 1.);//texture(tex, texcoord);
	colorf = colorv * texcolor + .1 * sin(gl_FragCoord / 5.);
}
]],
	}
end

function Page:updateGUI()
	if ig.igBegin('test2 window', nil, 0) then
		ig.igText('test2 text')
		ig.igEnd()
	end
end

function Page:update()
	gl.glClearColor(0,0,.3,1)
	gl.glClear(gl.GL_COLOR_BUFFER_BIT)

	local t = sdl.SDL_GetTicks() * 1e-3
	gl.glRotatef(t * 30, 0, 1, 0)

	self.shader:use()
	gl.glBegin(gl.GL_TRIANGLES)
	gl.glColor3f(1, 0, 0)
	gl.glVertex3f(-5, -4, 0)
	gl.glColor3f(0, 1, 0)
	gl.glVertex3f(5, -4, 0)
	gl.glColor3f(0, 0, 1)
	gl.glVertex3f(0, 6, 0)
	gl.glEnd()
	Program:useNone()
end

return Page
