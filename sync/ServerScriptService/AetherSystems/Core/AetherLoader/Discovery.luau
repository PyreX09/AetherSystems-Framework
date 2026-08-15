local SSS = game:GetService("ServerScriptService")

local module = {}

local function findPrimaryModule(root, maxDepth)
	maxDepth = maxDepth or 3
	local function walk(node, depth, systemName)
		if depth > maxDepth then return nil, nil end

		for _, child in ipairs(node:GetChildren()) do
			if child:IsA("ModuleScript") then
				return child, systemName or node.Name
			end
		end

		for _, child in ipairs(node:GetChildren()) do
			if child:IsA("Folder") then
				local found, foundName = walk(child, depth + 1, child.Name)
				if found then
					return found, foundName
				end
			end
		end

		return nil, nil
	end

	return walk(root, 0, root.Name)
end

function module.Discover()
	local aetherRoot = SSS:FindFirstChild("AetherSystems")
	if not aetherRoot then
		error("[Discovery] AetherSystems folder not found in ServerScriptService")
	end

	local entries = {}
	local foldersToScan = {"Services", "Systems"} 

	for _, targetFolderName in ipairs(foldersToScan) do
		local rootFolder = aetherRoot:FindFirstChild(targetFolderName)

		if rootFolder then
			local children = rootFolder:GetChildren()
			table.sort(children, function(a, b) return a.Name < b.Name end)

			for _, item in ipairs(children) do
				if item:IsA("Folder") then
					local primary, resolvedName = findPrimaryModule(item)
					if primary then
						table.insert(entries, { Name = resolvedName, Module = primary })
					else
						warn("[Discovery] No primary ModuleScript found for folder: " .. item.Name)
					end
				elseif item:IsA("ModuleScript") then
					table.insert(entries, { Name = item.Name, Module = item })
				end
			end
		end
	end

	return entries
end

return module