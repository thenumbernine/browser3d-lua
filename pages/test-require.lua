local gl = require 'gl'
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
	end, 18	-- offset to not cover the url
	)
end

return Page
