local LogService = game:GetService("LogService")

local Logger = {}

local COLUMN = {
	time = 12,
	level = 6,
	category = 20,
}

Logger.DebugEnabled = false

local HISTORY_LIMIT = 1000

local profiles = {}
local history = {}

local sequence = 0

local EMITTERS = {
	DEBUG = print,
	INFO = print,
	WARN = warn,
	ERROR = warn,
	FATAL = warn,
}

local LEVELS = {
	DEBUG = true,
	INFO = true,
	WARN = true,
	ERROR = true,
	FATAL = true,
}

local function getTime()
	return DateTime.now():FormatLocalTime("HH:mm:ss", "en-us")
end

local function getTimestamp()
	return DateTime.now().UnixTimestampMillis
end

local function rpad(str, len)
	str = tostring(str)

	if #str >= len then
		return string.sub(str, 1, len)
	end

	return str .. string.rep(" ", len - #str)
end

local function center(str, len)
	str = tostring(str)

	if #str >= len then
		return string.sub(str, 1, len)
	end

	local left = math.floor((len - #str) / 2)
	local right = len - #str - left

	return string.rep(" ", left)
		.. str
		.. string.rep(" ", right)
end

local function formatValue(value)
	local t = typeof(value)

	if value == nil then
		return "nil"
	elseif t == "table" then
		return "[table]"
	elseif t == "function" then
		return "[function]"
	end

	return tostring(value)
end

local function formatMessage(...)
	local args = table.pack(...)
	local parts = table.create(args.n)

	for i = 1, args.n do
		parts[i] = formatValue(args[i])
	end

	return table.concat(parts, " | ")
end

local function buildOutput(entry)
	local time = rpad(entry.time, COLUMN.time)
	local level = rpad(entry.level, COLUMN.level)
	local category = center(entry.category, COLUMN.category)

	return string.format(
		"[%s][%s][%s] %s",
		time,
		level,
		category,
		entry.message
	)
end

local function store(entry)
	sequence += 1

	entry.id = sequence

	table.insert(history, entry)

	if #history > HISTORY_LIMIT then
		table.remove(history, 1)
	end
end

local function createEntry(level, category, ...)
	return {
		id = 0,

		timestamp = getTimestamp(),
		time = getTime(),

		level = level,
		category = tostring(category),

		message = formatMessage(...),
	}
end

local function emit(entry)
	local emitter = EMITTERS[entry.level]

	if emitter then
		emitter(buildOutput(entry))
	end
end

local function log(level, category, ...)
	local entry = createEntry(level, category, ...)

	-- History always receives the log.
	store(entry)

	-- DEBUG visibility is controlled separately.
	if level == "DEBUG" and not Logger.DebugEnabled then
		return entry
	end

	emit(entry)

	return entry
end

function Logger:SetDebug(enabled: boolean)
	self.DebugEnabled = enabled
end

function Logger:IsDebugEnabled()
	return self.DebugEnabled
end

function Logger:Debug(category: string, ...)
	return log("DEBUG", category, ...)
end

function Logger:Info(category: string, ...)
	return log("INFO", category, ...)
end

function Logger:Warn(category: string, ...)
	return log("WARN", category, ...)
end

function Logger:Error(category: string, ...)
	return log("ERROR", category, ...)
end

function Logger:Fatal(category: string, ...)
	local entry = createEntry("FATAL", category, ...)

	store(entry)
	emit(entry)

	error(buildOutput(entry), 2)
end

function Logger:Banner(title: string)
	local width = math.max(#title + 8, 38)
	local border = string.rep("═", width)

	local padding = math.floor((width - #title) / 2)
	local centered = string.rep(" ", padding) .. title

	print(border)
	print(centered)
	print(border)
end

function Logger:Begin(name: string)
	profiles[name] = os.clock()
end

function Logger:End(name: string)
	local start = profiles[name]

	if not start then
		return
	end

	profiles[name] = nil

	self:Info(
		"PROFILE",
		name,
		string.format("(%.4f sec)", os.clock() - start)
	)
end

function Logger:TimeAsync(category: string, fn)
	local start = os.clock()

	task.spawn(function()
		local ok, err = pcall(fn)
		local duration = os.clock() - start

		if ok then
			Logger:Info(
				category,
				string.format("done (%.4f sec)", duration)
			)
		else
			Logger:Error(
				category,
				string.format(
					"failed (%.4f sec): %s",
					duration,
					err
				)
			)
		end
	end)
end

function Logger:GetHistory(opts)
	opts = opts or {}

	local results = {}

	for _, entry in ipairs(history) do
		if opts.level then
			if not LEVELS[opts.level] then
				error(
					"Invalid log level: " .. tostring(opts.level),
					2
				)
			end

			if entry.level ~= opts.level then
				continue
			end
		end

		if opts.category then
			local category = entry.category:lower()
			local filter = tostring(opts.category):lower()

			if not category:find(filter, 1, true) then
				continue
			end
		end

		table.insert(results, entry)
	end

	if opts.limit and #results > opts.limit then
		local startIndex = #results - opts.limit + 1

		local trimmed = {}

		for i = startIndex, #results do
			table.insert(trimmed, results[i])
		end

		return trimmed
	end

	return results
end

function Logger:GetCount()
	return #history
end

function Logger:ClearHistory()
	table.clear(history)
end

function Logger:GetEngineHistory()
	return LogService:GetLogHistory()
end

return Logger