--[[
I remember back in the OpenGL 1.0 days, when this tech demo was compelling.
Then it was like "Look! You can stream the script to draw a triangle in 3D hardware in just 10 lines of code!"
Then along came the GL 1.0 deprecation,
and next it was "You can stream draw a 3D triangle in ... 50 lines of code!"
Then all GL went out (*cough* Apple *cough)
and all that's left is GLES,
and now it is "You can stream draw a 3D triangle in ... 200 lines of code!"

🤦
I am old enough to remember when advances in software meant making things simpler, not making them more bureaucratic in the name of job security.
There was a place for OpenGL 1.0.  It was "easy mode API".
There was a place for GLES.  It was "normal mode API"
And of course everything now is Vulkan, "hard mode API".  Write 1000 lines of code just to draw a triangle to the screen.
Smfh....
--]]
local gl = require 'gl'
local Image = require 'image'
local GLSceneObject = require 'gl.sceneobject'
local GLTex2D = require 'gl.tex2d'
local ig = require 'imgui'
local getTime = require 'ext.timer'.getTime
local View = require 'app3d.view'

local Page ={}

Page.title = 'testing 2'

function Page:init()
	self.view = View()
	self.obj = GLSceneObject{
		program = {
			version = 'latest',
			vertexCode = [[
in vec4 vertex;
in vec3 color;
out vec2 vtxv;
out vec4 colorv;
uniform mat4 mvMat, projMat;
void main() {
	vtxv = vertex.xy;
	vec4 vtxWorld = mvMat * vec4(vertex.xyz, 1.);
	gl_Position = projMat * vtxWorld;
	colorv = vec4(color.xyz, 1.) + sin(30. * vtxWorld);
}
]],
			fragmentCode = [[
in vec2 vtxv;
in vec4 colorv;
out vec4 colorf;
uniform sampler2D tex;
void main() {
	vec2 texcoord = vtxv.xy;
	vec4 texcolor = texture(tex, texcoord);
	colorf = colorv * texcolor + .1 * sin(gl_FragCoord / 5.);
}
]],
			uinforms = {
				tex = 0,
			},
		},
		vertexes = {
			data = {
				-5, -4,
				5, -4,
				0, 6,
			},
			dim = 2,
		},
		geometry = {
			mode = gl.GL_TRIANGLES,
			count = 3,
		},
		attrs = {
			color = {
				buffer = {
					data = {
						1, 0, 0,
						0, 1, 0,
						0, 0, 1,
					},
					dim = 3,
				},
			},
		},
	}

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

	local t = getTime()
	self.view.mvMat:applyRotate(math.rad(t * 30), 0, 1, 0)
	self.view:setup(self.width / self.height)

	self.obj.uniforms.mvMat = self.view.mvMat.ptr
	self.obj.uniforms.projMat = self.view.projMat.ptr
	self.obj:draw()
end

return Page
