--- Класс гонки
-- @module dpRaceManager.Race
-- @author Wherry

Race = newclass("Race")

-- Конструктор
-- table settings - таблица настроек гонки
function Race:init(settings)
	---- Состояние гонки. 
	-- Нельзя изменить напрямую, только через race:setState(state)
	-- Возможные состояния: 
	-- no_map 	- карта ещё не загружена. Нельзя добавлять или удалять игроков.
	-- waiting 	- ожидание старта. Можно добавлять и удалять игроков.
	-- running	- непосредственно гонка. Нельзя добавлять игроков, но можно удалять игроков.
	-- finished - гонка завершилась. Нельзя добавлять игроков, но можно удалять игроков.
	self._state = "no_map"

	---- Настройки гонки
	-- number duration 		- продолжительность гонки в секундах
	-- bool ignoreSpawnpoints - начать гонку в точках, где находятся игроки, в данный момент.
	--							Если у трассы нет спавнпойнтов, гонка начнется в точках, где
	--							находятся игроки, в данный момент.
	-- bool separateDimension - использовать отдельный dimension
	--						По умолчанию игроки переносятся в отдельный dimension, чтобы не
	--						происходило случаных помех или падений фпс из-за скоплений игроков.
	-- bool createVehicles	- создать автомобиль для участников гонки. TODO: Пока не нужно  
	-- bool fadeCameraOnJoin - затемнять камеру игрока при добавлении его в гонку
	self.settings = {
		duration = 10,
		ignoreSpawnpoints = false,
		separateDimension = true,
		createVehicles = false,
		fadeCameraOnJoin = true
	}
	-- Установить не указанные настройки по умолчанию
	self.settings = exports.dpUtils:extendTable(settings, self.settings)
	-- Участники гонки
	self.players = {}
	-- Dimension гонки
	self.dimension = 0

	self.gameplay = RaceGameplay(self)
	self.finishedPlayers = {}
end

-- Гонка была добавлена в RaceManager
function Race:onAdded()
	if self.settings.separateDimension then
		-- Выбор dimension'а в зависимости от id гонки
		self.dimension = 70000 + self.id
	end
end

--- Загрузка карты в гонку
-- @tparam string mapName - название карты
function Race:loadMap(mapName)
	if type(mapName) ~= "string" then
		return false
	end	
	if self:getState() ~= "no_map" then
		return false
	end
	self.map = MapLoader()
	if not self.map:load(mapName) then
		return false
	end
	self:setState("waiting")
	return true
end

function Race:setMap(mapData)
	if type(mapData) ~= "table" then
		return false
	end
	self.map = MapLoader()
	self.map.checkpoints = mapData.checkpoints
	self:setState("waiting")
	return true
end

-- Вызывает клиентский метод, определенный в client->Race, для всех игроков гонки
function Race:callMethod(methodName, ...)
	for i, player in ipairs(self.players) do
		self:callPlayerMethod(player, methodName, ...)
	end
	return true
end

-- Вызывает клиентский метод, определенный в client->Race, для указанного игрока
function Race:callPlayerMethod(player, methodName, ...)
	return triggerClientEvent(player, "dpRaceManager.rpc", resourceRoot, methodName, ...)
end

-- Смена состояния гонки
function Race:setState(state)
	if type(state) ~= "string" then
		return true
	end
	if self._state == state then
		return false
	end
	self._state = state
	-- Передать всем игрокам новое состояние гонки
	self:callMethod("updateState", state)
	return true
end

-- Возвращает текущее состояние гонки
function Race:getState()
	return self._state
end

--- Добавление игрока в гонку
function Race:addPlayer(player)
	if self.state == "no_map" then
		outputDebugString("Can't add player: no map loaded")
		return false
	end
	if not isElement(player) or player.type ~= "player" then
		return false
	end
	-- Игрок уже находится в другой гонке
	if player:getData("race_id") then
		outputDebugString("Player '" .. tostring(player.name) .. "' is already in other race")
		return false
	end
	-- Игрок не находится в автомобиле, когда гонка требует машину игрока
	if not self.settings.createVehicles and not isElement(player.vehicle) then
		outputDebugString("Player '" .. tostring(player.name) .. "' must be in a vehicle to join this race")
		return false
	end
	-- Добавление игрока в список участников
	table.insert(self.players, player)
	player:setData("race_id", self.id)
	-- Обработка входа в гонку
	self.gameplay:onPlayerJoin(player)
	-- Вызов клиентских методов
	self:callPlayerMethod(player, "onJoin", self.settings, self.dimension)
	self:callMethod("onPlayerJoin", player)
	self:callPlayerMethod(player, "updateState", self:getState())
	-- Отправить карту
	triggerLatentClientEvent(player, "dpRaceManager.rpc", resourceRoot, "loadMap", self.map:getMapJSON())
	return true
end

--- Проверка на нахождение игрока в гонке
function Race:isPlayerIn(player)
	if not isElement(player) or player.type ~= "player" then
		return false
	end	
	-- Поиск игрока в списке участников гонки 
	for i, p in ipairs(self.players) do
		if p == player then
			return true, i
		end
	end
	return false
end

--- Добавление нескольких игроков в гонку
function Race:addPlayers(playersTable)
	if type(playersTable) ~= "table" then
		return false
	end
	-- Добавление игроков из списка в гонку
	for i, player in ipairs(playersTable) do
		self:addPlayer(player)
	end
	return true
end

--- Удаление игрока из гонки
function Race:removePlayer(player)
	if not isElement(player) or player.type ~= "player" then
		return false
	end
	-- Если игрок не находится в гонке
	if not player:getData("race_id") then
		outputDebugString("Race:removePlayer - player is not in race")
		return false
	end
	-- Если игрок находится в другой гонке
	if player:getData("race_id") ~= self.id then
		outputDebugString("Race:removePlayer - player is in another race")
		return false
	end

	-- Удалить игрока
	for i, p in ipairs(self.players) do
		if p == player then			
			-- Обработать выход игрока
			self.gameplay:onPlayerLeave(player)
			self:callPlayerMethod(player, "onLeave")
			self:callMethod("onPlayerLeave", player)
			-- Полностью удалить игрока из гонки
			player:setData("race_id", false)
			table.remove(self.players, i)
			-- Если все игроки покинули гонку - удалить её
			if #self.players == 0 then
				self.raceManager:removeRace(self)
			end
			return true
		end
	end
	return false
end

function Race:removeAllPlayers()
	while #self.players > 0 do
		self:removePlayer(self.players[1])
	end
end

function Race:run()
	self.gameplay:onRaceStart()

	local duration = self.settings.duration

	local race = self
	self.durationTimer = setTimer(function()
		race:onTimeout()
	end, duration * 1000, 1)

	self:setState("running")
end

--- Запуск гонки
function Race:start()
	if self:getState() ~= "waiting" then
		return false
	end
	if #self.players == 0 then
		outputDebugString("Race:start - can't start a race without players. Removing...")
		self.raceManager:removeRace(self)
		return false
	end
	self.finishedPlayers = {}

	self:callMethod("showCountdown", self.players)
	local race = self
	setTimer(function()
		race:run()
	end, 1000 * 3, 1)
end

function Race:playerFinish(player)
	if not isElement(player) or player.type ~= "player" then
		return false
	end	
	local timeLeft = getTimerDetails(self.durationTimer)
	if not timeLeft then
		return false
	end
	local timePassed = self.settings.duration * 1000 - timeLeft
	local rank = #self.finishedPlayers + 1
	local money = 2500 - (500 * (rank - 1))
	local xp = 250 - (50 * (rank - 1))
	table.insert(self.finishedPlayers, {
		player = player,
		time = timePassed,
		rank = rank, 
		money = money,
		xp = xp
	})
	self:callMethod("updateFinishedPlayers", self.finishedPlayers)
	return true
end

-- Время вышло
function Race:onTimeout()
	-- Принудительно финишировать всем игрокам
	for i, player in ipairs(self.players) do
		self:playerFinish(player)
	end	
	self:callMethod("timeout")
	if isTimer(self.durationTimer) then
		killTimer(self.durationTimer)
	end	
	self.durationTimer = nil
	outputDebugString("Race timeout")
	--self:removeAllPlayers()
end

---- Обработчики событий МТА
-- Каждый обработчик должен иметь следующее имя:
-- <eventName>Handler, где eventName - название события
-- Например: "onPlayerQuitHandler"
-- source - первый аргумент обработчика

-- Игрок вышел из автомобиля
function Race:onVehicleStartExitHandler(vehicle, player)
	-- TODO: Запустить таймер, показать предупреждение
	self:playerFinish(player)
end

-- Игрок вышел с сервера
function Race:onPlayerQuitHandler(player)
	self:removePlayer(player)
end

function Race:leaveRaceHandler(player)
	self:removePlayer(player)
end

function Race:finishRaceHandler(player)
	if not self.durationTimer then
		return false
	end
	self:playerFinish(player)
end