-- [[ cache all ffi.cdef calls since I'm using a nested package system, which means double ffi.cdef'ing things, which luajit doesn't like ...
local ffi = require 'ffi'
do
	-- also in preproc but I don't want to include other stuff
	local function removeCommentsAndApplyContinuations(code)
		-- should line continuations \ affect single-line comments?
		-- if so then do this here
		-- or should they not?  then do this after.
		repeat
			local i, j = code:find('\\\n')
			if not i then break end
			code = code:sub(1,i-1)..' '..code:sub(j+1)
		until false

		-- remove all /* */ blocks first
		repeat
			local i = code:find('/*',1,true)
			if not i then break end
			local j = code:find('*/',i+2,true)
			if not j then
				error("found /* with no */")
			end
			code = code:sub(1,i-1)..code:sub(j+2)
		until false

		-- [[ remove all // \n blocks first
		repeat
			local i = code:find('//',1,true)
			if not i then break end
			local j = code:find('\n',i+2,true) or #code
			code = code:sub(1,i-1)..code:sub(j)
		until false
		--]]

		return code
	end

	local old_ffi_cdef = ffi.cdef
	local alreadycdefd = {}
	function ffi.cdef(x)
		-- this isn't necessary but it does cut down on a lot of the ffi.cdef's
		-- make sure we're not just repeatedly cdef'ing nothing
		-- though does it matter if that's the case?
		-- for debugging ... yeah.  otherwise ... no?
		x = removeCommentsAndApplyContinuations(x)
		if x:match'^%s*$' then return end
		if alreadycdefd[x] then return end
		alreadycdefd[x] = debug.traceback()
		old_ffi_cdef(x)
	end

	-- same trick with ffi.metatype
	local old_ffi_metatype = ffi.metatype
	local alreadymetatype = {}
	function ffi.metatype(typename, mt)
		local v = alreadymetatype[typename]
		if not v then
			v = old_ffi_metatype(typename, mt)
			alreadymetatype[typename] = v
		end
		return v
	end
end
--]]


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
		tab:update(...)
	end

	-- hmmmm OpenGL state issues vs ImGUI update
	gl.glUseProgram(0)
	gl.glBindTexture(gl.GL_TEXTURE_2D, 0)
	return Browser.super.update(self, ...)
end

function Browser:event(...)
	for _,tab in ipairs(self.tabs) do
		tab:event(...)
	end
	return Browser.super.event(self, ...)
end

function Browser:updateGUI(...)
	if ig.igBeginMainMenuBar() then
		if ig.luatableInputText('', self.currentTab, 'url', ig.ImGuiInputTextFlags_EnterReturnsTrue) then
			self.currentTab:setPageURL()
		end
		ig.igEndMainMenuBar()
	end
	-- TODO show tabs
	self.currentTab:updateGUI(...)
	return Browser.super.updateGUI(self, ...)
end

return Browser
