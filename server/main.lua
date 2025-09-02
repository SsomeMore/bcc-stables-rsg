local Core = exports['rsg-core']:GetCoreObject()
local BccUtils = exports['bcc-utils'].initiate()
local CooldownData = {}
local DevModeActive = Config.devMode

local function DebugPrint(message)
    if DevModeActive then
        print('^1[DEV MODE] ^4' .. message)
    end
end

if Config.discord.active == true then
    Discord = BccUtils.Discord.setup(Config.discord.webhookURL, Config.discord.title, Config.discord.avatar)
end

local function LogToDiscord(name, description, embeds)
    if Config.discord.active == true then
        Discord:sendMessage(name, description, embeds)
    end
end

local function SetPlayerCooldown(type, citizenid)
    CooldownData[type .. tostring(citizenid)] = os.time()
end

Core.Functions.CreateCallback('bcc-stables:BuyHorse', function(source, cb, data)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return cb(false) end
    
    local citizenid = Player.PlayerData.citizenid
    local maxHorses = data.isTrainer and tonumber(Config.maxTrainerHorses) or tonumber(Config.maxPlayerHorses)
    
    -- Query using citizenid instead of charid for RSG Core
    local result = MySQL.query.await('SELECT COUNT(*) as count FROM `player_horses` WHERE `citizenid` = ? AND `dead` = ?', { citizenid, 0 })
    local horseCount = result[1] and result[1].count or 0
    
    if horseCount >= maxHorses then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Horse Limit Reached',
            description = Lang:t('error.horse_limit', { limit = maxHorses }),
            type = 'error'
        })
        return cb(false)
    end
    
    local model = data.ModelH
    local colorCfg = nil
    
    -- Find horse configuration
    for _, horseCfg in pairs(Horses) do
        if horseCfg.colors and horseCfg.colors[model] then
            colorCfg = horseCfg.colors[model]
            break
        end
    end
    
    if not colorCfg then
        print('Horse model not found in the configuration:', model)
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Error',
            description = 'Horse model not found in configuration',
            type = 'error'
        })
        return cb(false)
    end
    
    -- Check payment method and funds
    if data.IsCash then
        local cashPrice = colorCfg.cashPrice or 0
        if Player.PlayerData.money['cash'] >= cashPrice then
            -- Remove money and proceed
            Player.Functions.RemoveMoney('cash', cashPrice)
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Purchase Successful',
                description = 'Horse purchased with cash: $' .. cashPrice,
                type = 'success'
            })
            cb(true)
        else
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Insufficient Funds',
                description = Lang:t('error.short_cash'),
                type = 'error'
            })
            cb(false)
        end
    else
        -- For gold payment, check if RSG Core supports gold currency
        local goldPrice = colorCfg.goldPrice or 0
        if Player.PlayerData.money['gold'] and Player.PlayerData.money['gold'] >= goldPrice then
            -- Remove gold and proceed
            Player.Functions.RemoveMoney('gold', goldPrice)
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Purchase Successful',
                description = 'Horse purchased with gold: ' .. goldPrice .. 'g',
                type = 'success'
            })
            cb(true)
        elseif Player.PlayerData.money['bank'] >= goldPrice then
            -- Fallback to bank money if gold currency not supported
            Player.Functions.RemoveMoney('bank', goldPrice)
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Purchase Successful',
                description = 'Horse purchased from bank: $' .. goldPrice,
                type = 'success'
            })
            cb(true)
        else
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Insufficient Funds',
                description = Lang:t('error.short_gold'),
                type = 'error'
            })
            cb(false)
        end
    end
end)

Core.Functions.CreateCallback('bcc-stables:RegisterHorse', function(source, cb, data)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local citizenid = Player.PlayerData.citizenid

    local maxHorses = data.isTrainer and tonumber(Config.maxTrainerHorses) or tonumber(Config.maxPlayerHorses)

    local result = MySQL.query.await('SELECT COUNT(*) as count FROM `player_horses` WHERE `citizenid` = ? AND `dead` = ?', { citizenid, 0 })
    local horseCount = result[1].count
    
    if horseCount >= maxHorses then
        TriggerClientEvent('ox_lib:notify', src, {
            title = _U('horseLimit') .. maxHorses .. _U('horses'),
            type = 'error'
        })
        return cb(false)
    end

    if data.IsCash and data.origin == 'tameHorse' then
        if Player.PlayerData.money['cash'] >= Config.regCost then
            return cb(true)
        else
            TriggerClientEvent('ox_lib:notify', src, {
                title = _U('shortCash'),
                type = 'error'
            })
            return cb(false)
        end
    end

    cb(false)
end)

Core.Functions.CreateCallback('bcc-stables:BuyTack', function(source, cb, data)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local cashPrice = tonumber(data.cashPrice)
    local goldPrice = tonumber(data.goldPrice)

    if cashPrice > 0 and goldPrice > 0 then
        if tonumber(data.currencyType) == 0 then
            if Player.PlayerData.money['cash'] >= cashPrice then
                Player.Functions.RemoveMoney('cash', cashPrice)
            else
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Insufficient Funds',
                    description = Lang:t('error.short_cash'),
                    type = 'error'
                })
                return cb(false)
            end
        else
            if Player.PlayerData.money['gold'] >= goldPrice then
                Player.Functions.RemoveMoney('gold', goldPrice)
            else
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Insufficient Funds',
                    description = Lang:t('error.short_gold'),
                    type = 'error'
                })
                return cb(false)
            end
        end
        TriggerClientEvent('ox_lib:notify', src, {
            title = _U('purchaseSuccessful'),
            type = 'success'
        })
        return cb(true)
    end

    cb(false)
end)

Core.Functions.CreateCallback('bcc-stables:SaveNewHorse', function(source, cb, data)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local citizenid = Player.PlayerData.citizenid
    local identifier = Player.PlayerData.license  -- RSG-Core uses license as primary identifier
    local name = data.name
    local model = data.ModelH
    local gender = data.gender
    local captured = data.captured
    local isCash = data.IsCash
    local priceKey = isCash and 'cashPrice' or 'goldPrice'
    local moneyType = isCash and 'cash' or 'gold'
    local currency = Player.PlayerData.money[moneyType]
    local notification = isCash and _U('shortCash') or _U('shortGold')

    for _, horseCfg in pairs(Horses) do
        local colorCfg = horseCfg.colors[model]
        if colorCfg then
            if currency >= colorCfg[priceKey] then
                Player.Functions.RemoveMoney(moneyType, colorCfg[priceKey])

                MySQL.query.await([[
                    INSERT INTO `player_horses` (identifier, citizenid, name, model, gender, captured)
                    VALUES (?, ?, ?, ?, ?, ?)
                ]],
                { identifier, citizenid, name, model, gender, captured })

                LogToDiscord(charid, _U('discordHorsePurchased'))
                return cb(true)
            else
                TriggerClientEvent('ox_lib:notify', src, {
                    title = notification,
                    type = 'error'
                })
                return cb(false)
            end
        end
    end

    cb(false)
end)


Core.Functions.CreateCallback('bcc-stables:SaveTamedHorse', function(source, cb, data)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local citizenid = Player.PlayerData.citizenid
    local identifier = Player.PlayerData.license  -- RSG-Core uses license as primary identifier
    local regCost = Config.regCost
    local name = data.name
    local model = data.ModelH
    local gender = data.gender
    local captured = data.captured

    if data.IsCash and data.origin == 'tameHorse' then
        if Player.PlayerData.money['cash'] < regCost then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Insufficient Funds',
                description = Lang:t('error.short_cash'),
                type = 'error'
            })
            return cb(false)
        end
        Player.Functions.RemoveMoney('cash', regCost)
    end

    -- Include the identifier field in the INSERT query for RSG-Core compatibility
    MySQL.query.await('INSERT INTO `player_horses` (citizenid, identifier, name, model, gender, captured) VALUES (?, ?, ?, ?, ?, ?)',
    { citizenid, identifier, name, model, gender, captured })

    LogToDiscord(citizenid, _U('discordTamedPurchased'))
    cb(true)
end)

Core.Functions.CreateCallback('bcc-stables:UpdateHorseName', function(source, cb, data)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local citizenid = Player.PlayerData.citizenid
    local newName = data.name
    local horseId = data.horseId

    MySQL.query.await('UPDATE `player_horses` SET `name` = ? WHERE `id` = ? AND `citizenid` = ?',
    { newName, horseId, citizenid })

    cb(true)
end)

RegisterNetEvent('bcc-stables:UpdateHorseXp', function(Xp, horseId)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local identifier = Player.PlayerData.license
    local citizenid = Player.PlayerData.citizenid

    MySQL.query.await('UPDATE `player_horses` SET `xp` = ? WHERE `id` = ? AND `identifier` = ? AND `citizenid` = ?',
    { Xp, horseId, identifier, citizenid })

    LogToDiscord(citizenid, _U('discordHorseXPGain'))
end)

RegisterNetEvent('bcc-stables:SaveHorseStatsToDb', function(health, stamina, id)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local identifier = Player.PlayerData.license
    local citizenid = Player.PlayerData.citizenid
    local horseHealth = tonumber(health) or 100
    local horseStamina = tonumber(stamina) or 100
    local horseId = tonumber(id)

    print("Saving horse stats to DB:", horseId, horseHealth, horseStamina)
    MySQL.query.await('UPDATE `player_horses` SET `health` = ?, `stamina` = ? WHERE id = ? AND `identifier` = ? AND `citizenid` = ?',
    { horseHealth, horseStamina, horseId, identifier, citizenid })
end)

RegisterNetEvent('bcc-stables:SelectHorse', function(data)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local identifier = Player.PlayerData.license
    local citizenid = Player.PlayerData.citizenid
    local selectedHorseId = data.horseId

    -- Deselect all horses for the character
    MySQL.query('UPDATE `player_horses` SET `selected` = ? WHERE `citizenid` = ? AND `identifier` = ? AND `dead` = ?',
    { 0, citizenid, identifier, 0 })

    -- Select the specified horse
    MySQL.query('UPDATE `player_horses` SET `selected` = ? WHERE `id` = ? AND `citizenid` = ? AND `identifier` = ?',
    { 1, selectedHorseId, citizenid, identifier })
end)

RegisterNetEvent('bcc-stables:SetHorseWrithe', function(horseId)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local identifier = Player.PlayerData.license
    local citizenid = Player.PlayerData.citizenid

    MySQL.query.await('UPDATE `player_horses` SET `writhe` = ? WHERE `id` = ? AND `identifier` = ? AND `citizenid` = ?',
    { 1, horseId, identifier, citizenid })
end)

-- Update Horse Selected and Dead Status After Death Event
RegisterNetEvent('bcc-stables:UpdateHorseStatus', function(horseId, action)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local identifier = Player.PlayerData.license
    local citizenid = Player.PlayerData.citizenid

    local selected = (action == 'dead' or action == 'deselect') and 0 or 1
    local dead = action == 'dead' and 1 or 0

    MySQL.query.await('UPDATE `player_horses` SET `selected` = ?, `writhe` = ?, `dead` = ? WHERE `id` = ? AND `identifier` = ? AND `citizenid` = ?',
    { selected, 0, dead, horseId, identifier, citizenid })
end)

Core.Functions.CreateCallback('bcc-stables:GetHorseData', function(source, cb)
    local src = source
    local Player = Core.Functions.GetPlayer(src)

    if not Player then
        DebugPrint('User not found for source: ' .. tostring(src))
        return cb(false)
    end

    local citizenid = Player.PlayerData.citizenid

    local horses = MySQL.query.await('SELECT * FROM `player_horses` WHERE `citizenid` = ? AND `dead` = ?',
    { citizenid, 0 })

    if #horses == 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            title =  _U('noHorses'),
            type = 'error'
        })
        return cb(false)
    end

    local selectedHorse = nil
    for _, horse in ipairs(horses) do
        if horse.selected == 1 then
            selectedHorse = horse
            break
        end
    end

    if not selectedHorse then
        TriggerClientEvent('ox_lib:notify', src, {
            title = _U('noSelectedHorse'),
            type = 'error'
        })
        return cb(false)
    end

    cb({
        model = selectedHorse.model,
        name = selectedHorse.name,
        components = selectedHorse.components,
        id = selectedHorse.id,
        gender = selectedHorse.gender,
        xp = selectedHorse.xp,
        captured = selectedHorse.captured,
        health = selectedHorse.health,
        stamina = selectedHorse.stamina,
        writhe = selectedHorse.writhe
    })
end)

Core.Functions.CreateCallback('bcc-stables:GetMyHorses', function(source, cb)
    local src = source
    local Player = Core.Functions.GetPlayer(src)

    -- Check if the player exists
    if not Player then
        DebugPrint('User not found for source: ' .. tostring(src))
        return cb(false)
    end

    local citizenid = Player.PlayerData.citizenid

    local horses = MySQL.query.await('SELECT * FROM `player_horses` WHERE `citizenid` = ? AND `dead` = ?', { citizenid, 0 })

    cb(horses)
end)

Core.Functions.CreateCallback('bcc-stables:UpdateComponents', function(source, cb, encodedComponents, horseId)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local citizenid = Player.PlayerData.citizenid

    MySQL.query.await('UPDATE `player_horses` SET `components` = ? WHERE `id` = ? AND `citizenid` = ?',
    { encodedComponents, horseId, citizenid })

    cb(true)
end)

Core.Functions.CreateCallback('bcc-stables:SellMyHorse', function(source, cb, data)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local citizenid = Player.PlayerData.citizenid
    local model = nil
    local horseId = tonumber(data.horseId)
    local captured = data.captured
    local matchFound = false

    -- Fetch the horse data
    local horses = MySQL.query.await('SELECT `id`, `model` FROM `player_horses` WHERE `citizenid` = ? AND `dead` = ?',
    { citizenid, 0 })

    -- Find the horse and delete it
    for i = 1, #horses do
        if tonumber(horses[i].id) == horseId then
            matchFound = true
            model = horses[i].model

            MySQL.query.await('DELETE FROM `player_horses` WHERE `id` = ? AND `citizenid` = ?',
            { horseId, citizenid })

            LogToDiscord(citizenid, _U('discordHorseSold'))
            break
        end
    end

    if not matchFound then return cb(false) end

    -- Determine the sell price
    for _, horseCfg in pairs(Horses) do
        local colorCfg = horseCfg.colors[model]
        if colorCfg then
            local sellPrice = captured and (Config.tamedSellPrice * colorCfg.cashPrice) or (Config.sellPrice * colorCfg.cashPrice)
            Player.Functions.AddMoney('cash', sellPrice)
            TriggerClientEvent('ox_lib:notify', src, {
                title = _U('soldHorse') .. sellPrice,
                type = 'success'
            })
            return cb(true)
        end
    end

    cb(false)
end)

RegisterNetEvent('bcc-stables:SellTamedHorse', function(hash)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local sellPriceMultiplier = Config.tamedSellPrice

    for _, horseCfg in pairs(Horses) do
        for color, colorCfg in pairs(horseCfg.colors) do
            local colorHash = joaat(color)
            if colorHash == hash then
                local sellPrice = (sellPriceMultiplier * colorCfg.cashPrice)
                
                -- Add money to player (RSG-Core uses AddMoney)
                Player.Functions.AddMoney('cash', math.ceil(sellPrice))
                
                -- Send ox_lib notification
                TriggerClientEvent('ox_lib:notify', src, {
                    title = _U('horseSold'),
                    description = _U('soldHorse') .. sellPrice,
                    type = 'success',
                    duration = 4000
                })
                
                SetPlayerCooldown('sellTame', citizenid)
                LogToDiscord(citizenid, _U('discordTamedSold'))
                return
            end
        end
    end
end)

RegisterNetEvent('bcc-stables:SaveHorseTrade', function(serverId, horseId)
    -- Current Owner
    local src = source
    local curPlayer = Core.Functions.GetPlayer(src)
    if not curPlayer then return end

    local curOwnerId = curPlayer.PlayerData.license
    local curOwnercitizenid = curPlayer.PlayerData.citizenid
    local curOwnerName = curPlayer.PlayerData.charinfo.firstname .. " " .. curPlayer.PlayerData.charinfo.lastname
    
    -- New Owner
    local newPlayer = Core.Functions.GetPlayer(serverId)
    if not newPlayer then return end

    local newOwnerId = newPlayer.PlayerData.license
    local newOwnercitizenid = newPlayer.PlayerData.citizenid
    local newOwnerName = newPlayer.PlayerData.charinfo.firstname .. " " .. newPlayer.PlayerData.charinfo.lastname

    -- Fetch the horse
    local horse = MySQL.query.await('SELECT * FROM `player_horses` WHERE `id` = ? AND `citizenid` = ? AND `identifier` = ? AND `dead` = ?',
    { horseId, curOwnercitizenid, curOwnerId, 0 })

    if horse and #horse > 0 then
        -- Update the horse ownership
        MySQL.query.await('UPDATE `player_horses` SET `identifier` = ?, `citizenid` = ?, `selected` = ? WHERE `id` = ?',
        { newOwnerId, newOwnercitizenid, 0, horseId })

        -- Notify both parties using ox_lib
        TriggerClientEvent('ox_lib:notify', src, {
            title = _U('horseTraded'),
            description = _U('youGave') .. newOwnerName .. _U('aHorse'),
            type = 'success',
            duration = 4000
        })
        
        TriggerClientEvent('ox_lib:notify', serverId, {
            title = _U('horseReceived'),
            description = curOwnerName .. _U('gaveHorse'),
            type = 'success',
            duration = 4000
        })

        LogToDiscord(curOwnerName, _U('discordTraded') .. newOwnerName)
    end
end)

RegisterNetEvent('bcc-stables:RegisterInventory', function(id, model)
    local idStr = 'horse_' .. tostring(id)
    
    for _, horseCfg in pairs(Horses) do
        if horseCfg.colors[model] then
            local colorCfg = horseCfg.colors[model]
            local data = {
                id = idStr,
                label = _U('horseInv'),
                slots = tonumber(colorCfg.invLimit) or 10,
                weight = Config.horseWeight or 100000, -- RSG-Inventory uses weight instead of limit
                owner = false, -- Set to false for shared inventories
                isOpen = false
            }

            -- Register the inventory with RSG-Inventory
            exports['rsg-inventory']:CreateInventory(data.id, data.label, data.slots, data.weight)
            
            -- Set additional properties if needed
            if Config.shareInventory then
                exports['rsg-inventory']:SetInventoryShared(idStr, true)
            end

            -- Handle weapon restrictions
            if not Config.allowWeapons then
                exports['rsg-inventory']:SetInventoryWeaponRestriction(idStr, true)
            end

            -- Handle item whitelist/blacklist
            if Config.useBlackList and Config.itemsBlackList then
                for _, item in ipairs(Config.itemsBlackList) do
                    exports['rsg-inventory']:AddInventoryItemBlacklist(idStr, item)
                end
            end

            if Config.useWhiteList and Config.itemsLimitWhiteList then
                for _, item in ipairs(Config.itemsLimitWhiteList) do
                    exports['rsg-inventory']:SetInventoryItemLimit(idStr, item.name, item.limit)
                end
            end

            -- Handle weapon whitelist
            if Config.whitelistWeapons and Config.weaponsLimitWhiteList then
                for _, weapon in ipairs(Config.weaponsLimitWhiteList) do
                    exports['rsg-inventory']:SetInventoryWeaponLimit(idStr, weapon.name, weapon.limit)
                end
            end

            -- Handle permissions (if RSG-Inventory supports job-based permissions)
            if Config.usePermissions and Config.permissions then
                if Config.permissions.allowedJobsTakeFrom then
                    for _, permission in ipairs(Config.permissions.allowedJobsTakeFrom) do
                        exports['rsg-inventory']:AddInventoryPermission(idStr, 'take', permission.name, permission.grade)
                    end
                end
                
                if Config.permissions.allowedJobsMoveTo then
                    for _, permission in ipairs(Config.permissions.allowedJobsMoveTo) do
                        exports['rsg-inventory']:AddInventoryPermission(idStr, 'move', permission.name, permission.grade)
                    end
                end
            end
            
            break
        end
    end
end)

RegisterNetEvent('bcc-stables:OpenInventory', function(id)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local idStr = 'horse_' .. tostring(id)
    exports['rsg-inventory']:OpenInventory(src, idStr, {
        maxweight = Config.horseInventoryWeight or 1000,
        slots = Config.horseInventorySlots or 10,
    })
end)

-- Iterate over each item in the Config.horseFood array to register them as usable items
for _, item in ipairs(Config.horseFood) do
    Core.Functions.CreateUseableItem(item, function(source, item)
        local src = source
        local Player = Core.Functions.GetPlayer(src)
        if not Player then return end

        TriggerClientEvent('bcc-stables:FeedHorse', src, item.name)
    end)
end

if Config.flamingHooves.active then
    Core.Functions.CreateUseableItem(Config.flamingHooves.item, function(source, item)
        local src = source
        local Player = Core.Functions.GetPlayer(src)
        if not Player then return end

        local playerItem = exports['rsg-inventory']:GetItemBySlot(src, item.slot)

        if Config.flamingHooves.durability then
            local maxDurability = Config.flamingHooves.maxDurability or 100
            local useDurability = Config.flamingHooves.durabilityPerUse or 1
            local itemMetadata = playerItem.info or {}
            local currentDurability = itemMetadata.durability

            -- Initialize durability if it doesn't exist
            if not currentDurability then
                currentDurability = maxDurability
                local newData = {
                    description = Lang:t('items.flame_hoove_desc') .. '<br>' .. Lang:t('info.durability') .. currentDurability .. '%',
                    durability = currentDurability,
                }
                exports['rsg-inventory']:SetItemData(src, Config.flamingHooves.item, item.slot, newData)
            end

            -- Check if durability is below the usage threshold
            if currentDurability < useDurability then
                exports['rsg-inventory']:RemoveItem(src, Config.flamingHooves.item, 1, item.slot)
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Item Broken',
                    description = Lang:t('error.item_broke'),
                    type = 'error'
                })
                return
            end
        end

        TriggerClientEvent('bcc-stables:FlamingHooves', src)
    end)

    RegisterNetEvent('bcc-stables:FlamingHoovesDurability', function()
        local src = source
        local Player = Core.Functions.GetPlayer(src)
        if not Player then return end

        local playerItem = Player.Functions.GetItemByName(Config.flamingHooves.item)
        if not playerItem then return end

        local useDurability = Config.flamingHooves.durabilityPerUse or 1
        local itemMetadata = playerItem.info or {}
        local newDurability = (itemMetadata.durability or 100) - useDurability

        -- Check if durability is below the usage threshold or update the durability
        if newDurability < useDurability then
            exports['rsg-inventory']:RemoveItem(src, Config.flamingHooves.item, 1, playerItem.slot)
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Item Broken',
                description = Lang:t('error.item_broke'),
                type = 'error'
            })
        else
            local newData = {
                description = Lang:t('items.flame_hoove_desc') .. '<br>' .. Lang:t('info.durability') .. newDurability .. '%',
                durability = newDurability,
            }
            exports['rsg-inventory']:SetItemData(src, Config.flamingHooves.item, playerItem.slot, newData)
        end
    end)
end

RegisterNetEvent('bcc-stables:RemoveItem', function(itemName)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    exports['rsg-inventory']:RemoveItem(src, itemName, 1)
end)

Core.Functions.CreateUseableItem(Config.horsebrush.item, function(source, item)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local playerItem = exports['rsg-inventory']:GetItemBySlot(src, item.slot)

    if Config.horsebrush.durability then
        local maxDurability = Config.horsebrush.maxDurability or 100
        local useDurability = Config.horsebrush.durabilityPerUse or 1
        local itemMetadata = playerItem.info or {}
        local currentDurability = itemMetadata.durability

        -- Initialize durability if it doesn't exist
        if not currentDurability then
            currentDurability = maxDurability
            local newData = {
                description = Lang:t('items.horsebrush_desc') .. '<br>' .. Lang:t('info.durability') .. currentDurability .. '%',
                durability = currentDurability,
            }
            exports['rsg-inventory']:SetItemData(src, Config.horsebrush.item, item.slot, newData)
        end

        -- Check if durability is below the usage threshold
        if currentDurability < useDurability then
            exports['rsg-inventory']:RemoveItem(src, Config.horsebrush.item, 1, item.slot)
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Item Broken',
                description = Lang:t('error.item_broke'),
                type = 'error'
            })
            return
        end
    end

    TriggerClientEvent('bcc-stables:BrushHorse', src)
end)

RegisterNetEvent('bcc-stables:HorseBrushDurability', function()
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local playerItem = Player.Functions.GetItemByName(Config.horsebrush.item)
    if not playerItem then return end

    local useDurability = Config.horsebrush.durabilityPerUse or 1
    local itemMetadata = playerItem.info or {}
    local newDurability = (itemMetadata.durability or 100) - useDurability

    -- Check if durability is below the usage threshold or update the durability
    if newDurability < useDurability then
        exports['rsg-inventory']:RemoveItem(src, Config.horsebrush.item, 1, playerItem.slot)
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Item Broken',
            description = Lang:t('error.item_broke'),
            type = 'error'
        })
    else
        local newData = {
            description = Lang:t('items.horsebrush_desc') .. '<br>' .. Lang:t('info.durability') .. newDurability .. '%',
            durability = newDurability,
        }
        exports['rsg-inventory']:SetItemData(src, Config.horsebrush.item, playerItem.slot, newData)
    end
end)

Core.Functions.CreateUseableItem(Config.lantern.item, function(source, item)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local playerItem = exports['rsg-inventory']:GetItemBySlot(src, item.slot)

    if Config.lantern.durability then
        local maxDurability = Config.lantern.maxDurability or 100
        local useDurability = Config.lantern.durabilityPerUse or 1
        local itemMetadata = playerItem.info or {}
        local currentDurability = itemMetadata.durability

        -- Initialize durability if it doesn't exist
        if not currentDurability then
            currentDurability = maxDurability
            local newData = {
                description = Lang:t('items.lantern_desc') .. '<br>' .. Lang:t('info.durability') .. currentDurability .. '%',
                durability = currentDurability,
            }
            exports['rsg-inventory']:SetItemData(src, Config.lantern.item, item.slot, newData)
        end

        -- Check if durability is below the usage threshold
        if currentDurability < useDurability then
            exports['rsg-inventory']:RemoveItem(src, Config.lantern.item, 1, item.slot)
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Item Broken',
                description = Lang:t('error.item_broke'),
                type = 'error'
            })
            return
        end
    end

    TriggerClientEvent('bcc-stables:UseLantern', src)
end)

RegisterNetEvent('bcc-stables:LanternDurability', function()
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return end

    local playerItem = Player.Functions.GetItemByName(Config.lantern.item)
    if not playerItem then return end

    local useDurability = Config.lantern.durabilityPerUse or 1
    local itemMetadata = playerItem.info or {}
    local newDurability = (itemMetadata.durability or 100) - useDurability

    -- Check if durability is below the usage threshold or update the durability
    if newDurability < useDurability then
        exports['rsg-inventory']:RemoveItem(src, Config.lantern.item, 1, playerItem.slot)
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Item Broken',
            description = Lang:t('error.item_broke'),
            type = 'error'
        })
    else
        local newData = {
            description = Lang:t('items.lantern_desc') .. '<br>' .. Lang:t('info.durability') .. newDurability .. '%',
            durability = newDurability,
        }
        exports['rsg-inventory']:SetItemData(src, Config.lantern.item, playerItem.slot, newData)
    end
end)

Core.Functions.CreateCallback('bcc-stables:HorseReviveItem', function(source, cb)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local reviveItem = Config.reviver
    local hasItem = Player.Functions.GetItemByName(reviveItem)

    if not hasItem then
        return cb(false)
    end

    exports['rsg-inventory']:RemoveItem(src, reviveItem, 1)
    cb(true)
end)

Core.Functions.CreateCallback('bcc-stables:CheckPlayerCooldown', function(source, cb, type)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    if not Player then return cb(false) end

    local citizenid = Player.PlayerData.citizenid
    local cooldown = Config.cooldown[type]
    local typeId = type .. tostring(citizenid)
    local currentTime = os.time()
    local lastTime = CooldownData[typeId]

    if lastTime then
        if os.difftime(currentTime, lastTime) >= cooldown * 60 then
            cb(false) -- Not on Cooldown
        else
            cb(true) -- On Cooldown
        end
    else
        cb(false) -- Not on Cooldown
    end
end)

Core.Functions.CreateCallback('bcc-stables:CheckJob', function(source, cb, trainer, site)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player then 
        return cb(false) 
    end

    local job = Player.PlayerData.job.name
    local grade = Player.PlayerData.job.grade.level
    
    local jobConfig
    if trainer then
        jobConfig = Config.trainerJob
    else
        -- Add nil checks for the stable site configuration
        if not Stables then
            return cb({false, job})
        end
        
        if not Stables[site] then
            return cb({false, job})
        end
        
        if not Stables[site].shop then
            return cb({false, job})
        end
        
        if not Stables[site].shop.jobs then
            return cb({false, job})
        end
        
        jobConfig = Stables[site].shop.jobs
    end

    -- Check if jobConfig exists and is a table
    if not jobConfig or type(jobConfig) ~= 'table' then
        return cb({false, job})
    end


    local hasJob = false
    for _, jobData in pairs(jobConfig) do
        if jobData and jobData.name and jobData.grade then
            if (job == jobData.name) and (tonumber(grade) >= tonumber(jobData.grade)) then
                hasJob = true
                break
            end
        end
    end

    cb({hasJob, job})
end)

RegisterNetEvent('Core:server:playerLoaded', function(Player)
    local src = source
    if not Player then return end

    -- Trigger horse entity update after player is fully loaded
    Wait(3000)
    TriggerClientEvent('bcc-stables:UpdateMyHorseEntity', src)
end)

--- Check if properly downloaded
function file_exists(name)
    local f = LoadResourceFile(GetCurrentResourceName(), name)
    return f ~= nil
end

if not file_exists('./ui/index.html') then
    print('^1 INCORRECT DOWNLOAD!  ^0')
    print(
        '^4 Please Download: ^2(bcc-stables.zip) ^4from ^3<https://github.com/BryceCanyonCounty/bcc-stables/releases/latest>^0')
end

BccUtils.Versioner.checkFile(GetCurrentResourceName(), 'https://github.com/BryceCanyonCounty/bcc-stables')
