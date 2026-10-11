-- Shared CSS-style easing and interruptible numeric transitions; no MPV dependencies.
local clamp = require("core.model").clamp
local M = {duration={hover=0.2,volume=0.2,timeline=0.2,gear=0.1,toggle=0.2,track=0.08,expand=0.3,
    wave=0.25,menu=0.1,panel=0.25,tooltip=0.2,feedback=1,seek=1.2,seek_move=0.35,seek_fade=0.1}}
local curves = {modern={0.05,0,0,1},enter={0,0,0.2,1},leave={0.4,0,1,1},standard={0.4,0,0.2,1}}

-- CSS maps time through the curve's x coordinate, then reads its y coordinate.
function M.ease(progress, curve)
    progress=clamp(progress,0,1)
    local points=curves[curve]
    if not points or progress == 0 or progress == 1 then return progress end
    local function cubic(t,a,b) return 3*(1-t)^2*t*a+3*(1-t)*t*t*b+t^3 end
    local lo,hi=0,1
    for _=1,18 do
        local t=(lo+hi)/2
        if cubic(t,points[1],points[3]) < progress then lo=t else hi=t end
    end
    return cubic((lo+hi)/2,points[2],points[4])
end

local Animator = {}
Animator.__index=Animator
function M.new() return setmetatable({tracks={},now=0},Animator) end
function Animator:begin(now) self.now,self.active,self.used=now,false,{} end
local function sample(track,now)
    local progress=track.duration == 0 and 1 or clamp((now-track.start)/track.duration,0,1)
    return track.from+(track.target-track.from)*M.ease(progress,track.curve),progress < 1
end

-- Retarget from the displayed value, so reversals never jump or restart from an endpoint.
function Animator:value(key,target,kind,curve,initial)
    self.used[key]=true
    local track=self.tracks[key]
    if not track or track.target ~= target then
        local from=track and sample(track,self.now) or initial
        if from == nil then from=target end
        track={from=from,target=target,start=self.now,duration=M.duration[kind] or kind or 0,
            curve=curve or "modern"}
        self.tracks[key]=track
    end
    local value,running=sample(track,self.now)
    if running and track.from ~= target then self.active=true end
    return value
end

-- Disappearing rows/controls cannot leave an unbounded collection of animation tracks.
function Animator:finish()
    for key in pairs(self.tracks) do if not self.used[key] then self.tracks[key]=nil end end
    return self.active
end

-- YouTube's modern feedback grows/fades for 250 ms, holds, then shrinks/fades out.
function M.feedback(item,now)
    local age=now-item.start
    if item.kind == "seek" then
        item.opacity=M.ease(age/M.duration.seek_fade,"enter")*
            (1-M.ease((age-M.duration.seek+M.duration.seek_fade)/M.duration.seek_fade,"leave"))
        item.offset=16*(1-M.ease(age/M.duration.seek_move,"modern"))
        return age < M.duration.seek
    end
    local progress
    if age < 0.25 then progress=M.ease(age/0.25,"modern")
    elseif age < 0.75 then progress=1
    else progress=1-M.ease((age-0.75)/0.25,"modern") end
    item.opacity,item.scale=progress,1+0.33*progress
    return age < M.duration.feedback
end

return M
