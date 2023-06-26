local file = require 'ext.file'	-- TODO rename to path
local sdl = require 'ffi.sdl'
local Browser = require 'imguiapp.withorbit'()

Browser.title = 'Browser'

function Browser:initGL(...)
	Browser.super.initGL(self, ...)

	self:loadURL'file://./test.lua'
end

function Browser:loadURL(url)
	local proto, rest = url:match'^([^:]*)://(.*)'
	if not proto then error("url is ill-formatted "..tostring(url)) end
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
	local fn, err = load(data)
	if not fn then
		-- report compile error
	else
		xpcall(function()
			self.page = fn(self)
			if self.page then
				sdl.SDL_SetWindowTitle(self.window, self.page.title or '')
				if self.page.init then
					self.page:init()
				end
			end
		end, function(err)
			-- report execution error
		end)
	end
end

function Browser:update(...)
	if self.page and self.page.update then
		self.page:update()
	end
	return Browser.super.update(self, ...)
end

function Browser:event(...)
	if self.page and self.page.event then
		self.page:event(...)
	end
	return Browser.super.event(self, ...)
end

function Browser:updateGUI(...)
	if self.page and self.page.updateGUI then
		self.page:updateGUI(...)
	end
	return Browser.super.updateGUI(self, ...)
end

return Browser
