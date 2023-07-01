local file = require 'ext.file'	-- TODO rename to path
local sdl = require 'ffi.sdl'
local ig = require 'imgui'
local errorPage = require 'browser.errorpage'

local Browser = require 'imguiapp.withorbit'()

Browser.title = 'Browser'

function Browser:initGL(...)
	Browser.super.initGL(self, ...)

	self.url = self.url or 'file://./test.lua'
	self:loadURL()
end

function Browser:loadURL(url)
	url = url or self.url
	local proto, rest = url:match'^([^:]*)://(.*)'
	if not proto then
		-- try accessing it as a file
		if file(url):exists() then
			self.url = 'file:///'..url
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
	local fn, err = load(data, self.url)
	if not fn then
		-- report compile error
	else
		xpcall(function()
			self.page = fn(self)
			if self.page then
				sdl.SDL_SetWindowTitle(self.window, self.page.title or '')
			end
		end, function(err)
			self.page = errorPage(err)
		end)
		self:safecall'init'
	end
end

function Browser:safecall(field, ...)
	local page = self.page
	if not page then return end
	local cb = page[field]
	if not cb then return end
	local errstr
	xpcall(function(...)
		cb(page, ...)
	end, function(err)
		errstr = err..'\n'..debug.traceback()
print('errstr', errstr)	
	end, ...)
	if errstr then
		xpcall(function()
			self.page = errorPage(errstr)
		end, function(err)
			local errstr2 = err..'\n'..debug.traceback()
print('errstr2', errstr2)
			self.page = nil
		end)
	end
end

function Browser:update(...)
	self:safecall('update', ...)
	return Browser.super.update(self, ...)
end

function Browser:event(...)
	self:safecall('event', ...)
	return Browser.super.event(self, ...)
end

function Browser:updateGUI(...)
	if ig.igBeginMainMenuBar() then
		if ig.luatableTooltipInputText('url', self, 'url', ig.ImGuiInputTextFlags_EnterReturnsTrue) then
			self:loadURL()
		end
		ig.igEndMainMenuBar()
	end
	self:safecall('updateGUI', ...)
	return Browser.super.updateGUI(self, ...)
end

return Browser
