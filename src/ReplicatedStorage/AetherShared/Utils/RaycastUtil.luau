--!strict
-- AetherShared/Utils/RaycastUtil
-- Named cache for RaycastParams. Register once, reuse everywhere.
-- Does NOT wrap workspace:Raycast(). Callers use the native API with
-- the RaycastParams object returned by Get().

local Logger = require(game.ReplicatedStorage.AetherShared.Utils.Logger)

local TAG = "RaycastUtil"

local RaycastUtil = {}

local cache: { [string]: RaycastParams } = {}

local VALID_PROPERTIES = {
    FilterType = true,
    FilterDescendantsInstances = true,
    IgnoreWater = true,
    CollisionGroup = true,
    RespectCanCollide = true,
    BruteForceAllSlow = true,
}

local function validateConfig(config: { [string]: any })
    for key in config do
        if not VALID_PROPERTIES[key] then
            Logger:Fatal(TAG, ("Unknown RaycastParams property '%s'"):format(tostring(key)))
        end
    end
end

--- Registers a new named RaycastParams. Errors if the name already exists.
function RaycastUtil.Register(name: string, config: { [string]: any }?)
    if type(name) ~= "string" or name == "" then
        Logger:Fatal(TAG, "Register: name must be a non-empty string")
    end

    if cache[name] ~= nil then
        Logger:Fatal(TAG, ("Register: '%s' is already registered. Use Update() to modify it."):format(name))
    end

    local resolvedConfig: { [string]: any } = config or {}
    validateConfig(resolvedConfig)

    local params = RaycastParams.new()
    for key, value in resolvedConfig do
        (params :: any)[key] = value
    end

    cache[name] = params
end

--- Mutates the existing RaycastParams in place. Unspecified fields are left untouched.
function RaycastUtil.Update(name: string, config: { [string]: any })
    local params = cache[name]
    if params == nil then
        Logger:Fatal(TAG, ("Update: '%s' is not registered."):format(name))
        return
    end

    validateConfig(config)

    for key, value in config do
        (params :: any)[key] = value
    end
end

--- Returns the cached RaycastParams object (same instance every call).
function RaycastUtil.Get(name: string): RaycastParams
    local params = cache[name]
    if params == nil then
        Logger:Fatal(TAG, ("Get: '%s' is not registered."):format(name))
    end
    return params :: RaycastParams
end

--- Removes a named RaycastParams from the cache.
function RaycastUtil.Remove(name: string)
    cache[name] = nil
end

--- Returns true if a name is currently registered.
function RaycastUtil.Exists(name: string): boolean
    return cache[name] ~= nil
end

return RaycastUtil
