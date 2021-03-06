local LrDate = import 'LrDate'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

--[[----------------------------------------------------------------------------
interp implementation heavily modified from here: 
http://lua-users.org/wiki/StringInterpolation
Credited to Rici Lake
http://lua-users.org/wiki/RiciLake
------------------------------------------------------------------------------]]
function interp(s, tab, default, nonexist, sr, rvalue)
	function gfunc(w) 
		local key, sstart, send = getsplicepoint(w:sub(3, -2))
		
		local element = tab[key]
		if element then
			if sstart and send then
				element = element:sub(sstart, send)
			end
			if sr == "strip" then
				element = element:gsub('/', '')
				element = element:gsub('\\', '')
			elseif sr == "replace" then
				element = element:gsub('/', rvalue)
				element = element:gsub('\\', rvalue)
			end
		end
		if element == "" then
			return default
		end
		if (not element) and nonexist == "" then
			nonexist = key
		end
		return element or nonexist
	end
	
	return (s:gsub('($%b{})', gfunc))
end

function buildtime(photo, options, texport, otable)

	if (options.timeSource == "metadata") then
		t = photo:getRawMetadata("dateTimeOriginal")
		if ( (t == "") or (t == nil) ) then
			t = photo:getRawMetadata("dateTimeDigitized")
		end
	elseif (options.timeSource == "timeofexport") then
		t = texport
	end
	-- handle missing time metadata
	if (t == "" or t == nil ) then
		if (options.timeMissing == "unix" ) then
			t = LrDate.timeFromPosixDate(0)					
		elseif (options.timeMissing == "skip" ) then
			return nil
		elseif (options.timeMissing == "current" ) then
			t = texport
		elseif (options.timeMissing == "custom" ) then
			t = LrDate.timeFromComponents(options.timeYear, 
				options.timeMonth, options.timeDay, options.timeHour,
				options.timeMinute, options.timeSecond, "local")
		end
	end
	return t
end

function buildpath(photo, options, texport, otable)
	local pathbase = options.metaFormat
	
	-- replace meta first, then date
	--local newpath = interp(pathbase, rendition.photo:getFormattedMetadata())
	local t = buildtime(photo, options, texport, otable)
	if (not t) then
		return nil
	end
	local newpath = LrDate.timeToUserFormat(t, pathbase)
	newpath = interp(newpath, photo:getFormattedMetadata(), options.metaDefault, options.metaNonexist, options.metaStripReplace, options.metaReplace )

	-- Translate BADCHARACTERS into safecharacter
	newpath = newpath:gsub(":", "_")
	
	return LrFileUtils.resolveAllAliases(LrPathUtils.child(options.destPath, newpath))
end

function getsplicepoint(s)
	local sfirst = s:find(":")
	local slast
	local key = s
	if sfirst then
		slast = s:find(":", sfirst+1)
		key = s:sub(1, sfirst-1)
	end
	if (not sfirst) or (not slast) then
		return key, nil, nil
	end
	local sfirstn = tonumber(s:sub(sfirst+1, slast-1))
	slast = tonumber(s:sub(slast+1))
	if (not sfirst) or (not slast) then
		return key, nil, nil
	end
	return key, sfirstn, slast
end

function round(num) 
	if num >= 0 then return math.floor(num) 
	else return math.ceil(num) end
end

function tzstring(tz)
	return string.format("%+03d%02d", round(tz / 3600), tz/60%60)
end


--[[----------------------------------------------------------------------------
Dummy Photo class thing using base from:
http://lua-users.org/wiki/SimpleLuaClasses
------------------------------------------------------------------------------]]

PhotoDummy = {}
PhotoDummy.__index = PhotoDummy

function PhotoDummy.create(t)
   local photo = {}             -- our new object
   setmetatable(photo, Account)  -- make PhotoDummy handle lookup
   photo.time = t      -- initialize our object
   return photo
end

function PhotoDummy:getRawMetadata(key)
   return self.time
end

function PhotoDummy:getFormattedMetadata()
	return {}
end

