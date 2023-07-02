print('browser/browser.lua _G', _G)
local file = require 'ext.file'	-- TODO rename to path
local table = require 'ext.table'
local sdl = require 'ffi.sdl'
local ig = require 'imgui'
local gl = require 'gl'
local ThreadManager = require 'threadmanager'
local errorPage = require 'browser.errorpage'

local Browser = require 'imguiapp.withorbit'()

Browser.title = 'Browser'

function Browser:initGL(...)
	Browser.super.initGL(self, ...)

	self.threads = ThreadManager()

	self.url = self.url or 'file://pages/test.lua'
	self:loadURL()
end

-- TODO some set of functions which error() shouldn't be permitted to be called within
-- only setErrorPage instead.
-- I'd say just wrap this all in xpcall,
-- but I'm already doing that within setPage
function Browser:loadURL(url)
	url = url or self.url
	local proto, rest = url:match'^([^:]*)://(.*)'
	if not proto then
		-- try accessing it as a file
		if file(url):exists() then
			self.url = 'file://'..url
			self:loadFile(url)
			return
		else
			self:setErrorPage("url is ill-formatted "..tostring(url))
		end
	end
	if proto == 'file' then
		self:loadFile(rest)
	elseif proto == 'http' then
		self:loadHTTP(url)
	else
		self:setErrorPage("unknown protocol "..tostring(proto))
	end
end

function Browser:loadFile(filename)
	if not file(filename):exists() then
		-- ... have the browser show a 'file missing' page
		self:setErrorPage("couldn't load file "..tostring(filename))
	else
		self:handleData(file(filename):read())
	end
end

function Browser:loadHTTP(url)
	self:handleData(require 'socket.http'.request(url))
end

local function shallowcopy(t)
	return table(t):setmetatable(nil)
end

function Browser:handleData(data)
	-- sandbox env
	-- [==[ simple sandbox:
	local env = setmetatable({browser=self}, {__index=_G})
	--]==]
	--[==[ trying to sandbox _G from require()
	-- this was my attempt to make a quick fix to using all previous glapp subclasses as pages ...
	-- the problem occurs because browser here already require'd glapp, which means glapp is in package.loaded, and with its already-defined _G, which has no 'browser'
	-- I was trying to create a parallel require()/package.loaded , one with _G having 'browser', and using that as a detect, but.... it's getting to be too much work
	-- ... maybe I can use another kind of detect ...

	local env = {}
	-- copy over original globals (not requires)
	for _,k in ipairs{
		'require',
		'assert',
		'rawequal',
		'rawlen',
		'unpack',
		'select',
		'type',
		'next',
		'pairs',
		'ipairs',
		'getmetatable',
		'setmetatable',
		'getfenv',
		'setfenv',
		'rawget',
		'rawset',
		'collectgarbage',
		'newproxy',
		'print',
		'_VERSION',
		'gcinfo',
		'dofile',
		'error',
		'tonumber',
		'jit',
		'loadstring',
		'load',
		'loadfile',
		'xpcall',
		'pcall',
		'tostring',
		'module',
	} do
		env[k] = _G[k]
	end
	-- what kind of args do we want?
	env.arg = {}
	-- set browser as a global or package?
	env.browser = self
print('env', env)
print('env.browser', env.browser)
	-- make sure our sandbox _G points back to itself so the page can't modify the browser env
	env._G = env

	-- also we're going to need a new package table,
	-- otherwise browser environment will collide with page environments
	-- namely that the page's glapp's _G will otherwise point to the browser _G instead of the page _G
	env.package = shallowcopy(_G.package)
	env.package.preload = shallowcopy(_G.package.preload)

	--[[
	four searchers:
	1) package.preload table
	2) package.searchpath / package.path
	3) package.searchpath / package.cpath
	4) 'all in one loader'
	--]]
	env.package.searchers = shallowcopy(_G.package.searchers)
	--env.package.searchers =

	env.package.loaded = {}
	for _,field in ipairs{
		'coroutine',
		'jit',
		'bit',
		'os',
		'debug',
		'string',
		'math',
		'jit.opt',
		'table',
		'io',
	} do
		local v = package.loaded[field]
		env[field] = v
		env.package.loaded[field] = v
	end
	env.package.loaded._G = env
	env.package.loaded.package = env.package

	print('browser _G before sandbox', _G)
	assert(load([[
print('sandbox _G', _G)

-- without this, subequent require()'s will have the original _G
setfenv(0, _G)

print('sandbox package', package)
print('sandbox package.searchers', package.searchers)
print('sandbox os', os)
print('sandbox package.loaded.os', package.loaded.os)

-- now I guess I need my own require() function
-- and maybe get rid of package searchers and loaders? maybe? not sure?
local function findchunk(name)
	local errors = ("module '%s' not found"):format(name)
	for i,searcher in ipairs(package.searchers) do
		local chunk = searcher(name)
--print('searcher',i,'got',chunk)
		if type(chunk) == 'function' then
			return chunk
		elseif type(chunk) == 'string' then
			errors = errors .. chunk
		end
	end
	return nil, errors
end

function require(name)
	if package.loaded[name] == nil then
		package.loaded[name] = assert(findchunk(name))(name) or true
	end
	return package.loaded[name]
end

print('sandbox browser', browser)
print('sandbox package.loaded.glapp before', package.loaded.glapp)
-- TODO this isn't putting requires in our package.laded ...
require 'glapp'
print('sandbox package.loaded.glapp after', package.loaded.glapp)
]], 'sandbox of '..self.url, nil, env))()
	print('browser _G after sandbox', _G)
	--]==]


	-- get our page generation module
	local gen, err = load(data, self.url, nil, env)
	if not gen then
		-- report compile error
		self:setErrorPage('failed to load '..tostring(self.url))
		return
	end
	self:setPage(gen, self)
end

function Browser:setPageProtected(gen, ...)
	self.page = gen(self, ...)
	if self.page then
		sdl.SDL_SetWindowTitle(self.window, self.page.title or '')
	end
end

function Browser:setPage(gen, ...)
	self:safecall(self.setPageProtected, self, gen, ...)
	-- TODO this on another thread? for blocking requires to load remote scripts
	self:safecallPage'init'
end

local function captureTraceback(err)
	return err..'\n'..debug.traceback()
end

function Browser:safecall(cb, ...)
	local res, errstr = xpcall(cb, captureTraceback, ...)
	if res then return true end

	-- if we were handling an error, and we got an error ...
	if self.handlingError then
		-- bail?
		print'error handling error:'
		io.stderr:write(errstr,'\n')
		os.exit()
		self.page = nil
	else
		self:setErrorPage(errstr)
	end
end

function Browser:setErrorPage(errstr)
	-- prevent infinite loops of setPage / setErrorPage
	self.handlingError = true
	self:setPage(errorPage, errstr)
	self.handlingError = false
end

function Browser:safecallPage(field, ...)
	local page = self.page
	if not page then return end
	local cb = page[field]
	if not cb then return end
	return self:safecall(cb, page, ...)
end

function Browser:update(...)
	-- super calls matrix setup and calls updategui
	-- so for the matrix to be setup before the first update,
	-- i have to call it here
	self.view:setup(self.width / self.height)

	self:safecallPage('update', ...)
	-- hmmmm OpenGL state issues ...
	gl.glUseProgram(0)
	gl.glBindTexture(gl.GL_TEXTURE_2D, 0)
	return Browser.super.update(self, ...)
end

function Browser:event(...)
	self:safecallPage('event', ...)
	return Browser.super.event(self, ...)
end

function Browser:updateGUI(...)
	if ig.igBeginMainMenuBar() then
		if ig.luatableInputText('', self, 'url', ig.ImGuiInputTextFlags_EnterReturnsTrue) then
			self:loadURL()
		end
		ig.igEndMainMenuBar()
	end
	self:safecallPage('updateGUI', ...)
	return Browser.super.updateGUI(self, ...)
end

return Browser
