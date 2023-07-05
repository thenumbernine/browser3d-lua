-- [[ cache all ffi.cdef calls since I'm using a nested package system, which means double ffi.cdef'ing things, which luajit doesn't like ...
local ffi = require 'ffi'
do
	-- also in preproc but I don't want to include other stuff
	local function removeCommentsAndApplyContinuations(code)
		-- should line continuations \ affect single-line comments?
		-- if so then do this here
		-- or should they not?  then do this after.
		repeat
			local i, j = code:find('\\\n')
			if not i then break end
			code = code:sub(1,i-1)..' '..code:sub(j+1)
		until false

		-- remove all /* */ blocks first
		repeat
			local i = code:find('/*',1,true)
			if not i then break end
			local j = code:find('*/',i+2,true)
			if not j then
				error("found /* with no */")
			end
			code = code:sub(1,i-1)..code:sub(j+2)
		until false

		-- [[ remove all // \n blocks first
		repeat
			local i = code:find('//',1,true)
			if not i then break end
			local j = code:find('\n',i+2,true) or #code
			code = code:sub(1,i-1)..code:sub(j)
		until false
		--]]

		return code
	end

	local old_ffi_cdef = ffi.cdef
	local alreadycdefd = {}
	function ffi.cdef(x)
		-- this isn't necessary but it does cut down on a lot of the ffi.cdef's
		-- make sure we're not just repeatedly cdef'ing nothing
		-- though does it matter if that's the case?
		-- for debugging ... yeah.  otherwise ... no?
		x = removeCommentsAndApplyContinuations(x)
		if x:match'^%s*$' then return end
		if alreadycdefd[x] then return end
		alreadycdefd[x] = debug.traceback()
		old_ffi_cdef(x)
	end

	-- same trick with ffi.metatype
	local old_ffi_metatype = ffi.metatype
	local alreadymetatype = {}
	function ffi.metatype(typename, mt)
		local v = alreadymetatype[typename]
		if not v then
			v = old_ffi_metatype(typename, mt)
			alreadymetatype[typename] = v
		end
		return v
	end
end
--]]

return ffi
