local gl = require 'gl'
local ig = require 'imgui'
local vec3f = require 'vec-ffi.vec3f'
local matrix_ffi = require 'matrix.ffi'
matrix_ffi.real = 'float'
return {
	title = 'mesh demo',
	init = function(self)
		-- how to handle for remote resources? browser:request? 
		-- same with files ...
		self.mesh = require 'mesh.objloader'():load'cube.obj'
		self.shader = self.mesh:makeShader()
		self.shader:useNone()
		self.modelMatrix = matrix_ffi{{1,0,0,0},{0,1,0,0},{0,0,1,0},{0,0,0,1}}
		self.viewMatrix = matrix_ffi.zeros{4,4}
		self.projectionMatrix = matrix_ffi.zeros{4,4}
		gl.glEnable(gl.GL_DEPTH_TEST)
	end,
	update = function(self)
		gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
		gl.glGetFloatv(gl.GL_MODELVIEW_MATRIX, self.viewMatrix.ptr)
		gl.glGetFloatv(gl.GL_PROJECTION_MATRIX, self.projectionMatrix.ptr)
		--[[
		self.shader:use()
		self.shader:setUniforms{
			--useFlipTexture = self.useFlipTexture,
			--useLighting = self.useLighting,
			--lightDir = self.lightDir:normalize().s,
			modelMatrix = self.modelMatrix.ptr,
			viewMatrix = self.viewMatrix.ptr,
			projectionMatrix = self.projectionMatrix.ptr,
		}
		--]]
		self.mesh:draw{
			-- TODO why isn't VAO working?
			method = 'immediate',
			shader = self.shader,
			beginGroup = function(g)
				--[[
				self.shader:setUniforms{
					--useTextures = g.tex_Kd and 1 or 0,
					--Ka = g.Ka or {0,0,0,0},	-- why are most mesh files 1,1,1,1 ambient?  because blender exports ambient as 1,1,1,1 ... but that would wash out all lighting ... smh
					--Ka = {0,0,0,0},
					--Kd = g.Kd and g.Kd.s or {1,1,1,1},
					--Ks = g.Ks and g.Ks.s or {1,1,1,1},
					--Ns = g.Ns or 10,
					-- com3 is best for closed meshes
					--objCOM = vec3f().s,--self.mesh.com2.s,
					--groupCOM = vec3f().s,--g.com2.s,
					--groupExplodeDist = 0,
					--triExplodeDist = 0,
				}
				--]]
			end,
		}
		self.shader:useNone()
	end,
	updateGUI = function(self)
	end,
}
