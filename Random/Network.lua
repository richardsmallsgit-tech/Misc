-- World of Stands Network Module



local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local IsServer = RunService:IsServer()
local Context = ReplicatedStorage:FindFirstChild("Context")
local ContextValue = (Context and Context.Value) or "Main"
local Network = {}
local eventHandlers = {}
local functionHandlers = {}
local requestCounter = 0
local trafficLog = nil
local ReferenceTypes = {
	Character = {},
	CharacterPart = {},
}
local ObjectLookup = {
	Character = {},
	CharacterPart = {},
}
local function Spawn(fn, ...)
	task.spawn(fn, ...)
end
local function ToByteArgs(n)
	if n > 255 then
		return math.floor(n / 256), n % 256
	end
	return n
end
local function ToByteString(n)
	return string.char(ToByteArgs(n))
end
local function logTraffic(isOutgoing, player, name, ...)
	if trafficLog then
		table.insert(trafficLog, { isOutgoing, player, name, ... })
	end
end
local Communication = ReplicatedStorage:FindFirstChild("Communication")
if not Communication then
	if IsServer then
		Communication = Instance.new("Folder")
		Communication.Name = "Communication"
		Communication.Parent = ReplicatedStorage
	else
		Communication = ReplicatedStorage:WaitForChild("Communication")
	end
end
local EventsFolder = Communication:FindFirstChild("Events")
if not EventsFolder then
	if IsServer then
		EventsFolder = Instance.new("Folder")
		EventsFolder.Name = "Events"
		EventsFolder.Parent = Communication
	else
		EventsFolder = Communication:WaitForChild("Events")
	end
end
local FunctionsFolder = Communication:FindFirstChild("Functions")
if not FunctionsFolder then
	if IsServer then
		FunctionsFolder = Instance.new("Folder")
		FunctionsFolder.Name = "Functions"
		FunctionsFolder.Parent = Communication
	else
		FunctionsFolder = Communication:WaitForChild("Functions")
	end
end
local function AddToQueue(handler, action, warnOnYield)
	if handler.Remote then
		return action()
	end
	if not handler.Queue then
		handler.Queue = {}
	end
	table.insert(handler.Queue, action)
	if warnOnYield then
		task.delay(5, function()
			if not handler.Remote then
				warn(
					debug.traceback(
						("Infinite yield possible on '%s:WaitForChild(\"%s\")'"):format(
							handler.Folder:GetFullName(),
							handler.Name
						)
					)
				)
			end
		end)
	end
end
local function GetEventHandler(name, unreliable)
	local handler = eventHandlers[name]
	if handler then
		return handler
	end
	handler = { Name = name, Folder = EventsFolder }
	eventHandlers[name] = handler
	if IsServer then
		local remote
		if unreliable == true then
			remote = Instance.new("UnreliableRemoteEvent")
		else
			remote = Instance.new("RemoteEvent")
		end
		remote.Name = name
		remote.Parent = EventsFolder
		handler.Remote = remote
		remote.Name = ""
	else
		local remote = EventsFolder:FindFirstChild(name)
		if remote then
			handler.Remote = remote
			remote.Name = ""
		else
			handler.Queue = {}
			local connection
			connection = EventsFolder.ChildAdded:Connect(function(child)
				if child.Name ~= name then
					return
				end
				if connection then
					connection:Disconnect()
					connection = nil
				end
				handler.Remote = child
				child.Name = ""
				local queue = handler.Queue
				handler.Queue = nil
				if queue then
					for _, queued in ipairs(queue) do
						Spawn(queued)
					end
				end
			end)
		end
	end
	return handler
end
local function GetFunctionHandler(name)
	local handler = functionHandlers[name]
	if handler then
		return handler
	end
	handler = { Name = name, Folder = FunctionsFolder }
	functionHandlers[name] = handler
	if IsServer then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = FunctionsFolder
		local response = Instance.new("RemoteEvent")
		response.Name = "Response"
		response.Parent = remote
		handler.Remote = remote
		handler.ResponseRemote = response
		remote.Name = ""
	else
		Spawn(function()
			handler.Queue = handler.Queue or {}
			local remote = handler.Folder:WaitForChild(name)
			local response = remote:WaitForChild("Response")
			handler.Remote = remote
			handler.ResponseRemote = response
			remote.Name = ""
			local queue = handler.Queue
			handler.Queue = nil
			if queue then
				for _, queued in ipairs(queue) do
					Spawn(queued)
				end
			end
		end)
	end
	return handler
end
local function checkParams(name, paramTypes)
	local validators = {}
	for _, types in ipairs(paramTypes) do
		if typeof(types) == "string" then
			local validator = { _string = types }
			for token in string.gmatch(types, "[^%s]+") do
				validator[token] = true
			end
			table.insert(validators, validator)
		end
	end
	return function(callback)
		return function(...)
			local args = table.pack(...)
			if #validators > 0 and args.n < #validators then
				warn(
					("[Network] Invalid number of parameters to %s (%d expected, got %d)"):format(
						name,
						#validators,
						args.n
					)
				)
			end
			for i = 1, math.min(#validators, args.n) do
				local validator = validators[i]
				if not validator[typeof(args[i])] and not validator.any then
					warn(
						("[Network] Invalid parameter %d to %s (%s expected, got %s)"):format(
							i,
							name,
							validator._string,
							typeof(args[i])
						)
					)
				end
			end
			return callback(table.unpack(args, 1, args.n))
		end
	end
end
local function combineFn(handler, callback, middleware)
	if typeof(middleware) == "function" then
		local inner = callback
		callback = function(...)
			return middleware(inner, ...)
		end
	elseif typeof(middleware) == "table" then
		local middlewareFn = nil
		for _, value in ipairs(middleware) do
			if typeof(value) == "function" then
				middlewareFn = value
				break
			end
		end
		local typeList = middleware.MatchParams
		if typeList == nil then
			local hasStrings = false
			for _, value in ipairs(middleware) do
				if typeof(value) == "string" then
					hasStrings = true
					break
				end
			end
			if hasStrings then
				typeList = middleware
			end
		end
		if typeList then
			callback = checkParams(handler.Name, typeList)(callback)
		end
		if middlewareFn then
			local inner = callback
			callback = function(...)
				return middlewareFn(inner, ...)
			end
		end
	end
	return callback
end
local function BindEvent(_, name, callback, middleware)
	local handler = GetEventHandler(name)
	if not handler then
		error(("Tried to bind callback to non-existing RemoteEvent %q"):format(name))
	end
	callback = combineFn(handler, callback, middleware)
	if IsServer then
		handler.Remote.OnServerEvent:Connect(callback)
	else
		if handler.Remote then
			handler.Remote.OnClientEvent:Connect(callback)
		else
			AddToQueue(handler, function()
				handler.Remote.OnClientEvent:Connect(callback)
			end)
		end
	end
end
Network.BindEvent = BindEvent
local function BindEvents(_, events, middleware)
	if typeof(events) == "table" then
		for name, callback in pairs(events) do
			BindEvent(nil, name, callback, middleware)
		end
	end
end
Network.BindEvents = BindEvents
local function BindFunction(_, name, callback, middleware)
	assert(IsServer, "BindFunction can only be used on the server")
	local handler = GetFunctionHandler(name)
	if not handler then
		error(("Tried to bind callback to non-existing RemoteFunction %q"):format(name))
	end
	if handler.IsSet then
		error(("Tried to bind multiple callbacks to the same RemoteFunction (%s)"):format(handler.Remote:GetFullName()))
	end
	handler.IsSet = true
	callback = combineFn(handler, callback, middleware)
	handler.Remote.OnServerEvent:Connect(function(player, requestId, ...)
		local responded = false
		local function respond(...)
			if responded then
				return
			end
			responded = true
			handler.ResponseRemote:FireClient(player, requestId, true, ...)
		end
		task.spawn(function(...)
			local results = table.pack(pcall(callback, player, respond, ...))
			if responded then
				return
			end
			responded = true
			if results[1] then
				handler.ResponseRemote:FireClient(player, requestId, true, table.unpack(results, 2, results.n))
			else
				warn(("[Network] Error in RemoteFunction '%s': %s"):format(name, tostring(results[2])))
				handler.ResponseRemote:FireClient(player, requestId, false, results[2])
			end
		end, ...)
	end)
end
Network.BindFunction = BindFunction
local function BindFunctions(_, functions, middleware)
	assert(IsServer, "BindFunctions can only be used on the server")
	if typeof(functions) == "table" then
		for name, callback in pairs(functions) do
			BindFunction(nil, name, callback, middleware)
		end
	end
end
Network.BindFunctions = BindFunctions
local function AddReference(_, reference, refType, ...)
	assert(ReferenceTypes[refType], "Invalid Reference Type")
	local data = {
		Type = refType,
		Reference = reference,
		Objects = { ... },
		Aliases = {},
	}
	ReferenceTypes[refType][reference] = data
	local lookup = ObjectLookup[refType]
	for _, obj in ipairs(data.Objects) do
		if not lookup[obj] then
			lookup[obj] = {}
		end
		lookup[obj].__Data = data
	end
end
Network.AddReference = AddReference
local function AddReferenceAlias(_, reference, refType, ...)
	assert(ReferenceTypes[refType], "Invalid Reference Type")
	local data = ReferenceTypes[refType][reference]
	if not data then
		warn("Tried to add an alias to a non-existing reference")
		return
	end
	local aliases = { ... }
	local lookup = ObjectLookup[refType]
	for _, alias in ipairs(aliases) do
		table.insert(data.Aliases, alias)
		if not lookup[alias] then
			lookup[alias] = {}
		end
		lookup[alias].__Data = data
	end
end
Network.AddReferenceAlias = AddReferenceAlias
local function RemoveReference(_, reference, refType)
	assert(ReferenceTypes[refType], "Invalid Reference Type")
	local data = ReferenceTypes[refType][reference]
	if not data then
		warn("Tried to remove a non-existing reference")
		return
	end
	local lookup = ObjectLookup[refType]
	local function unlink(obj)
		local mapping = lookup[obj]
		if not mapping then
			return
		end
		if mapping.__Data == data then
			mapping.__Data = nil
		end
		if next(mapping) == nil then
			lookup[obj] = nil
		end
	end
	for _, obj in ipairs(data.Objects) do
		unlink(obj)
	end
	for _, alias in ipairs(data.Aliases) do
		unlink(alias)
	end
	ReferenceTypes[refType][reference] = nil
end
Network.RemoveReference = RemoveReference
local function GetObject(_, reference, refType)
	assert(ReferenceTypes[refType], "Invalid Reference Type")
	local data = ReferenceTypes[refType][reference]
	if not data then
		return nil
	end
	return table.unpack(data.Objects)
end
Network.GetObject = GetObject
local function GetReference(_, ...)
	local args = { ... }
	local refType = table.remove(args)
	assert(ReferenceTypes[refType], "Invalid Reference Type")
	local lookup = ObjectLookup[refType]
	for _, obj in ipairs(args) do
		local mapping = lookup[obj]
		if mapping and mapping.__Data then
			return mapping.__Data.Reference
		end
	end
	return nil
end
Network.GetReference = GetReference
local function GetPlayers()
	return Players:GetPlayers()
end
Network.GetPlayers = GetPlayers
local function FireClient(_, player, name, ...)
	local handler = GetEventHandler(name)
	if not handler then
		error(("'%s' is not a valid RemoteEvent"):format(name))
	end
	logTraffic(true, player, name, ...)
	return handler.Remote:FireClient(player, ...)
end
Network.FireClient = FireClient
local function FireClientUnreliable(_, player, name, ...)
	local handler = GetEventHandler(name, true)
	if not handler then
		error(("'%s' is not a valid RemoteEvent"):format(name))
	end
	logTraffic(true, player, name, ...)
	return handler.Remote:FireClient(player, ...)
end
Network.FireClientUnreliable = FireClientUnreliable
local function FireAllClients(_, name, ...)
	local handler = GetEventHandler(name)
	if not handler then
		error(("'%s' is not a valid RemoteEvent"):format(name))
	end
	for _, player in ipairs(Players:GetPlayers()) do
		logTraffic(true, player, name, ...)
		handler.Remote:FireClient(player, ...)
	end
end
Network.FireAllClients = FireAllClients
local function FireAllClientsUnreliable(_, name, ...)
	local handler = GetEventHandler(name, true)
	if not handler then
		error(("'%s' is not a valid RemoteEvent"):format(name))
	end
	for _, player in ipairs(Players:GetPlayers()) do
		logTraffic(true, player, name, ...)
		handler.Remote:FireClient(player, ...)
	end
end
Network.FireAllClientsUnreliable = FireAllClientsUnreliable
local function FireOtherClients(_, exceptPlayer, name, ...)
	local handler = GetEventHandler(name)
	if not handler then
		error(("'%s' is not a valid RemoteEvent"):format(name))
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= exceptPlayer then
			logTraffic(true, player, name, ...)
			handler.Remote:FireClient(player, ...)
		end
	end
end
Network.FireOtherClients = FireOtherClients
local function FireOtherClientsWithinDistance(_, exceptPlayer, name, distance, ...)
	local handler = GetEventHandler(name, true)
	if not handler then
		error(("'%s' is not a valid RemoteEvent"):format(name))
	end
	local character = exceptPlayer.Character
	local sourcePosition = character and character.PrimaryPart and character.PrimaryPart.Position
	if not sourcePosition then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= exceptPlayer then
			local targetCharacter = player.Character
			local root = targetCharacter and targetCharacter.PrimaryPart
			if root and (root.Position - sourcePosition).Magnitude <= distance then
				logTraffic(true, player, name, ...)
				handler.Remote:FireClient(player, ...)
			end
		end
	end
end
Network.FireOtherClientsWithinDistance = FireOtherClientsWithinDistance
local function FireAllClientsWithinDistance(_, name, distance, sourcePosition, ...)
	if ContextValue == "PVP" then
		return FireAllClients(nil, name, ...)
	end
	local handler = GetEventHandler(name, true)
	if not handler then
		error(("'%s' is not a valid RemoteEvent"):format(name))
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character.PrimaryPart
		if root and (root.Position - sourcePosition).Magnitude <= distance then
			logTraffic(true, player, name, ...)
			handler.Remote:FireClient(player, ...)
		end
	end
end
Network.FireAllClientsWithinDistance = FireAllClientsWithinDistance
local function FireServer(_, name, ...)
	local handler = GetEventHandler(name)
	if not handler then
		error(("'%s' is not a valid RemoteEvent"):format(name))
	end
	if handler.Remote then
		logTraffic(false, Players.LocalPlayer, name, ...)
		handler.Remote:FireServer(...)
	else
		local args = table.pack(...)
		AddToQueue(handler, function()
			handler.Remote:FireServer(table.unpack(args, 1, args.n))
		end, true)
	end
end
Network.FireServer = FireServer
local function GetResponse(requestId, event)
	while true do
		local results = table.pack(event:Wait())
		if results[1] == requestId then
			if results[2] then
				return table.unpack(results, 3, results.n)
			end
			error(("[Network] RemoteFunction request failed: %s"):format(tostring(results[3])), 2)
		end
	end
end
local function InvokeServer(_, name, ...)
	local handler = GetFunctionHandler(name)
	if not handler then
		error(("'%s' is not a valid RemoteFunction"):format(name))
	end
	if not handler.Remote then
		local ready = Instance.new("BindableEvent")
		AddToQueue(handler, function()
			ready:Fire()
		end, true)
		ready.Event:Wait()
		ready:Destroy()
	end
	local requestId = ToByteString(requestCounter)
	requestCounter = (requestCounter + 1) % 65536
	handler.Remote:FireServer(requestId, ...)
	return GetResponse(requestId, handler.ResponseRemote.OnClientEvent)
end
Network.InvokeServer = InvokeServer
local function LogTraffic(_, duration)
	if not IsServer then
		warn("LogTraffic is server only")
		return
	end
	warn("Logging Network Traffic...")
	local startedAt = os.clock()
	local log = {}
	trafficLog = log
	task.delay(duration or 10, function()
		if trafficLog ~= log then
			return
		end
		trafficLog = nil
		local elapsed = math.max(os.clock() - startedAt, 0.001)
		local aggregated = {}
		for _, entry in ipairs(log) do
			local isOutgoing, player, name = entry[1], entry[2], entry[3]
			if typeof(player) == "Instance" and player:IsA("Player") then
				local perPlayer = aggregated[player]
				if not perPlayer then
					perPlayer = {}
					aggregated[player] = perPlayer
				end
				local perRemote = perPlayer[name]
				if not perRemote then
					perRemote = { dataIn = {}, dataOut = {}, total = 0 }
					perPlayer[name] = perRemote
				end
				perRemote.total += 1
				table.insert(isOutgoing and perRemote.dataOut or perRemote.dataIn, entry)
			end
		end
		for player, perPlayer in pairs(aggregated) do
			local total = 0
			for _, perRemote in pairs(perPlayer) do
				total += perRemote.total
			end
			warn(("Player '%s', total traffic: %d"):format(player.Name, total))
			for name, perRemote in pairs(perPlayer) do
				if #perRemote.dataIn > 0 then
					warn(
						("   %s %s: %d (%.2f/s)"):format(
							"Incoming",
							name,
							#perRemote.dataIn,
							#perRemote.dataIn / elapsed
						)
					)
				end
				if #perRemote.dataOut > 0 then
					warn(
						("   %s %s: %d (%.2f/s)"):format(
							"Outgoing",
							name,
							#perRemote.dataOut,
							#perRemote.dataOut / elapsed
						)
					)
				end
			end
		end
	end)
end
Network.LogTraffic = LogTraffic
if not IsServer then
	for _, child in ipairs(EventsFolder:GetChildren()) do
		if child.Name ~= "" then
			GetEventHandler(child.Name)
		end
	end
	for _, child in ipairs(FunctionsFolder:GetChildren()) do
		if child.Name ~= "" then
			GetFunctionHandler(child.Name)
		end
	end
end
return Network
