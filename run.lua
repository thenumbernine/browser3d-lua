#!/usr/bin/env luajit
local Browser = require 'browser'
Browser.url = (...) 
return Browser():run()
