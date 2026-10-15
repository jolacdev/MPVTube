-- Persist UI choices and share atomic file replacement with the shortcut editor.
local M={}

function M.read(path)
    local file=io.open(path,'rb')
    if not file then return nil end
    local data=file:read('*a');file:close();return data
end

-- Write beside the destination; failed replacement preserves the previous file.
function M.write(path,data,original)
    local suffix=os.tmpname();os.remove(suffix);suffix=suffix:gsub('.*[/\\]','')
    local temporary=path..'.'..suffix
    local file=io.open(temporary,'wb')
    local ok=file and file:write(data)
    if file then ok=file:close() and ok end
    if ok then
        ok=os.rename(temporary,path)
        if not ok and original then
            -- Windows needs a recoverable rename when the destination already exists.
            local backup=temporary..'.bak'
            if os.rename(path,backup) then
                ok=os.rename(temporary,path)
                if ok then os.remove(backup) else os.rename(backup,path) end
            end
        end
    end
    os.remove(temporary)
    return not not ok
end

-- Explicit UI choices override configuration defaults, without editing the user's .conf.
function M.new(options)
    local mp,utils=require('mp'),require('mp.utils')
    local path=options.preferences_path
    if not path or path=='' then path=mp.command_native({'expand-path','~~/mpvtube-preferences.json'}) end
    local original=M.read(path)
    local saved={version=1}
    if original then saved=utils.parse_json(original) end
    local writable=type(saved)=='table' and saved.version==1 and (saved.animations==nil or type(saved.animations)=='boolean')
    if writable and saved.animations~=nil then options.animations=saved.animations end
    return function(enabled)
        if not writable then return false,'Preferences file is invalid or unsupported' end
        if M.read(path)~=original then return false,'Preferences changed; reopen MPV before saving' end
        local updated={}
        for key,value in pairs(saved) do updated[key]=value end
        updated.animations=enabled
        local data=utils.format_json(updated)
        if not data or not M.write(path,data,original) then return false,'Cannot save animations; check preferences folder permissions' end
        original,saved,options.animations=data,updated,enabled
        return true
    end
end

return M
