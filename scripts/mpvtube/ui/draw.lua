-- Small ASS drawing layer with reusable rounded geometry and safe text rendering.
local model = require("core.model")
local icons = require("ui.icons")
local M = {metrics={inset=12,gap=12,compact_gap=8,control_height=40,control_bottom=8,
    hover_inset=4,hover_opacity=0.1,capsule_opacity=0.3,menu_bottom=62,
    menu_padding=8,menu_row=48,menu_header=57,safe_height=72,timeline_bottom=59}}
-- Sizes are CSS pixels; named roles share their font weights.
M.text_styles={body={14,400},timer={14,500},chapter={13.07,500},header={12,500},header_action={12,400},
    tooltip={12.98,500},title={20,700},speed={18,900},step={24,500},preset={12,500},
    hint={10,400},percentage={19.25,400},badge={6,700},seek={24,700},dialog_title={18,500},
    field_label={12,400},field_value={16,500},field_value_compact={14,500}}
local Canvas = {}
Canvas.__index = Canvas

-- ASS expects BGR color bytes and inverse alpha; callers use ordinary RGB/opacity.
local function color(rgb)
    return rgb:sub(5, 6) .. rgb:sub(3, 4) .. rgb:sub(1, 2)
end

function M.new(opacity, font, motion, state)
    return setmetatable({events={},opacity=opacity or 1,font=font or "Roboto",motion=motion,state=state or {}},Canvas)
end

function Canvas:animate(key,target,kind,curve,initial)
    return self.motion and self.motion:value(key,target,kind,curve,initial) or target
end

-- Layers share drawing/animation helpers while applying opacity, clipping and translation.
function Canvas:layer(opacity,clip,dx,dy)
    local layer=M.new(self.opacity*opacity,self.font,self.motion,self.state)
    layer.clip,layer.dx,layer.dy=clip or self.clip,(self.dx or 0)+(dx or 0),(self.dy or 0)+(dy or 0)
    return layer
end

function Canvas:style(rgb, opacity)
    local alpha = math.floor(255 * (1 - self.opacity * (opacity or 1)) + 0.5)
    local style=string.format("\\bord0\\shad0\\1c&H%s&\\alpha&H%02X&",color(rgb or "ffffff"),alpha)
    if self.clip then
        local area=self.clip
        style=style..string.format("\\clip(%.2f,%.2f,%.2f,%.2f)",area.x,area.y,area.x+area.w,area.y+area.h)
    end
    return style
end

function Canvas:path(x, y, path, rgb, opacity, size, rotation, stroke)
    x,y=x+(self.dx or 0),y+(self.dy or 0)
    local scale = (size or 24) / 24 * 100
    local style = self:style(rgb, opacity)
    if stroke then
        local alpha=math.floor(255*(1-self.opacity*(opacity or 1))+.5)
        style=style..string.format("\\bord%.2f\\1a&HFF&\\3c&H%s&\\3a&H%02X&",stroke,color(rgb or "ffffff"),alpha)
    end
    -- ASS rotates counterclockwise; use the icon center for CSS-style clockwise rotation.
    if rotation then style=style..string.format("\\org(%.2f,%.2f)\\frz%.2f",x+(size or 24)/2,y+(size or 24)/2,-rotation) end
    self.events[#self.events + 1] = string.format(
        "{\\an7\\pos(%.2f,%.2f)%s\\fscx%.2f\\fscy%.2f\\p1}%s{\\p0}",
        x, y, style, scale, scale, path)
end

-- Cubic curves approximate rounded corners without depending on an icon font.
function Canvas:rect(x, y, w, h, rgb, opacity, radius, stroke)
    if w <= 0 or h <= 0 then return end
    local r = math.min(radius or 0, w / 2, h / 2)
    local path
    if r == 0 then
        path = string.format("m 0 0 l %.2f 0 %.2f %.2f 0 %.2f", w, w, h, h)
    else
        local k = r * 0.55228475
        path = string.format("m %.2f 0 l %.2f 0 b %.2f 0 %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f %.2f %.2f %.2f %.2f l %.2f %.2f b %.2f %.2f 0 %.2f 0 %.2f l 0 %.2f b 0 %.2f %.2f 0 %.2f 0",
            r, w-r, w-r+k, w, r-k, w, r, w, h-r, w, h-r+k, w-r+k, h, w-r, h,
            r, h, r-k, h, h-r+k, h-r, r, r-k, r-k, r)
    end
    self:path(x, y, path, rgb, opacity,nil,nil,stroke)
end

function Canvas:circle(x, y, r, rgb, opacity)
    self:rect(x-r, y-r, r*2, r*2, rgb, opacity, r)
end

-- One hover predicate, spacing and easing path serves buttons, capsules and menu rows.
function Canvas:hover(area,active)
    if active == nil then
        active=area.action and area.enabled ~= false and
            (self.state.hover == area.id or self.state.focus==area.id and self.state.focus_group==area.group or area.index and self.state.menu_focus == area.index)
    end
    if self.state.focus==area.id and self.state.focus_group==area.group and area.action then
        self:rect(area.x+2,area.y+2,area.w-4,area.h-4,"ffffff",.85,area.hover_radius or 16,1)
    end
    local target=active and (area.id == "play" and self.state.pressed == area.id and 2 or 1) or 0
    local opacity=self:animate("hover:"..(area.group or "bar")..":"..area.id,target,"hover","modern",0)
    local inset=area.hover_inset or M.metrics.hover_inset
    if opacity > 0 then
        local w,h=area.hover_width or area.w-2*inset,area.hover_height or area.h-2*inset
        self:rect(area.x+(area.w-w)/2,area.y+(area.h-h)/2,w,h,"ffffff",
            M.metrics.hover_opacity*opacity,area.hover_radius or 16)
    end
end

-- Both menu switches and autoplay move their knobs through the same transition helper.
function Canvas:toggle(key,cx,cy,enabled,autoplay)
    local progress=self:animate("toggle:"..key,enabled and 1 or 0,"toggle")
    if autoplay then
        local knob=cx-6+13*progress
        local track=self:animate("toggle-track:"..key,enabled and 1 or 0,"track","leave")
        self:rect(cx-15,cy-9,30,18,"ffffff",0.1+0.9*track,9)
        local shade=math.floor(255*(1-progress)+0.5)
        self:circle(knob,cy,7,string.format("%02x%02x%02x",shade,shade,shade))
        self:icon(enabled and "play" or "pause",knob,cy,9,enabled and "ffffff" or "000000")
    else
        self:rect(cx-18,cy-10,36,20,"ffffff",0.18+0.22*progress,10)
        self:circle(cx-8+16*progress,cy,8,"ffffff",0.65+0.35*progress)
    end
end

-- Volume waves scale around their reference pivots instead of swapping whole icons.
function Canvas:volume_icon(name,cx,cy,size)
    local small=self:animate("volume-small",name ~= "muted" and 1 or 0,"wave","linear")
    local large=self:animate("volume-large",name == "volume" and 1 or 0,"wave","linear")
    if name == "muted" then self:icon(name,cx,cy,size); return end
    self:icon("volume_speaker",cx,cy,size)
    for _,wave in ipairs({{name="volume_small",pivot=18,scale=small},{name="volume_large",pivot=22,scale=large}}) do
        if wave.scale > 0 then
            local x=cx-size/2+wave.pivot*size/24*(1-wave.scale)
            self:path(x,cy-size/2+size/2*(1-wave.scale),icons[wave.name],"ffffff",1,size*wave.scale)
        end
    end
end

function Canvas:icon(name, cx, cy, size, rgb, opacity, rotation)
    local path = icons[name]
    if path then self:path(cx-size/2, cy-size/2, path, rgb, opacity, size,rotation) end
end

-- Reset text scale after vector paths and escape metadata before emitting an ASS event.
function Canvas:text(x, y, text, size, rgb, align, opacity, weight)
    x,y=x+(self.dx or 0),y+(self.dy or 0)
    -- ASS sizes include Win ascent/descent; CSS sizes use em units. Values come from the font tables.
    local font_scale=self.font == "Roboto" and 2701/2048 or self.font == "Arial" and 2288/2048 or 1
    weight=type(weight) == "number" and weight or weight and 700 or 400
    self.events[#self.events + 1] = string.format(
        "{\\an%d\\pos(%.2f,%.2f)%s\\fn%s\\fs%.2f\\b%d\\i0\\fsp0\\fscx100\\fscy100}%s",
        align or 4, x, y, self:style(rgb, opacity), self.font, (size or 14)*font_scale,
        weight, model.escape(text))
end

function Canvas:label(role,x,y,text,rgb,align,opacity)
    local style=M.text_styles[role]
    self:text(x,y,text,style[1],rgb,align,opacity,style[2])
end

-- Feedback and tooltips share a measured, bounded text card; clipping is a final safety net.
function Canvas:badge(role,cx,cy,text,max_width,height,padding,radius)
    height,padding=height or 45,padding or 20
    local style=M.text_styles[role]
    local available=math.max(1,max_width-2*padding)
    local label=model.fit(text,available,style[1])
    local measure=self.state.measure_text or model.text_width
    local text_width=measure(label,style[1],style[2])
    if text_width>available then
        label=model.fit(label,model.text_width(label,style[1])*available/text_width-style[1],style[1])
        text_width=measure(label,style[1],style[2])
    end
    local width=math.min(max_width,math.ceil(text_width)+2*padding)
    if self.state.w then cx=model.clamp(cx,width/2+M.metrics.inset,self.state.w-width/2-M.metrics.inset) end
    self:rect(cx-width/2,cy-height/2,width,height,"000000",.6,radius or 3)
    local layer=self:layer(1,{x=cx-width/2+padding,y=cy-height/2,w=width-2*padding,h=height})
    layer:label(role,cx,cy,label,"ffffff",5)
    self.events[#self.events+1]=layer:finish()
    return {x=cx-width/2,y=cy-height/2,w=width,h=height,text=label}
end

-- A short stack of strips creates a transparent black title scrim.
function Canvas:title_scrim(width)
    local height = 92
    local step = 4
    for offset = 0, height-step, step do
        local opacity = (1-offset/height)^2 * 0.52
        self:rect(0,offset,width,step,"000000",opacity)
    end
end

function Canvas:finish() return table.concat(self.events, "\n") end

return M
