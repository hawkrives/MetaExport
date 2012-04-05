--[[----------------------------------------------------------------------------

MetaExportTask.lua
based on FtpUploadTask.lua


LrFileUtils.createAllDirectories( path )
Creates a directory at a given path, recursively creating any parent directories that do not already exist.
LrFileUtils.exists( path )
Reports whether a given path indicates an existing file or directory.
------------------------------------------------------------------------------]]

-- Lightroom API
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrErrors = import 'LrErrors'
local LrDialogs = import 'LrDialogs'
local LrDate = import 'LrDate'

--============================================================================--

-- import util
require 'MetaUtil'

MetaExportTask = {}

--------------------------------------------------------------------------------

function MetaExportTask.processRenderedPhotos( functionContext, exportContext )

	-- Make a local reference to the export parameters.
	
	local exportSession = exportContext.exportSession
	local exportParams = exportContext.propertyTable

	-- Store and check export params
	local pathbase = exportParams.metaFormat
	local root = exportParams.destPath
	local default = exportParams.metaDefault
	local nonexist = exportParams.metaNonexist
	local metaSR = exportParams.metaStripReplace
	local metaReplace = exportParams.metaReplace
	local timeSource = exportParams.timeSource
	
	if pathbase == "" then
		LrDialogs.message( "Meta Export - Error", "Folder format cannot be empty." )
		return
	end
	if (not root) or (root == "") then
		LrDialogs.message( "Meta Export - Error", "Destination cannot be empty." )
		return
	end
	
	if (metaSR ~= "strip") and (metaSR ~= "replace") then
		LrDialogs.message( "Meta Export - Error", "Invalid selection for '/ or \\ in metadata.'" )
		return
	end
	if metaReplace == "/" or metaReplace == "\\" then
		local value = LrDialogs.confirm( "Meta Export - Warning", "/ replace contains / or \\. Continue?" )
		if value == "cancel" then
			return
		end
	end
	
	if (timeSource ~= "metadata") and (timeSource ~= "timeofexport") then
		LrDialogs.message( "Meta Export - Error", 'Invalid selection for "Time"', "critical" )
		return
	end
	local texport = LrDate.currentTime()
	
	-- Set progress title.
	
	local nPhotos = exportSession:countRenditions()
	local atitle = nil
	if nPhotos > 1 then
		atitle = "Meta Exporting ".. nPhotos .. " photos..."
	else
		atitle = "Meta Exporting 1 photo..."
	end
	local progressScope = exportContext:configureProgress {
						title = atitle,
					}

	local failures = {}

	for _, rendition in exportContext:renditions{ stopIfCanceled = true } do
	
		-- Wait for next photo to render.

		local success, pathOrMessage = rendition:waitForRender()
		
		-- Check for cancellation again after photo has been rendered.
		
		if progressScope:isCanceled() then 
			if success then
				table.insert( failures, string.format("%s (User cancelled.)", filename ) )
			else
				table.insert( failures, string.format("%s (User cancelled + %s)", filename, pathOrMessage ) )
			end
			break
		end
		
		if success then

			local filename = LrPathUtils.leafName( pathOrMessage )
			
			-- build path
			local t = nil
			if timeSource == "metadata" then
				t = rendition.photo:getRawMetadata("dateTimeOriginal")
			elseif timeSource == "timeofexport" then
				t = texport
			end
			-- replace meta first, then date
			--local newpath = interp(pathbase, rendition.photo:getFormattedMetadata())
			local newpath = LrDate.timeToUserFormat(t, pathbase)
			newpath = interp(newpath, rendition.photo:getFormattedMetadata(), default, nonexist, metaSR, metaReplace )
			
			-- Translate BADCHARACTERS into safecharacter
			newpath = newpath:gsub(":", "_")
			
			newpath = LrFileUtils.resolveAllAliases(LrPathUtils.child(root, newpath))
			--do return end
			
			if not LrFileUtils.exists( newpath ) then LrFileUtils.createAllDirectories( newpath ) end
			
			--Check if file exists:
			local newfile = LrPathUtils.child(newpath, filename)
			local doCopy = true

			if LrFileUtils.exists( newfile ) then
				local overorskip = LrDialogs.promptForActionWithDoNotShow{
					message = "Meta Export - File exists.",
					info = "The file (" .. newfile .. ") already exists.\nDo you wish to overwrite the file?\n(Overwrite will completely delete the existing file. Skip will leave the existing file. Cancel will stop the export.)",
					actionPrefKey = "overwriteorskip",
					verbBtns = {
						{ label = "Overwrite", verb = "overwrite"},
						{ label = "Skip", verb = "skip"},
					}
				}
				if overorskip == "overwrite" then
					success, reason = LrFileUtils.delete(newfile)
					if not success then
						LrDialogs.message( "Meta Export - Warning", string.format("Cannot delete (%s): %s.\nFile will not be overwritten.", newfile, reason ) )
						table.insert( failures, string.format("%s (File could not be overwritten.)", filename ) )
						doCopy = false
					end
				
				elseif overorskip == false then
					table.insert( failures, string.format("%s (User cancelled.)", filename ) )
					break
				else
					doCopy = false
				end
			end
			
			if doCopy then
				local success, reason = LrFileUtils.copy( pathOrMessage, LrPathUtils.child(newpath, filename) )
				if not success then
				
					-- If we can't upload that file, log it.  For example, maybe user has exceeded disk
					-- quota, or the file already exists and we don't have permission to overwrite, or
					-- we don't have permission to write to that directory, etc....
					table.insert( failures, string.format("%s (%s)", filename, reason ) )
				end
						
				-- When done with photo, delete temp file. There is a cleanup step that happens later,
				-- but this will help manage space in the event of a large upload.
				
				LrFileUtils.delete( pathOrMessage )
			end
					
		else
			table.insert( failures, string.format("%s (%s)", filename, pathOrMessage ) )
		end
		
	end

	if #failures > 0 then
		local message
		if #failures == 1 then
			message = "1 file failed to copy correctly."
		else
			message = "^1 files failed to copy correctly.", #failures
		end

		LrDialogs.message( message, table.concat( failures, "\n" ) )
	end
	
end