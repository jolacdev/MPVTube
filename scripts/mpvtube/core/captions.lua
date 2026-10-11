-- Caption appearance menus use native subtitle properties, not a second text renderer.
local M = {}
local colors = {{"White","ffffff"},{"Yellow","ffff00"},{"Green","00ff00"},
    {"Cyan","00ffff"},{"Blue","0000ff"},{"Magenta","ff00ff"},{"Red","ff0000"},{"Black","000000"}}
local fonts = {{"Sans-serif","sans-serif"},{"Serif","serif"},{"Monospace","monospace"},
    {"Cursive","cursive"}}
M.titles = {captions="Options", ["caption-font"]="Font family", ["caption-color"]="Font color",
    ["caption-size"]="Font size", ["caption-background"]="Background color",
    ["caption-background-opacity"]="Background opacity", ["caption-edge"]="Character edge style",
    ["caption-opacity"]="Font opacity"}
local subtitle_properties = {{"sub-font","sans-serif"},{"sub-font-size",38},{"sub-color","#FFFFFFFF"},
    {"sub-back-color","#AF000000"},{"sub-border-style","outline-and-shadow"},
    {"sub-outline-size",1.65},{"sub-shadow-offset",0},{"sub-outline-color","#FF000000"},
    {"sub-ass-override","scale"}}

-- MPV colors use alpha first. Preserve opacity when changing hue, and hue when changing opacity.
function M.color(value)
    local hex = tostring(value or ""):match("^#(%x+)$")
    if hex and #hex == 8 then return hex:sub(3):lower(),tonumber(hex:sub(1,2),16)/255 end
    if hex and #hex == 6 then return hex:lower(),1 end
    local parts = {}
    for number in tostring(value or ""):gmatch("[%d.]+") do parts[#parts+1]=tonumber(number) end
    if #parts >= 3 then
        return string.format("%02x%02x%02x",math.floor(parts[1]*255+.5),
            math.floor(parts[2]*255+.5),math.floor(parts[3]*255+.5)),parts[4] or 1
    end
    return "ffffff",1
end

function M.rgba(rgb, opacity)
    return string.format("#%02X%s",math.floor(math.max(0,math.min(1,opacity))*255+.5),rgb:upper())
end

local function has_background_box(style) return style == "background-box" or style == "opaque-box" end
local function choice_label(choices,value)
    for _, choice in ipairs(choices) do if choice[2] == value then return choice[1] end end
    return tostring(value)
end
local function edge_style(style)
    if (style["sub-outline-size"] or 0) > 0 then return "Outline" end
    return not has_background_box(style["sub-border-style"]) and (style["sub-shadow-offset"] or 0) > 0 and "Drop shadow" or "None"
end

-- Rows reflect observed values, so input.conf and other scripts remain visible in the menu.
function M.rows(state,page)
    local style = state.caption_style or {}
    local rgb,opacity=M.color(style["sub-color"])
    local background,background_opacity=M.color(style["sub-back-color"])
    if not has_background_box(style["sub-border-style"]) then background_opacity=0 end
    local size=(style["sub-font-size"] or 38)/(state.caption_base_size or 38)*100
    local rows={}
    local function row(text,value,action,selected)
        rows[#rows+1]={label=text,value=value or "",action=action,selected=selected}
    end
    if page == "captions" then
        row("Font family",choice_label(fonts,style["sub-font"] or "sans-serif"),{page="caption-font"})
        row("Font color",choice_label(colors,rgb),{page="caption-color"})
        row("Font size",string.format("%.0f%%",size),{page="caption-size"})
        row("Background color",choice_label(colors,background),{page="caption-background"})
        row("Background opacity",string.format("%.0f%%",background_opacity*100),{page="caption-background-opacity"})
        row("Character edge style",edge_style(style),{page="caption-edge"})
        row("Font opacity",string.format("%.0f%%",opacity*100),{page="caption-opacity"})
        row("Reset",nil,{caption="reset"})
    else
        local key=page:match("^caption%-(.*)$")
        local choices,current
        if key == "font" then choices,current=fonts,style["sub-font"]
        elseif key == "color" then choices,current=colors,rgb
        elseif key == "background" then choices,current=colors,background
        elseif key == "edge" then choices,current={{"None","None"},{"Drop shadow","Drop shadow"},{"Outline","Outline"}},edge_style(style)
        elseif key == "size" then
            choices,current={},size
            for _, percent in ipairs({50,75,100,150,200,300,400}) do choices[#choices+1]={percent.."%",percent} end
        elseif key == "opacity" or key == "background-opacity" then
            choices,current={},(key == "opacity" and opacity or background_opacity)*100
            for _, percent in ipairs({0,25,50,75,100}) do choices[#choices+1]={percent.."%",percent} end
        end
        for _, choice in ipairs(choices or {}) do
            local selected=type(current)=="number" and math.abs(current-choice[2]) < .6 or current==choice[2]
            row(choice[1],nil,{caption=key,value=choice[2]},selected)
        end
    end
    return rows
end

function M.parent(page) return page == "captions" and "sub" or "captions" end

function M.new(state,request_render)
    local mp=require("mp")
    local original_style={}
    state.caption_style={}
    for _, field in ipairs(subtitle_properties) do
        local name,fallback=field[1],field[2]
        -- Observe native names; border aliases accept writes but can miss change notifications.
        original_style[name]=mp.get_property_native(name,fallback)
        state.caption_style[name]=original_style[name]
        mp.observe_property(name,"native",function(_,value)
            state.caption_style[name]=value == nil and fallback or value
            request_render()
        end)
    end
    state.caption_base_size=original_style["sub-font-size"]
    local function set_property(name,value)
        local ok,error=mp.set_property_native(name,value)
        if ok then
            -- Read back accepted values so rapid choices do not wait for an observer callback.
            state.caption_style[name]=mp.get_property_native(name)
            request_render()
        else mp.msg.warn("Caption option "..name..": "..tostring(error)) end
        return ok
    end
    local function apply(key,value)
        if key == "reset" then
            for _, field in ipairs(subtitle_properties) do set_property(field[1],original_style[field[1]]) end
            return
        end
        local style=state.caption_style
        -- Override authored text styles only after the user chooses a custom appearance.
        set_property("sub-ass-override","force")
        if key == "font" then set_property("sub-font",value)
        elseif key == "size" then set_property("sub-font-size",state.caption_base_size*value/100)
        elseif key == "color" or key == "opacity" then
            local rgb,alpha=M.color(style["sub-color"])
            set_property("sub-color",M.rgba(key == "color" and value or rgb,key == "opacity" and value/100 or alpha))
        elseif key == "background" or key == "background-opacity" then
            local rgb,alpha=M.color(style["sub-back-color"])
            if not has_background_box(style["sub-border-style"]) then alpha=0 end
            set_property("sub-back-color",M.rgba(key == "background" and value or rgb,key == "background-opacity" and value/100 or alpha))
            set_property("sub-border-style","background-box")
            set_property("sub-shadow-offset",4)
        elseif key == "edge" then
            set_property("sub-outline-size",value == "Outline" and 1.65 or 0)
            set_property("sub-outline-color","#FF000000")
            if value == "Drop shadow" then
                -- MPV uses one backing color for a box or a shadow; these modes are exclusive.
                set_property("sub-border-style","outline-and-shadow")
                set_property("sub-back-color","#BF000000")
                set_property("sub-shadow-offset",2)
            else set_property("sub-shadow-offset",has_background_box(style["sub-border-style"]) and 4 or 0) end
        end
    end
    return {apply=apply}
end

return M
