local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NexusDataStore = require(ReplicatedStorage:WaitForChild("NexusAdminClient"):WaitForChild("NexusFeatureFlags"):WaitForChild("NexusDataStore")) :: any
local Types = require(script.Parent.Parent.Parent:WaitForChild("Types"))

local PersistentBans = {}
PersistentBans.__index = PersistentBans

local StaticInstance = nil

export type PersistentBans = {
    new: (Api: Types.NexusAdminApiServer) -> (PersistentBans),
    GetInstance: (Api: Types.NexusAdminApiServer) -> (PersistentBans),

    Initialized: boolean,
    InitializationStarted: boolean,
    Initialize: (self: PersistentBans) -> (),
    WasInitialized: (self: PersistentBans) -> (boolean),
    ResolveUserIds: (self: PersistentBans, Name: string) -> ({number}),
    BanId: (self: PersistentBans, UserId: number, Message: string?) -> (),
    UnbanId: (self: PersistentBans, UserId: number) -> (),
}



--[[
Creates a persistent bans object.
--]]
function PersistentBans.new(Api: Types.NexusAdminApiServer): PersistentBans
    --Create the object.
    local self = {
        InitializationStarted = false,
        Initialized = false,
        Api = Api,
        PlayerUpdateEvents = {},
    }
    setmetatable(self, PersistentBans)

    --Return the object.
    return (self :: any) :: PersistentBans
end

--[[
Returns a static instance of the persistent bans.
--]]
function PersistentBans.GetInstance(Api: Types.NexusAdminApiServer): PersistentBans
    if not StaticInstance then
        StaticInstance = PersistentBans.new(Api)
        StaticInstance:Initialize()
    end
    while not StaticInstance.Initialized do
        task.wait()
    end
    return StaticInstance
end

--[[
Initializes the bans.
--]]
function PersistentBans:Initialize(): ()
    if self.InitializationStarted then return end
    self.InitializationStarted = true

    --Get the DataStore.
    local Worked, ErrorMessage = pcall(function()
        self.BansDataStore = NexusDataStore:GetDataStore("NexusAdmin_Persistence", "PercistentBans")
    end)
    if not Worked then
        warn("Failed to get persistent bans because "..tostring(ErrorMessage))
        self.Initialized = true
        return
    end
    
    --Connect kicking players.
    Players.PlayerRemoving:Connect(function(Player: Player)
        if not self.PlayerUpdateEvents[Player] then return end
        self.PlayerUpdateEvents[Player]:Disconnect()
        self.PlayerUpdateEvents[Player] = nil
    end)
    Players.PlayerAdded:Connect(function(Player: Player)
        self:ConnectPlayer(Player)
    end)
    for _, Player in Players:GetPlayers() do
        self:ConnectPlayer(Player)
    end
    self.Initialized = true
end

--[[
Connects a player.
--]]
function PersistentBans:ConnectPlayer(Player: Player): ()
    if not self.BansDataStore then return end
    self.PlayerUpdateEvents[Player] = self.BansDataStore:OnUpdate(tostring(Player.UserId), function()
        self:KickPlayer(Player)
    end)
    self:KickPlayer(Player)
end

--[[
Kicks a player if they are banned.
--]]
function PersistentBans:KickPlayer(Player: Player): ()
    if not self.BansDataStore then return end
    task.spawn(function()
        --Return if the player is an admin.
        self.Api.Authorization:YieldForAdminLevel(Player)
        if self.Api.Authorization:IsPlayerAuthorized(Player, 0) then
            return
        end

        --Kick the player.
        local BanMessage = self.BansDataStore:Get(tostring(Player.UserId))
        if BanMessage == true then
            Player:Kick()
        elseif BanMessage then
            Player:Kick(BanMessage)
        end
    end)
end

--[[
Returns if the bans initialized correctly.
--]]
function PersistentBans:WasInitialized(): boolean
    return self.BansDataStore ~= nil
end

--[[
Attempts to resolve the user ids for the given name.
--]]
function PersistentBans:ResolveUserIds(Name: string): {number}
    --Add the ids from the players.
    local Ids = {}
    for _,Player in Players:GetPlayers() do
        if string.find(string.lower(Player.Name), string.lower(Name)) then
            table.insert(Ids, Player.UserId)
        end
    end

    --Add the user id from the name if no players match.
    if #Ids == 0 then
        if tonumber(Name) then
            table.insert(Ids, tonumber(Name))
        else
            pcall(function()
                table.insert(Ids, self.Players:GetUserIdFromNameAsync(Name))
            end)
        end
    end

    --Return the ids.
    return Ids
end

--[[
Bans a user id.
--]]
function PersistentBans:BanId(UserId: number, Message: string?): ()
    if not self.BansDataStore then return end
    self.BansDataStore:Set(tostring(UserId), Message or true)
end

--[[
Unbans a user id.
--]]
function PersistentBans:UnbanId(UserId)
    if not self.BansDataStore then return end
    self.BansDataStore:Set(tostring(UserId), nil)
end



return (PersistentBans :: any) :: PersistentBans
