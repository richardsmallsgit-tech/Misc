-- these are the snippets madium has in it's editor.



for i = 1, 10 do
	-- code here
end





for key, value in pairs(tbl) do
	-- code here
end





for index, item in ipairs(list) do
	-- code here
end





while true do
	-- code here
	task.wait(0.1)
end





local function name()
	-- code here
end





if condition then
-- code here
else
	-- code here
end





local ok, err = pcall(function() end)
if not ok then
	warn(err)
end





-- ============
-- end of basic snippets
-- ============








-- roblox snippets
local Players = game:GetService("Players") -- get a service

-- local player and humanoid
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

-- connect to an event
event:Connect(function()
	-- code here
end)





-- every frame loop
local RunService = game:GetService("RunService")
local connection
connection = RunService.Heartbeat:Connect(function(dt)
	-- code here
end)
-- connection:Disconnect() stops it





-- run in the background
task.spawn(function()
	-- code here
end)





-- delays a function
task.delay(1, function()
	-- code here
end)





-- some gui animate shit
local TweenService = game:GetService("TweenService")
local tween = TweenService:Create(part, TweenInfo.new(1, Enum.EasingStyle.Quad), {
	Transparency = 1,
})
tween:Play()





-- create an instance
local part = Instance.new("Part")
part.Name = "Part"
part.Parent = workspace





-- Notify
game:GetService("StarterGui"):SetCore("SendNotification", {
	Title = "Placeholder",
	Text = "Hello!",
	Duration = 5,
})





-- loadstring loader
loadstring(game:HttpGet("https://raw.realnigg.yeah"))() -- not a real link, but a placeholder for the stupid.





-- run once
if getgenv().Loaded then
	return
end
getgenv().Loaded = true
-- code here





-- global whatever
getgenv().Enabled = true
while getgenv().Enabled do
	-- code here
	task.wait(0.1)
end
