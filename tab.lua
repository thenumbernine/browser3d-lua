-- require this first so it modifies ffi first
local ffi = require 'browser.ffi'

local path = require 'ext.path'
local class = require 'ext.class'
local table = require 'ext.table'
local tolua = require 'ext.tolua'
local gl = require 'gl'
local sandbox = require 'browser.sandbox'
local errorPage = require 'browser.errorpage'

local Tab = class()

local function call(f, ...)
	return f(...)
end

local function replacearg(i, x, ...)
	if select('#', ...) == 0 then return end
	-- if I had a ternary (that worked with booleans) then I could turn this if into one line ...
	if i == 1 then
		return x, select(2, ...)
	else
		return (...), replacearg(i-1, x, select(2, ...))
	end
end

function Tab:init(args)
	self.browser = assert(args.browser)
	self.url = args.url or self.url or 'file://pages/test.lua'
	assert(type(self.url) == 'string')

	-- start off a thread for our modified environment
	self.thread = self.browser.threads:add(self.threadLoop, self)
end

-- call this from another thread
function Tab:resumecall(field, ...)
	coroutine.resume(self.thread, self[field], self, ...)
end

-- everything else in Tab should only be called from the tab's own thread

function Tab:threadLoop()
	local result = self:setPageURL()
	while not self.done do
		result = call(coroutine.yield(result))
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
	elseif proto == 'https' then
		return self:loadHTTPS(url)
	else
		return nil, "unknown protocol "..tostring(proto)
	end
end

function Tab:loadFile(filename)
	return path(filename):read()
end

function Tab:loadHTTP(url)
	return require 'socket.http'.request(url)
end

-- [[ lua-ssl-based ... but that means now I have to build luassl for luajit...
function Tab:loadHTTPS(url)
	local data = table()
	local res, err
	xpcall(function()
		local https = require 'ssl.https'
		local ltn12 = require 'ltn12'
		res, err = https.request{
			url = url,
			sink = ltn12.sink.table(data),
			protocol = 'tlsv1',
		}
	end, function(err)
		print(err..'\n'..debug.traceback())
	end)
	return res and data:concat(), err
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
--print('path(url):exists()', path(url):exists(), url)
		if path(url):exists() then
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
	elseif proto == 'https' then
		self:setPageHTTPS(url)
	else
		self:setErrorPage("unknown protocol "..tostring(proto))
	end
end

function Tab:setPageFile(filename)
	if not path(filename):exists() then
		-- ... have the browser show a 'file missing' page
		self:setErrorPage("couldn't load file "..tostring(filename))
		return
	end

	local data, err = path(filename):read()
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

function Tab:setPageHTTPS(url)
	local data, reason = self:loadHTTPS(url)
	if not data then
		self:setErrorPage("couldn't load url "..tostring(url)..': '..tostring(reason))
	else
		self:handleData(data)
	end
end


function Tab:handleData(data)
	if type(data) ~= 'string' then
		-- error and not errorPage because this is an internal browser code convention
		error("handleData got bad data: "..tolua(data))
	end

	-- sandbox env

	-- [==[ sandboxing _G from require()
	-- this was my attempt to make a quick fix to using all previous glapp subclasses as pages ...
	-- the problem occurs because browser here already require'd glapp, which means glapp is in package.loaded, and with its already-defined _G, which has no 'browser'
	-- I was trying to create a parallel require()/package.loaded , one with _G having 'browser', and using that as a detect, but.... it's getting to be too much work
	-- ... maybe I can use another kind of detect ...

	--[===[ why doesn't this work
	local env
	xpcall(function()
		env = sandbox(_G)
	end, function(err)
		print(tostring(err)..'\n'..debug.traceback())
	end)
	--]===]
	-- [===[ ... but this works?
	local function shallowcopy(t)
		local r = {}
		for k,v in pairs(t) do r[k] = v end
		return r
	end

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

	replace the local file searchers for ones that search remote+local
	--]]
	env.package.searchers = shallowcopy(_G.package.searchers)

	-- reset package.loaded
	env.package.loaded = {}

	-- add defaults
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
		local v = _G.package.loaded[field]
		env[field] = v
		env.package.loaded[field] = v
	end
	env.package.loaded._G = env
	env.package.loaded.package = env.package

	-- now I guess I need my own require() function
	-- and maybe get rid of package searchers and loaders? maybe? not sure?
	local function findchunk(env, name)
		local errors = ("module '%s' not found"):format(name)
		for i,searcher in ipairs(env.package.searchers) do
			local chunk = searcher(name)
			if type(chunk) == 'function' then
				return chunk
			elseif type(chunk) == 'string' then
				errors = errors .. chunk
			end
		end
		return nil, errors
	end

	-- needs env in closure
	function env.require(name)
		local v = env.package.loaded[name]
		if v == nil then
			v = assert(findchunk(env, name))(name)
			if v == nil then v = true end
			env.package.loaded[name] = v
		end
		return v
	end
	--]===]

	-- [[ inserting the searcher first means possibility of every resource being delayed in its loading for remote urls
	table.insert(env.package.searchers, 1, function(name)
		-- very first, try relative URL to our page
		local data, err = self:searchURLRelative(name)
		if data then
			local gen

			-- TODO save 'dir' somewhere?
			-- or break down self.url object?
			local dir, pagename = self.url:match'(.*)/(.-)'

			-- TODO name is the require(), instead provide the found file name
			gen, err = load(data, dir..'/'..name, nil, self.env)
			if gen then return gen end
		end
		return err
	end)
	--]]

	-- set browser as a global or package?
	env.browser = self.browser
	env.browserTab = self.browserTab
--print('env', env)
--print('env.browser', env.browser)
	
	-- without this, subequent require()'s will have the original _G
	-- this has to be run on the tab's thread
	setfenv(0, env)

	local function addCacheShim(origfunc, argno)
		argno = argno or 1
		return function(...)
			local filename = select(argno, ...)

			-- if proto isn't file then
			-- ... fail for writing
			-- ... fail for io.rename
			-- ... fail for io.mkdir
			-- ... fail for io.popen
			--[[ if we fall through to the original file always then we can't get paths relative to the file:// url...
			if self.proto == 'file' then
				-- TODO relative path? page working dir? emulate behavior of remote?
				return origfunc(...)
			end
			--]]

			--[[ this is io.open specific
			-- how to put function-specific stuff in here ...
			local filename, mode = ...
			if mode:find'w' then return nil, "can't write to remote urls" end
			--]]

			local cacheName = self.cache[filename]
			if not cacheName then
				local cacheDir = self.browser.cacheDir
				cacheName = (cacheDir/filename).path	-- TODO hash base url or something? idk...

				-- [[ don't allow cached files to write outside the cache folder
				if cacheName:sub(1,#cacheDir.path) ~= cacheDir.path then
					return false, "tried to load file outside of the base directory"
				end
				--]]

				local dir, basename = path(cacheName):getdir()
				assert(dir)
				path(dir):mkdir(true)

--print('mapping file', filename,'to', cacheName)
				local data, err = self:loadURLRelative(filename)
				if not data then return data, err end
				path(cacheName):write(data)
				self.cache[filename] = cacheName
			end
			if not cacheName then
				return nil, "failed to create cache entry for file "..tostring(filename)
			end
			return origfunc(replacearg(argno, cacheName, ...))
		end
	end
	
	-- also load ffi - with its modified cdef
	env.package.loaded.ffi = ffi

	-- shim all io.open's to - upon remote protocols - check remote first
	-- or just use the page protocol as the cwd in general
	env.package.loaded.io = shallowcopy(env.package.loaded.io)
	env.io = env.package.loaded.io
	env.io.open = addCacheShim(io.open)
	env.io.lines = addCacheShim(io.lines)

	--[=[ TODO image-luajit still uses per-format library calls that use FILE for local access...
	env.ffi.C.fopen = addCacheShim(ffi.C.fopen)
	env.ffi.C.TIFFOpen = addCacheShim(ffi.C.TIFFOpen)
	env.ffi.C.ffopen = addCacheShim(ffi.C.ffopen)			-- fits
	env.ffi.C.DGifOpenFileName = addCacheShim(ffi.C.DGifOpenFileName)
	--]=]

	-- sandbox filesystem via cache file shim
	do
		--[=[ TODO work around lfs?
		local lfs = env.require 'ext.detect_lfs'
		--]=]
		-- [=[ or just work around other ext.io / os stuff that uses lfs?
		local extos = env.require 'ext.os'
		extos.mkdir = addCacheShim(extos.mkdir)
		extos.rmdir = addCacheShim(extos.rmdir)
		extos.isdir = addCacheShim(extos.isdir)
		extos.listdir = addCacheShim(extos.listdir)
		extos.rlistdir = addCacheShim(extos.rlistdir)
		extos.fileexists = addCacheShim(extos.fileexists)
		--]=]

		local stdio = env.require 'ffi.c.stdio'
		-- TODO for replacing ffi, wrap the shim in a ffi closure
		stdio.fopen = addCacheShim(stdio.fopen)

		-- NOTICE, like using stdio=require'ffi.c.stdio' stdio.fopen rather than ffi.C.fopen
		-- same here, I'm going to require using require'imgui' over require'ffi.cimgui' for ImFontAtlas_AddFontFromFileTTF 
		local imgui = env.require 'imgui'
		imgui.ImFontAtlas_AddFontFromFileTTF = addCacheShim(imgui.ImFontAtlas_AddFontFromFileTTF, 2)

		-- bypass GLApp :run() and ImGuiApp
		-- TODO what about windows and case-sensitivity?  all case permutations of glapp need to be included ...
		-- or Windows-specific, lowercase the filename ..?
		local GLApp = env.require 'glapp'
		function GLApp:run() return self end
		function GLApp:exit() end
		-- thanks to my package.path containing ?.lua;?/?.lua ...
		env.package.loaded['glapp.glapp'] = env.package.loaded['glapp']

		local ImGuiApp = env.require 'imguiapp'
		function ImGuiApp:initGL() end
		function ImGuiApp:exit() end
		function ImGuiApp:event() end
		function ImGuiApp:update() end
		env.package.loaded['imguiapp.imguiapp'] = env.package.loaded['imguiapp']
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
	-- [[ out with the old?
	if self.page and self.page.exit then
		self.page:exit()
	end
	--]]

	self.page = gen(...)
end

function Tab:setPage(gen, ...)
	self.cache = {}

	self:safecall(self.setPageProtected, self, gen, ...)

	if not self.page then
		self:setErrorPage('no page')
		return
	end

	-- reset GL state
	gl.glPopAttrib()
	gl.glPushAttrib(gl.GL_ALL_ATTRIB_BITS)

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
		self:safecallPage('initGL', self.env.require'gl', 'gl')
	
		--[[
		gl.glPushAttrib(gl.GL_TRANSFORM_BIT)
		gl.glMatrixMode(gl.GL_PROJECTION)
		gl.glPushMatrix()
		gl.glMatrixMode(gl.GL_MODELVIEW)
		gl.glPushMatrix()
		-- TODO push texture, color, etc matrices?
		--]]
		-- [[
		self.projMat = ffi.new('float[16]')
		self.mvMat = ffi.new('float[16]')
		gl.glGetFloatv(gl.GL_PROJECTION_MATRIX, self.projMat)
		gl.glGetFloatv(gl.GL_MODELVIEW_MATRIX, self.mvMat)
		--]]
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
	-- or how about, only do this if no initGL is present?
	if self.page and not self.page.initGL then
		self.browser.view:setup(self.browser.width / self.browser.height)
	end

	if self.page and self.page.initGL then
	--[[
		gl.glMatrixMode(gl.GL_MODELVIEW)
		gl.glPopMatrix()
		gl.glMatrixMode(gl.GL_PROJECTION)
		gl.glPopMatrix()
		gl.glPopAttrib(gl.GL_TRANSFORM_BIT)
	--]]
	-- [[
		gl.glMatrixMode(gl.GL_PROJECTION)
		gl.glLoadMatrixf(self.projMat)
		gl.glMatrixMode(gl.GL_MODELVIEW)
		gl.glLoadMatrixf(self.mvMat)
	--]]
	end
	
	self:safecallPage('update', ...)

	if self.page and self.page.initGL then
	--[[
		gl.glPushAttrib(gl.GL_TRANSFORM_BIT)
		gl.glMatrixMode(gl.GL_PROJECTION)
		gl.glPushMatrix()
		gl.glMatrixMode(gl.GL_MODELVIEW)
		gl.glPushMatrix()
	--]]
	-- [[
		gl.glGetFloatv(gl.GL_PROJECTION_MATRIX, self.projMat)
		gl.glGetFloatv(gl.GL_MODELVIEW_MATRIX, self.mvMat)
	--]]
	end
end

function Tab:event(...)
	self:safecallPage('event', ...)
end

function Tab:updateGUI(...)
	self:safecallPage('updateGUI', ...)
end

return Tab
