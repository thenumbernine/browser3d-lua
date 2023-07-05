local gl = require 'gl'
local sdl = require 'ffi.sdl'
local ig = require 'imgui'
local f = require 'test-required'
local Page = {}

Page.title = 'testing'

function Page:init()
end

function Page:update()
end

function Page:updateGUI()
	ig.fullscreen(function()
		ig.igText(tostring(f()))
	end)
end

return Page
