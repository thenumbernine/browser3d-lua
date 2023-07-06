-- require this first so it modifies ffi first
local ffi = require 'browser.ffi'

local class = require 'ext.class'
local file = require 'ext.file'
local table = require 'ext.table'
local gl = require 'gl'
local ig = require 'imgui'
local ThreadManager = require 'threadmanager'
local Tab = require 'browser.tab'

file'cache':mkdir()

local Browser = require 'imguiapp.withorbit'()

Browser.title = 'Browser'

function Browser:initGL(...)
	-- save this to be reset each time a new page is loaded
	gl.glPushAttrib(gl.GL_ALL_ATTRIB_BITS)

	Browser.super.initGL(self, ...)

	--[[ use a package.searchers and give it precedence over local requires
	-- TODO just do this for the page env' require() and that way we can block via http request
	-- without blocking on the main thread
	-- that'd doubly be good to prevent dif pages' package.loaded[] 's from mixing with one another
	table.insert(package.searchers, 1, function(name)
print('here', self.proto, name)
		if self.proto ~= 'file' then
			local res, err = self:requireRelativeToLastPage(name)
			return res or err
		end
	end)
	--]]

	self.threads = ThreadManager()

	-- finally start a page off
	local tab = Tab{browser=self, url=self.url}
	self.url = nil
	self.tabs = table{tab}
	self.currentTab = tab
	assert(type(self.currentTab.url) == 'string')
end

function Browser:update(...)
	for _,tab in ipairs(self.tabs) do
		tab:resumecall('update', ...)
	end

	-- hmmmm OpenGL state issues vs ImGUI update
	gl.glUseProgram(0)
	gl.glBindTexture(gl.GL_TEXTURE_2D, 0)
	return Browser.super.update(self, ...)
end

function Browser:event(...)
	for _,tab in ipairs(self.tabs) do
		tab:resumecall('event', ...)
	end
	return Browser.super.event(self, ...)
end

function Browser:updateGUI(...)
	if ig.igBeginMainMenuBar() then
		if ig.luatableInputText('', self.currentTab, 'url', ig.ImGuiInputTextFlags_EnterReturnsTrue) then
			self.currentTab:resumecall'setPageURL'
		end
		ig.igEndMainMenuBar()
	end
	
	-- TODO show tabs
	
	self.currentTab:resumecall('updateGUI', ...)
	
	return Browser.super.updateGUI(self, ...)
end

return Browser
