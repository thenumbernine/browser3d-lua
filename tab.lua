-- require this first so it modifies ffi first
local ffi = require 'browser.ffi'

local file = require 'ext.file'	-- TODO rename to path
local class = require 'ext.class'
local table = require 'ext.table'
local tolua = require 'ext.tolua'
local sdl = require 'ffi.sdl'
local gl = require 'gl'
local errorPage = require 'browser.errorpage'

local Tab = class()

function Tab:init(args)
	self.browser = assert(args.browser)
	self.url = args.url or self.url or 'file://pages/test.lua'
	assert(type(self.url) == 'string')
	
	-- start off a thread for our modified environment
	self.thread = coroutine.create(function()
		self:setPageURL()
		coroutine.yield()

		repeat
			local args = table.pack(coroutine.yield())
			if self.cmd == 'update' then
				self:safecallPage('update', args:unpack())
			elseif self.cmd == 'updateGUI' then
				self:safecallPage('updateGUI', args:unpack())
			elseif self.cmd == 'event' then
				self:safecallPage('event', args:unpack())
			end
			self.cmd = nil
		until self.done
	end)
	coroutine.resume(self.thread)
end

function Tab:requireRelativeToLastPage(name)
	local proto, rest = name:match'^([^:]*)://(.*)'
	-- if no prefix is found ...
	if not proto then
		-- then first try assuming it is a relative path
		if self.proto then
			-- TODO here make a URL with path or whatever and change to 'name'
		end
	end
	if proto == 'file' then
		self:setPageFile(rest)
	elseif proto == 'http' then
		self:setPageHTTP(url)
	else
		self:setErrorPage("unknown protocol "..tostring(proto))
	end
end

-- this function will expect a URL in proper format
-- no implicit-files like :setPageURL (which should handle whatever the user puts in the titlebar)
-- it'll return data or return false and an error message
function Tab:loadURL(url)
	local proto, rest = url:match'^([^:]*)://(.*)'
	if proto == 'file' then
		return self:loadFile(rest)
	elseif proto == 'http' then
		return self:loadHTTP(url)
	else
		return nil, "unknown protocol "..tostring(proto)
	end
end

function Tab:loadFile(filename)
	return file(filename):read()
end

function Tab:loadHTTP(url)
	return require 'socket.http'.request(url)
end

-- TODO delineate some set of functions which error() shouldn't be permitted to be called within
-- only setErrorPage instead.
-- I'd say just wrap this all in xpcall,
-- but I'm already doing that within setPage
--
-- TODO have this use 'loadURL'
function Tab:setPageURL(url)
	url = url or self.url
	local proto, rest = url:match'^([^:]*)://(.*)'
	self.proto = proto
	if not proto then
		-- try accessing it as a file
--print('file(url):exists()', file(url):exists(), url)
		if file(url):exists() then
			proto = 'file'
			self.proto = 'file'
			self.url = 'file://'..url
			self:setPageFile(url)
			return
		else
			self:setErrorPage("url is ill-formatted / file not found: "..tostring(url))
			return
		end
	end
	if proto == 'file' then
		self:setPageFile(rest)
	elseif proto == 'http' then
		self:setPageHTTP(url)
	else
		self:setErrorPage("unknown protocol "..tostring(proto))
	end
end

function Tab:setPageFile(filename)
	if not file(filename):exists() then
		-- ... have the browser show a 'file missing' page
		self:setErrorPage("couldn't load file "..tostring(filename))
		return
	end

	local data, err = file(filename):read()
	if not data then
		self:setErrorPage("couldn't read file "..tostring(filename)..": "..tostring(err))
		return
	end

	self:handleData(data)
end

function Tab:setPageHTTP(url)
	local data, reason = require 'socket.http'.request(url)
	if not data then
		self:setErrorPage("couldn't load url "..tostring(url)..': '..tostring(reason))
	else
		self:handleData(data)
	end
end

local function shallowcopy(t)
	return table(t):setmetatable(nil)
end

function Tab:handleData(data)
	if type(data) ~= 'string' then
		-- error and not errorPage because this is an internal browser code convention
		error("handleData got bad data: "..tolua(data))
	end
	
	-- sandbox env
	
	--[==[ simple sandbox:
	local env = setmetatable({browser=self}, {__index=_G})
	--[[ env.require to require remote ...
	env.require = function(name)
		local v = package.loaded[name]
		if v ~= nil then return v end
		-- first try same url protocol
		if self.proto ~= 'file' then
			-- hmm how about file ext ...
			-- now I need one extension for lua require files, another for lua-driven pages ...
			-- or not? maybe I just need the page-loader to be routed through the remote-require function?
			-- TODO this is basically another package.searchers
			local cb, err = self:requireRelativeToLastPage(name)
			if cb then
				v = cb(name) 
				if v == nil then v = true end
				package.loaded[name] = v
				return v
			end
		end
		return require(name)
	end
	--]]
	--]==]

	-- [==[ sandboxing _G from require()
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
	env.browser = self.browser
	env.browserTab = self.browserTab
--print('env', env)
--print('env.browser', env.browser)
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

	TODO replace the local file searchers for ones that search remote+local
	and then shim all io.open's to - upon remote protocols - check remote first
		or just use the page protocol as the cwd in general
	--]]
	env.package.searchers = shallowcopy(_G.package.searchers)

	-- [[ inserting the searcher first means possibility of every resource being delayed in its loading for remote urls
	table.insert(env.package.searchers, 1, function(name)
		-- very first, try relative URL to our page
		local data, err = self:searchURLRelative(name)
		if data then
			local gen
			gen, err = load(data, self.url..'/'..name, nil, self.env)
			if gen then return gen end
		end
		return err
	end)
	--]]

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
	-- also load ffi - with its modified cdef
	env.package.loaded.ffi = ffi

	-- now shim io ...
	env.package.loaded.io = shallowcopy(env.package.loaded.io)
	env.io = env.package.loaded.io

	local function addCacheShim(origfunc)
		return function(...)
			-- if proto isn't file then 
			-- ... fail for writing
			-- ... fail for io.rename 
			-- ... fail for io.mkdir
			-- ... fail for io.popen
			if self.proto == 'file' then return origfunc(...) end
			local name, mode = ...
			if mode:find'w' then return nil, "can't write to remote urls" end

			local cacheName = self.cache[name] 
			if not cacheName then
				cacheName = 'cache/'..name	-- TODO hash url or something? idk...
				local data, err = self:loadURLRelative(name)
				if not data then return data, err end
				file(cacheName):write(data)
				self.cache[name] = cacheName
			end
			if not cacheName then 
				return nil, "failed to create cache entry for file "..tostring(name)
			end
			return origfunc(cacheName, select(2, ...))
		end
	end

	-- shim io.open
	env.io.open = addCacheShim(io.open)
	--[[ TODO image-luajit still uses per-format library calls that use FILE for local access...
	env.ffi.C.fopen = addCacheShim(ffi.C.fopen)
	env.ffi.C.TIFFOpen = addCacheShim(ffi.C.TIFFOpen)
	env.ffi.C.ffopen = addCacheShim(ffi.C.ffopen)			-- fits
	env.ffi.C.DGifOpenFileName = addCacheShim(ffi.C.DGifOpenFileName)
	--]]
	do
		local gen, err = load([[
-- without this, subequent require()'s will have the original _G
-- TODO need a new thread for all this
setfenv(0, _G)

-- now I guess I need my own require() function
-- and maybe get rid of package searchers and loaders? maybe? not sure?
local function findchunk(name)
	local errors = ("module '%s' not found"):format(name)
	for i,searcher in ipairs(package.searchers) do
		local chunk = searcher(name)
		if type(chunk) == 'function' then
			return chunk
		elseif type(chunk) == 'string' then
			errors = errors .. chunk
		end
	end
	return nil, errors
end

function require(name)
	local v = package.loaded[name]
	if v == nil then
		v = assert(findchunk(name))(name)
		if v == nil then v = true end
		package.loaded[name] = v
	end
	return v
end

-- bypass GLApp :run() and ImGuiApp
-- TODO what about windows and case-sensitivity?  all case permutations of glapp need to be included ...
-- or Windows-specific, lowercase the filename ..?
do
	local GLApp = require 'glapp'
	function GLApp:run() return self end
	package.loaded['glapp.glapp'] = package.loaded['glapp']

	local ImGuiApp = require 'imguiapp'
	function ImGuiApp:initGL() end
	function ImGuiApp:exit() end
	function ImGuiApp:event() end
	function ImGuiApp:update() end
	package.loaded['imguiapp.imguiapp'] = package.loaded['imguiapp']
end

]], 'init sandbox of '..self.url, nil, env)
		if not gen then
			-- report compile error
			self:setErrorPage('failed to load '..tostring(self.url)..': '..tostring(err))
			return
		else
			if not self:safecall(gen) then return end
		end
	end
	--]==]

	-- get our page generation module
	local gen, err = load(data, self.url, nil, env)
	if not gen then
		self:setErrorPage('failed to load '..tostring(self.url)..': '..tostring(err))
		return
	end

	self.env = env

	self:setPage(gen)
end

--[[
run this after a page is loaded
it will use the browser's current state
--]]
function Tab:searchURLRelative(name)
	assert(self.url)
	assert(self.proto)
--print('searchURLRelative self.url', self.url)
--print('searchURLRelative self.proto', self.proto)

	local errs = ''

	-- TODO a nice server feature would be to pass a file and search-path and have the server do the requests
	for _,searchpath in ipairs{
		'?.lua',
		'?/?.lua',
	} do
		local filename = searchpath:gsub('%?', (name:gsub('%.', '/')))
--print('searchURLRelative filename', filename)
		local data, err = self:loadURLRelative(filename)
		if data then return data end
		if err then
			errs = errs .. err .. '\n'
		end
	end
	return nil, errs
end

-- gets url for 'name' relative to url self.url
function Tab:getURLForRelativeFilename(filename)
	-- TODO use a proper URL object and break down the pieces , incl username, password, port, GET args, etc
	local dir, pagename = self.url:match'(.*)/(.-)'
	assert(dir)
--print('searchURLRelative dir', dir)
--print('searchURLRelative pagename', pagename)
	return dir..'/'..filename
end

function Tab:loadURLRelative(filename)
	-- TODO how about absolute-paths 'filename'?
	-- in that case, rename 'Relative' to 'ForCurrentPageURL' ?
	return self:loadURL(self:getURLForRelativeFilename(filename))
end

function Tab:setPageProtected(gen, ...)
	self.page = gen(...)
	-- TODO handle change pages / tabs
	if self.page then
		sdl.SDL_SetWindowTitle(self.window, self.page.title or '')
	end
end

function Tab:setPage(gen, ...)
	self.cache = {}
	
	self:safecall(self.setPageProtected, self, gen, ...)

	if not self.page then
		self:setErrorPage('no page')
		return
	end

	-- init GL state
--	gl.glPopAttrib()
--	gl.glPushAttrib(gl.GL_ALL_ATTRIB_BITS)

	if self.page then
		self.page.width = self.width
		self.page.height = self.height
	end

	-- TODO this on another thread? for blocking requires to load remote scripts
	self:safecallPage'init'

	-- for glapp interop support:
	if self.page
	and self.page.initGL
	then
		--[[
		self:safecallPage'initGL'
		--]]
		-- [=[
		local res, err = load([[
local page = ...
page:initGL(require 'gl', 'gl')
]], self.url, nil, self.env
		)
		if not res then
			self:setErrorPage('error calling initGL: '..tostring(err))
		end
		self:safecall(res, self.page)
		--]=]
	end
end

local function captureTraceback(err)
	return err..'\n'..debug.traceback()
end

function Tab:safecall(cb, ...)
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

function Tab:setErrorPage(errstr)
	-- prevent infinite loops of setPage / setErrorPage
	self.handlingError = true
	self:setPage(errorPage, errstr)
	self.handlingError = false
end

function Tab:safecallPage(field, ...)
	local page = self.page
	if not page then return end
	local cb = page[field]
	if not cb then return end
	return self:safecall(cb, page, ...)
end

function Tab:update(...)
	if self.page then
		self.page.width = self.browser.width
		self.page.height = self.browser.height
	end

	-- super calls matrix setup and calls updategui
	-- so for the matrix to be setup before the first update,
	-- i have to call it here
	-- TODO this?  this can mess with the page's own matrix setup...
	self.browser.view:setup(self.browser.width / self.browser.height)

--	self:safecallPage('update', ...)
end

function Tab:event(...)
--	self:safecallPage('event', ...)
end

function Tab:updateGUI(...)
--	self:safecallPage('updateGUI', ...)
end

return Tab
