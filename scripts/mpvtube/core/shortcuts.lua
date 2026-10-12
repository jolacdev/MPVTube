-- One action registry supplies key bindings and labels for the in-player guide.
local M = {}
function M.defaults(options)
    local keys={}
    local volume_step=options.volume_step or 5
    local sync_step=options.sync_step or .05
    local function key(name,id,label,action,repeatable)
        keys[#keys+1]={key=name,id=id,label=label,action=action,repeatable=repeatable}
    end
    key('SPACE','pause-SPACE','Play / pause',{kind='pause'})
    for _,tier in ipairs({{'','short'},{'Shift+','precise'},{'Ctrl+','medium'},{'Ctrl+Alt+','long'}}) do
        for _,direction in ipairs({{'LEFT',-1},{'RIGHT',1}}) do
            key(tier[1]..direction[1],'seek-'..tier[2]..direction[1],tier[2]:gsub('^%l',string.upper)..' seek '..(direction[2]<0 and 'backward' or 'forward'),
                {kind='relative-seek',value=direction[2]*(options['seek_'..tier[2]] or ({precise=3,short=10,medium=60,long=300})[tier[2]])},true)
        end
    end
    key('UP','volume-up','Volume +'..volume_step..'%',{kind='volume-step',value=volume_step},true)
    key('DOWN','volume-down','Volume -'..volume_step..'%',{kind='volume-step',value=-volume_step},true)
    for _,item in ipairs({{'m','mute','Mute'},{'f','fullscreen','Fullscreen'},
        {'c','subtitles','Toggle subtitles'},{'i','pip','Mini player'},
        {'n','next','Next video'},{'p','previous','Previous video'},
        {'Shift+N','next','Next video'},{'Shift+P','previous','Previous video'},
        {'u','subtitle-override','Clean subtitle style'},
        {'Ctrl+p','native-menu','MPV menu'},{'Ctrl+Shift+p','properties','MPV properties'}}) do
        key(item[1],item[2]..'-'..item[1],item[3],{kind=item[2],show_feedback=true})
    end
    for _,item in ipairs({{'[','chapter-previous',-1},{']','chapter-next',1},
        {'B','audio-previous',-1},{'b','audio-next',1},
        {'Alt+v','sub-previous',-1},{'v','sub-next',1}}) do
        local track=item[2]:match('^(audio)') or item[2]:match('^(sub)')
        key(item[1],item[2],item[2]:gsub('-',' '),{kind=track and 'track-step' or 'chapter-step',track=track,value=item[3]})
    end
    for _,item in ipairs({{'g','sub',-sync_step},{'h','sub',sync_step},{'j','audio',-sync_step},{'k','audio',sync_step}}) do
        key(item[1],item[2]..'-delay-'..item[1],item[2]..' sync '..string.format('%+.0f ms',item[3]*1000),
            {kind='delay',track=item[2],value=item[3]},true)
    end
    key('Ctrl+Shift+k','sync-reset','Reset audio/subtitle sync',{kind='sync-reset'})
    key('.','frame-next','Next frame',{kind='frame',value=1},true)
    key(',','frame-previous','Previous frame',{kind='frame',value=-1},true)
    key('>','speed-up','Speed +0.25×',{kind='speed-step',value=.25},true)
    key('<','speed-down','Speed -0.25×',{kind='speed-step',value=-.25},true)
    key('F1','guide','Shortcut guide',{page='shortcuts'})
    key('Alt+c','subtitle-list','Subtitle track selector',{page='sub'})
    for _,item in ipairs({{'C','chapter-list','Chapters','chapters'},{'a','audio-list','Audio track selector','audio'},
        {'Ctrl+,','settings','Settings','settings'}}) do key(item[1],item[2],item[3],{page=item[4]}) end
    key('TAB','focus-next','Focus next control',{kind='focus',value=1})
    key('Shift+TAB','focus-previous','Focus previous control',{kind='focus',value=-1})
    key('BS','focus-reset','Clear menus and focus',{kind='clear-focus'})
    key('q','quit','Quit MPV',{command='quit'})
    key('s','screenshot','Take screenshot',{command='screenshot'})
    key('`','console','MPV console',{command='script-binding console/enable'})
    for digit=0,9 do key(tostring(digit),'seek-'..digit,'Seek '..digit..'0%',{kind='percent-seek',value=digit/10}) end
    return keys
end

M.categories={'Playback','Seeking','Chapters and playlist','Subtitles','Audio','Synchronization','Window and tools','Navigation'}
function M.category(action)
    local kind=action.kind or ''
    if kind=='delay' or kind=='sync-reset' then return 'Synchronization' end
    if kind=='focus' or kind=='clear-focus' then return 'Navigation' end
    if kind=='relative-seek' or kind=='percent-seek' or kind=='frame' then return 'Seeking' end
    if kind=='chapter-step' or kind=='next' or kind=='previous' or action.page=='chapters' then return 'Chapters and playlist' end
    if kind=='subtitles' or kind=='subtitle-override' or action.track=='sub' or action.page=='sub' then return 'Subtitles' end
    if kind=='volume-step' or kind=='mute' or action.track=='audio' or action.page=='audio' then return 'Audio' end
    if kind=='pause' or kind=='speed-step' then return 'Playback' end
    return 'Window and tools'
end

-- Normalize modifier aliases so Shift+c and C cannot evade duplicate detection.
function M.normalize(key)
    if type(key)~='string' or key=='' or key:find('[\r\n ]') then return nil end
    if key=='none' then return key end
    local modifiers={}
    while key:find('+',1,true) and key~='+' do
        local modifier,rest=key:match('^([^+]+)%+(.+)$')
        if not modifier or not ({Shift=true,Ctrl=true,Alt=true,Meta=true})[modifier] then break end
        modifiers[modifier],key=true,rest
    end
    if modifiers.Shift and key:match('^[a-zA-Z]$') then key=key:upper();modifiers.Shift=nil end
    local parts={}
    for _,modifier in ipairs({'Ctrl','Alt','Meta','Shift'}) do if modifiers[modifier] then parts[#parts+1]=modifier end end
    parts[#parts+1]=key
    return table.concat(parts,'+')
end

local function action_key(action)
    return table.concat({action.kind or action.page or action.command or '',action.track or '',tostring(action.value or '')},':')
end

function M.display_key(key)
    if key=='none' then return 'Unassigned' end
    local prefix,letter=(key or ''):match('^(.-)([A-Z])$')
    if letter and (prefix=='' or prefix:sub(-1)=='+') then key=prefix..'Shift+'..letter end
    return (key or ''):gsub('SPACE','Space'):gsub('TAB','Tab'):gsub('BS$','Backspace')
end

-- Menu hints and tooltips share the effective assignment, including edits and overrides.
function M.hint(state,action)
    local key=action and (state.shortcut_hints or {})[action_key(action)]
    return key and M.display_key(key)
end

function M.tip(state,action,label)
    if not label then return nil end
    label=label:gsub(' %([^()]*%)$','')
    local key=M.hint(state,action)
    if key then return label..' ('..key..')' end
    return label
end

function M.refresh(state,bindings)
    state.active_bindings=M.effective(state,bindings)
    local underlying={}
    local prefix='script-binding '..(state.script_name or 'mpvtube')..'/'
    for _,binding in ipairs(bindings or {}) do
        local command=binding.cmd or ''
        if not command:find(prefix..'focus-',1,true) and not command:find(prefix..'menu-escape',1,true)
            and not command:find(prefix..'capture-key',1,true) then underlying[#underlying+1]=binding end
    end
    local active={}
    for _,binding in ipairs(M.effective(state,underlying)) do
        active[M.normalize(binding.key)]=binding.cmd:match('script%-binding [^ ]+/[^ ]+$') or binding.cmd
    end
    state.shortcut_hints={}
    for _,binding in ipairs(state.shortcuts or {}) do
        binding.active=active[binding.key]==binding.command
        if binding.active then
            local id=action_key(binding.action)
            state.shortcut_hints[id]=state.shortcut_hints[id] or binding.key
        end
    end
end

-- Check owned assignments and effective external bindings; temporary UI routes are excluded.
function M.conflict(state,id,key,bindings,resetting)
    key=M.normalize(key)
    if not key then return 'Invalid key combination' end
    if key=='none' then return nil end
    if key=='ESC' or key=='ENTER' then return 'Reserved for menu navigation' end
    local target
    for _,binding in ipairs(state.shortcuts or {}) do
        if binding.id==id then target=binding end
        if binding.id==id and not resetting and binding.key==key then return nil end
        if binding.id~=id and (resetting and binding.default or binding.key)==key then return 'Already used: '..binding.label end
    end
    local external={}
    local prefix='script-binding '..(state.script_name or 'mpvtube')..'/'
    for _,binding in ipairs(bindings or {}) do
        local command=binding.cmd or ''
        -- A batch reset validates defaults together, ignoring old assignments but retaining the ownership anchor.
        if (not resetting or binding.section~='mpvtube-shortcuts' or binding.key=='UNMAPPED')
            and not command:find(prefix..'focus-',1,true) and not command:find(prefix..'menu-escape',1,true) and not command:find(prefix..'capture-key',1,true) then
            external[#external+1]=binding
        end
    end
    for _,binding in ipairs(M.effective(state,external)) do
        if M.normalize(binding.key)==key then
            -- Restoring an owned default may reclaim the weak native fallback it originally replaced.
            if target and key==target.default and binding.is_weak and binding.cmd==target.default_native then return nil end
            return 'Already used: '..(binding.comment or binding.cmd)
        end
    end
end

-- Match MPV's precedence: strong bindings win, then the highest active section priority.
function M.active(bindings)
    local by_key={}
    for _,binding in ipairs(bindings or {}) do
        local previous=by_key[binding.key]
        if binding.key and (binding.priority or -1)>=0 and (not previous or
            previous.is_weak and not binding.is_weak or previous.is_weak==binding.is_weak and binding.priority>previous.priority) then
            by_key[binding.key]=binding
        end
    end
    local result={}
    for _,binding in pairs(by_key) do if binding.cmd~='ignore' then result[#result+1]=binding end end
    table.sort(result,function(a,b) return a.key<b.key end)
    return result
end

-- MPV reports priorities even for sections shadowed by exclusive ownership.
-- Filter below our section before resolving keys, including strong input.conf bindings.
function M.effective(state,bindings)
    local minimum=-1
    if state.shortcut_exclusive then
        for _,binding in ipairs(bindings or {}) do
            if binding.section=='mpvtube-shortcuts' then minimum=binding.priority or -1;break end
        end
    end
    local visible={}
    for _,binding in ipairs(bindings or {}) do
        if (binding.priority or -1)>=minimum then visible[#visible+1]=binding end
    end
    return M.active(visible)
end

-- One input section owns assignments; an exclusive capture section never executes a candidate key.
function M.new(state,options,view,execute,mouse_bindings)
    local mp,utils=require('mp'),require('mp.utils')
    local script=mp.get_script_name()
    state.script_name=script
    local path=options.keymap_path and options.keymap_path~='' and options.keymap_path or mp.command_native({'expand-path','~~/mpvtube-keys.json'})
    local function read()
        local file=io.open(path,'rb')
        if not file then return nil end
        local data=file:read('*a');file:close();return data
    end
    local original=read()
    local saved=original and utils.parse_json(original) or {version=1,keys={}}
    local writable=type(saved)=='table' and saved.version==1 and type(saved.keys)=='table'
    if not writable then saved={version=1,keys={}} end
    state.shortcuts,state.shortcut_labels={},{}
    local native={}
    for _,binding in ipairs(M.active(mp.get_property_native('input-bindings',{}))) do
        if binding.is_weak then native[M.normalize(binding.key)]=binding.cmd end
    end
    local function route(binding)
        mp.add_key_binding(nil,binding.id,binding.callback or function() execute(binding.action) end,
            {repeatable=binding.repeatable or false,complex=binding.complex or false})
        binding.command='script-binding '..script..'/'..binding.id
    end
    if options.keyboard then
        for _,binding in ipairs(M.defaults(options)) do
            binding.default=M.normalize(binding.key)
            binding.default_native=native[binding.default]
            binding.key=M.normalize(saved.keys[binding.id]) or binding.default
            binding.category=M.category(binding.action)
            route(binding)
            state.shortcuts[#state.shortcuts+1]=binding
            state.shortcut_labels[binding.id]=binding.label
        end
    end
    for _,binding in ipairs(mouse_bindings) do route(binding) end
    local pointer_rows={}
    for _,binding in ipairs(mouse_bindings) do pointer_rows[#pointer_rows+1]=binding.key..' '..binding.command end
    mp.commandv('define-section','mpvtube-pointer',table.concat(pointer_rows,'\n'),'force')
    local function apply()
        state.shortcut_exclusive=options.keyboard and options.shortcut_policy~='compatible'
        -- UNMAPPED runs after explicit keys and retains an entirely disabled keymap.
        -- ANY_UNICODE would swallow assigned letters before MPV checks them.
        local rows=state.shortcut_exclusive and {'UNMAPPED ignore'} or {}
        for _,binding in ipairs(state.shortcuts) do
            if binding.key~='none' then rows[#rows+1]=binding.key..' nonscalable '..binding.command end
        end
        mp.commandv('define-section','mpvtube-shortcuts',table.concat(rows,'\n'),options.shortcut_policy=='compatible' and 'default' or 'force')
        if #rows>0 then mp.commandv('enable-section','mpvtube-shortcuts',
            (state.shortcut_exclusive and 'exclusive+' or '')..'allow-hide-cursor+allow-vo-dragging') end
        -- Keyboard compatibility must never let native mouse bindings bypass UI safe areas.
        mp.commandv('enable-section','mpvtube-pointer','allow-hide-cursor+allow-vo-dragging')
        mp.enable_key_bindings('mpvtube-controls','allow-hide-cursor')
        if state.menu or state.focus then mp.commandv('enable-section','mpvtube-focus','allow-hide-cursor+allow-vo-dragging') end
        M.refresh(state,mp.get_property_native('input-bindings',{}))
        view.request_render()
    end
    local function cancel_capture()
        if state.key_capture then mp.commandv('disable-section','mpvtube-key-capture') end
        state.key_capture,state.key_capture_bindings=false,nil
    end
    local function selected()
        for _,binding in ipairs(state.shortcuts) do if binding.id==state.key_edit then return binding end end
    end
    -- Status belongs to the editor's fixed notice card, never to its selectable options.
    local function message(text,tone)
        state.keymap_message,state.keymap_tone=text,tone or 'info'
        view.request_render()
    end
    local function candidate(key)
        local binding=selected()
        if not binding then return end
        key=M.normalize(key)
        local error=M.conflict(state,binding.id,key,state.key_capture_bindings or mp.get_property_native('input-bindings',{}))
        message(error or 'Press Enter to save: '..M.display_key(key),error and 'error' or 'info')
        if not error then
            state.key_candidate=key;cancel_capture()
            if view.focus_menu_action then view.focus_menu_action('save') end
        else state.key_candidate=nil end
        view.request_render()
    end
    mp.add_key_binding(nil,'capture-key',function(event)
        if not state.key_capture or event.canceled or event.is_mouse or event.event~='down' and event.event~='press' then return end
        if event.key_name=='ESC' then cancel_capture();message('Cancelled')
        else candidate(event.key_name) end
    end,{complex=true})
    local capture={'ANY_UNICODE nonscalable script-binding '..script..'/capture-key','UNMAPPED nonscalable script-binding '..script..'/capture-key'}
    for _,binding in ipairs(mouse_bindings) do capture[#capture+1]=binding.key..' '..binding.command end
    -- Right-click dismissal retains its bounded mouse section above capture.
    mp.commandv('define-section','mpvtube-key-capture',table.concat(capture,'\n'),'force')

    -- Single edits and full resets share one atomic write; failures leave live assignments intact.
    local function persist(keys)
        if not writable or read()~=original then message('Keymap changed or unreadable; reopen MPV before saving','error');return end
        -- Empty untyped Lua tables become JSON arrays; keep the key dictionary an object.
        local data=utils.format_json({version=1,keys=next(keys) and keys or utils.parse_json('{}')})
        if not data then message('Invalid keymap data; current shortcuts retained','error');return end
        local suffix=os.tmpname();os.remove(suffix);suffix=suffix:gsub('.*[/\\]','')
        local temporary=path..'.'..suffix
        local file=io.open(temporary,'wb')
        local ok=file and file:write(data)
        if file then ok=file:close() and ok end
        if ok then
            ok=os.rename(temporary,path)
            if not ok and original then
                -- Windows does not replace an existing destination with rename; restore on failure.
                local backup=temporary..'.bak'
                if os.rename(path,backup) then
                    ok=os.rename(temporary,path)
                    if ok then os.remove(backup) else os.rename(backup,path) end
                end
            end
        end
        os.remove(temporary)
        if not ok then message('Cannot save keymap; check folder permissions','error');return end
        original,saved=data,{version=1,keys=keys}
        return true
    end
    local function save(binding)
        local error=M.conflict(state,binding.id,state.key_candidate,mp.get_property_native('input-bindings',{}))
        if error then message(error,'error');return end
        local keys={}
        for id,key in pairs(saved.keys) do keys[id]=key end
        keys[binding.id]=state.key_candidate
        if not persist(keys) then return end
        binding.key,state.key_candidate=keys[binding.id],nil
        message('Saved','success')
        apply()
        state.menu_scroll=0
        if view.focus_menu_action then view.focus_menu_action('capture') end
    end
    view.edit_shortcut=function(operation,id)
        local binding=selected()
        if operation=='confirm-reset' then
            cancel_capture();state.key_candidate,state.keymap_message,state.keymap_tone=nil,nil,nil
            view.open_menu('shortcut-reset')
        elseif operation=='reset-all' then
            local bindings=mp.get_property_native('input-bindings',{})
            for _,item in ipairs(state.shortcuts) do
                local error=M.conflict(state,item.id,item.default,bindings,true)
                if error then message(error,'error');return end
            end
            if not persist({}) then return end
            cancel_capture();state.key_edit,state.key_candidate=nil,nil
            for _,item in ipairs(state.shortcuts) do item.key=item.default end
            apply();view.open_menu('shortcuts');message('All shortcuts reset','success')
        elseif operation=='select' then
            cancel_capture();state.key_edit,state.key_candidate,state.keymap_message,state.keymap_tone=id,nil,nil,nil
            view.open_menu('binding')
            if view.focus_menu_action then view.focus_menu_action('capture') end
        elseif operation=='capture' and binding then
            state.key_capture_bindings=mp.get_property_native('input-bindings',{})
            state.key_capture,state.key_candidate=true,nil
            message('Press a key combination; Esc cancels')
            mp.commandv('enable-section','mpvtube-key-capture','exclusive+allow-hide-cursor+allow-vo-dragging')
            mp.enable_key_bindings('mpvtube-controls','allow-hide-cursor')
        elseif operation=='default' and binding then candidate(binding.default)
        elseif operation=='disable' and binding then candidate('none')
        elseif operation=='save' and binding and state.key_candidate then save(binding)
        elseif operation=='cancel' then cancel_capture();state.key_candidate=nil;message('Cancelled') end
        view.request_render()
    end
    view.cancel_key_capture=cancel_capture
    apply()
    return {shutdown=function()
        cancel_capture();mp.commandv('disable-section','mpvtube-shortcuts');mp.commandv('disable-section','mpvtube-pointer')
    end}
end
return M
