#!/usr/bin/env luajit
local Browser = require 'browser'
Browser.url = (...) 
Browser():run()
