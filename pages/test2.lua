local gl = require 'gl'
local glreport = require 'gl.report'
local Image = require 'image'
local GLProgram = require 'gl.program'
local GLTex2D = require 'gl.tex2d'
local sdl = require 'ffi.sdl'
local ig = require 'imgui'
local matrix_ffi = require 'matrix.ffi'

local Page ={}

Page.title = 'testing 2'

Page.modelViewMatrix = matrix_ffi.zeros({4,4}, 'float')
Page.projectionMatrix = matrix_ffi.zeros({4,4}, 'float')

function Page:init()
	self.shader = GLProgram{
		vertexCode = [[
#version 460
uniform mat4 modelViewMatrix, projectionMatrix;
layout(location=0) in vec4 pos;
layout(location=1) in vec3 color;
out vec2 posv;
out vec4 colorv;
void main() {
	posv = pos.xy;
	vec4 vtxWorld = modelViewMatrix * vec4(pos.xyz, 1.);
	gl_Position = projectionMatrix * vtxWorld;
	colorv = vec4(color.xyz, 1.) + sin(30. * vtxWorld);
}
]],
		fragmentCode = [[
#version 460
in vec2 posv;
in vec4 colorv;
out vec4 colorf;
layout(binding=0) uniform sampler2D tex;
void main() {
	vec2 texcoord = posv.xy;
	vec4 texcolor = texture(tex, texcoord);
	colorf = colorv * texcolor + .1 * sin(gl_FragCoord / 5.);
}
]],
	}
	self.shader:useNone()

	self.tex = GLTex2D{
		image = Image(256, 256, 3, 'unsigned char', function(u,v)
			return math.random(), math.random(), math.random()
		end),
	}
	self.tex:unbind()
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

	gl.glGetFloatv(gl.GL_MODELVIEW_MATRIX, self.modelViewMatrix.ptr)
	gl.glGetFloatv(gl.GL_PROJECTION_MATRIX, self.projectionMatrix.ptr)
	self.shader:use()
	self.shader:setUniforms{
		modelViewMatrix = self.modelViewMatrix.ptr,
		projectionMatrix = self.projectionMatrix.ptr,
	}
	self.tex:bind()
	gl.glBegin(gl.GL_TRIANGLES)
	gl.glColor3f(1, 0, 0)
	gl.glVertex3f(-5, -4, 0)
	gl.glColor3f(0, 1, 0)
	gl.glVertex3f(5, -4, 0)
	gl.glColor3f(0, 0, 1)
	gl.glVertex3f(0, 6, 0)
	gl.glEnd()
	self.tex:unbind()
	self.shader:useNone()
end

return Page
