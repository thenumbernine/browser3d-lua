local file = require 'ext.file'	-- TODO rename to path
local sdl = require 'ffi.sdl'
local ig = require 'imgui'
local errorPage = require 'browser.errorpage'

local Browser = require 'imguiapp.withorbit'()

Browser.title = 'Browser'

function Browser:initGL(...)
	Browser.super.initGL(self, ...)

	self.url = self.url or 'file://test.lua'
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

function Browser:handleData(data)
	-- now what kind of format should the file be?
	local gen, err = load(data, self.url)
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
	self:safecallPage('update', ...)
	return Browser.super.update(self, ...)
end

function Browser:event(...)
	self:safecallPage('event', ...)
	return Browser.super.event(self, ...)
end

function Browser:updateGUI(...)
	if ig.igBeginMainMenuBar() then
		if ig.luatableTooltipInputText('url', self, 'url', ig.ImGuiInputTextFlags_EnterReturnsTrue) then
			self:loadURL()
		end
		ig.igEndMainMenuBar()
	end
	self:safecallPage('updateGUI', ...)
	return Browser.super.updateGUI(self, ...)
end

return Browser
