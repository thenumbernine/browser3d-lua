--[[
create a fully-sandboxed lua global table
with its own require() and set of package.loaded[]'s

TODO this belongs in its own library or something - somewhere that other projects can use it
--]]
local function shallowcopy(t)
	local r = {}
	for k,v in pairs(t) do r[k] = v end
	return r
end

local function sandbox(srcenv)
	srcenv = srcenv or _G
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
		env[k] = srcenv[k]
	end
	-- what kind of args do we want?
	env.arg = {}

	-- make sure our sandbox _G points back to itself so the page can't modify the browser env
	env._G = env

	-- also we're going to need a new package table,
	-- otherwise browser environment will collide with page environments
	-- namely that the page's glapp's _G will otherwise point to the browser _G instead of the page _G
	env.package = shallowcopy(srcenv.package)
	env.package.preload = shallowcopy(srcenv.package.preload)

	--[[
	four searchers:
	1) package.preload table
	2) package.searchpath / package.path
	3) package.searchpath / package.cpath
	4) 'all in one loader'

	replace the local file searchers for ones that search remote+local
	--]]
	env.package.searchers = shallowcopy(srcenv.package.searchers)

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
		-- TODO shallowcopy this too?  if it is modified then so will the srcenv be?
		local v = srcenv.package.loaded[field]
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

	return env
end

return sandbox
