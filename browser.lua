-- require this first so it modifies ffi first
local ffi = require 'browser.ffi'

local class = require 'ext.class'
local file = require 'ext.file'
local table = require 'ext.table'
local gl = require 'gl'
local sdl = require 'ffi.sdl'
local ig = require 'imgui'
local ThreadManager = require 'threadmanager'
local Tab = require 'browser.tab'

local Browser = require 'imguiapp.withorbit'()

Browser.title = 'Browser'

function Browser:initGL(...)
	-- save this to be reset each time a new page is loaded
	gl.glPushAttrib(gl.GL_ALL_ATTRIB_BITS)

	Browser.super.initGL(self, ...)

	file'cache':mkdir()
	self.cacheDir = file(file:cwd())/'cache'

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

	-- refresh title
	self.title = tostring(self.currentTab.page and self.currentTab.page.title or nil)
	if self.lastTitle ~= self.title then
		sdl.SDL_SetWindowTitle(self.window, self.title)
		self.lastTitle = self.title
	end

	-- hmmmm OpenGL state issues vs ImGUI update
	gl.glUseProgram(0)
	gl.glBindTexture(gl.GL_TEXTURE_2D, 0)

	-- hmm, this is going to mess with the modelview/projection matrix state ..
	-- app pages aren't going to like that ...
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
	
	-- show tabs
	--[[
	ig.igSetNextWindowPos(ig.ImVec2(0, 18), 0, ig.ImVec2())
	local size = ig.ImVec2(ig.igGetIO().DisplaySize)
	size.y = 18
	ig.igSetNextWindowSize(size, 0)

	ig.igPushStyleVar_Float(ig.ImGuiStyleVar_WindowRounding, 0)
	ig.igBegin('tab window', nil, bit.bor(
		ig.ImGuiWindowFlags_NoMove,
		ig.ImGuiWindowFlags_NoResize,
		ig.ImGuiWindowFlags_NoCollapse,
		ig.ImGuiWindowFlags_NoDecoration
	))

	if ig.igBeginTabBar('tabs', 0) then
		ig.igTabItemButton('+', bit.bor(
			ig.ImGuiTabItemFlags_Trailing,
			ig.ImGuiTabItemFlags_NoTooltip
		))
		
		if ig.igBeginTabItem('tab', nil, 0) then
			ig.igEndTabItem()
		end

		ig.igEndTabBar()
	end
	ig.igEnd()
	ig.igPopStyleVar(1)
	--]]

	self.currentTab:resumecall('updateGUI', ...)
	
	return Browser.super.updateGUI(self, ...)
end

return Browser
