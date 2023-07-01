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
			error("url is ill-formatted "..tostring(url))
		end
	end
	if proto == 'file' then
		self:loadFile(rest)
	elseif proto == 'http' then
		self:loadHTTP(url)
	else
		error("unknown protocol "..tostring(proto))
	end
end

function Browser:loadFile(filename)
	if not file(filename):exists() then
		-- ... have the browser show a 'file missing' page
		return
	end
	self:handleData(file(filename):read())
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

function Browser:setPage(gen, ...)
	self:safecall(function()
		self.page = gen(self)
		if self.page then
			sdl.SDL_SetWindowTitle(self.window, self.page.title or '')
		end
	end)
	self:safecallPage'init'
end

function Browser:safecall(cb, ...)
	local errstr
	xpcall(function(...)
		cb(page, ...)
	end, function(err)
		errstr = err..'\n'..debug.traceback()
	end, ...)
	if errstr then
		self:setErrorPage(errstr)
	end
end

function Browser:setErrorPage(errstr)
	--[[
	self:setPage(errorPage, self, errstr)
	--]]
	xpcall(function()
		self.page = errorPage(self, errstr)
	end, function(err)
		errstr = err..'\n'..debug.traceback()
-- or exit?
print('error handling error:', errstr)
		self.page = nil
	end)
end

function Browser:safecallPage(field, ...)
	local page = self.page
	if not page then return end
	local cb = page[field]
	if not cb then return end
	return self:safecall(cb, ...)
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
