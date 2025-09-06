-- === Stable Sort ===

--- @param list any[]
--- @param workingList any[]
--- @param sortFunction fun( a, b ) : boolean
local function bindMergeSort( list, workingList, sortFunction )
    local function merge( start, finish )
        local left = start
        local leftFinish = math.floor( ( start + finish ) * 0.5 )
        local right = leftFinish + 1

        for index = start, finish do
            if right > finish then
                workingList[ index ] = list[ left ]
                left = left + 1

            elseif sortFunction( list[ left ], list[ right ] ) and left <= leftFinish then
                workingList[ index ] = list[ left ]
                left = left + 1

            else
                workingList[ index ] = list[ right ]
                right = right + 1
            end
        end

        for index = start, finish do
            list[ index ] = workingList[ index ]
        end
    end

    local function mergeSort( start, finish )
        if start >= finish then return end

        local middle = math.floor( ( start + finish ) * 0.5 )

        mergeSort( start, middle )
        mergeSort( middle + 1, finish )

        merge( start, finish )
    end

    return mergeSort
end


--- @param list any[]
--- @param sortFunction ( fun( a : any, b : any ) : boolean )
local function sortList( list, sortFunction )
    local workingList = { unpack( list ) }
    local result = { unpack( list ) }
    local sort = bindMergeSort( result, workingList, sortFunction )

    sort( 1, #list )

    return result
end


-- === Sparse Set ===

--- @class Dark.SparseSet : table
--- @field dense any[]
--- @field sparse { [any] : integer }
--- @overload fun() : Dark.SparseSet
local SparseSet = setmetatable( {}, { __call = function ( self )
    return setmetatable( { dense = {}, sparse = {} }, self )
end } )


--- @private
SparseSet.__index = SparseSet


--- @param value any
function SparseSet:has( value )
    return self.sparse[ value ] ~= nil
end


--- @param value any
function SparseSet:add( value )
    if self:has( value ) then return end

    table.insert( self.dense, value )
    self.sparse[ value ] = #self.dense
end


--- @param value any
function SparseSet:delete( value )
    local index = self.sparse[ value ]

    if index == nil then return end

    local backValue = table.remove( self.dense )

    if backValue == value then return end

    self.dense[ index ] = backValue
    self.sparse[ backValue ] = index
end


function SparseSet:iterate()
    local dense = self.dense
    local index = #dense + 1

    return function ()
        index = index - 1
        return dense[ index ]
    end
end


-- === ECS ===

--- @alias Dark.Entity table
--- @alias Dark.Filter fun( entity : Dark.Entity ) : boolean
--- @alias Dark.Run fun( entity : Dark.Entity, deltaTime : number? )
local dark = {}


-- Filter

local filterHelpers = {}
dark.filters = filterHelpers


--- This filter will only allow entities who have all of these components.
--- @param components string[] #Component names
--- @return Dark.Filter
function filterHelpers.all( components )
    return function ( entity )
        for _, component in ipairs( components ) do
            if entity[ component ] == nil then return false end
        end

        return true
    end
end


--- This filter will allow entities who have any of these components.
--- @param components string[] #Component names
--- @return Dark.Filter
function filterHelpers.any( components )
    return function ( entity )
        for _, component in ipairs( components ) do
            if entity[ component ] ~= nil then return true end
        end

        return false
    end
end


--- This filter will only allow entities that have these and only these components.
--- @param components string[] #Component names
--- @return Dark.Filter
function filterHelpers.exact( components )
    local requireAll = filterHelpers.all( components )

    return function ( entity )
        local keyCount = 0

        for _, _ in pairs( entity ) do
            keyCount = keyCount + 1
            if keyCount > #components then return false end
        end

        if keyCount < #components then return false end

        return requireAll( entity )
    end
end


--- This filter will reject entities that have any of these components, allowing all others.
--- @param components string[] #Component names
--- @return Dark.Filter
function filterHelpers.rejectAny( components )
    return function ( entity )
        for _, component in ipairs( components ) do
            if entity[ component ] ~= nil then return false end
        end

        return true
    end
end


--- This filter will reject entities that have all of these components, allowing all others.
--- @param components string[] #Component names
--- @return Dark.Filter
function filterHelpers.rejectAll( components )
    return function ( entity )
        for _, component in ipairs( components ) do
            if entity[ component ] == nil then return true end
        end

        return false
    end
end


-- World

--- @class Dark.World
--- @field package archetypeEntities { [Dark.Archetype] : Dark.SparseSet }
--- @field package allEntities Dark.SparseSet
local World = {}
local worldMetatable = { __index = World }


--- @return World
function dark.makeWorld( )
    return setmetatable( {
        archetypeEntities = {},
        allEntities = SparseSet()
    }, worldMetatable )
end


--- @param entity Dark.Entity
function World:addEntity( entity )
    self.allEntities:add( entity )

    for archetype, archetypeEntities in pairs( self.archetypeEntities ) do
        if not( archetype:filterEntity( entity ) ) then goto skip end

        archetypeEntities:add( entity )

        ::skip::
    end
end


--- @param entity Dark.Entity
function World:deleteEntity( entity )
    self.allEntities:delete( entity )

    for _, archetypeEntities in pairs( self.archetypeEntities ) do
        archetypeEntities:delete( entity )
    end
end


--- @private
--- @param system Dark.System
function World:initSystem( system )
    local archetypeEntities = SparseSet()
    local archetype = system.archetype

    self.archetypeEntities[ archetype ] = archetypeEntities

    for entity in self.allEntities:iterate() do
        if not( archetype:filterEntity( entity ) ) then goto skip end

        archetypeEntities:add( entity )

        ::skip::
    end
end


--- @param system Dark.System
--- @param deltaTime number?
function World:runSystem( system, deltaTime )
    local archetype = system.archetype
    local archetypeEntities = self.archetypeEntities[ archetype ]
    local run = system.run
    local sort = system.sort

    if archetypeEntities == nil then
        self:initSystem( system )
        archetypeEntities = self.archetypeEntities[ archetype ]
    end

    if sort ~= nil then
        local sortedEntities = sortList( archetypeEntities.dense, sort )

        for _, entity in ipairs( sortedEntities ) do
            run( entity, deltaTime )
        end
    else
        for entity in archetypeEntities:iterate() do
            run( entity, deltaTime )
        end
    end
end


--System

--- @class Dark.System
--- @field package archetype Dark.Archetype
--- @field package run Dark.Run
--- @field package sort? fun( a : Dark.Entity, b : Dark.Entity ) : boolean
local System = {}
local systemMetatable = { __index = System }


--- @param archetype Dark.Archetype
--- @param run Dark.Run
--- @param sort? fun( a : Dark.Entity, b : Dark.Entity ) : boolean
--- @return Dark.System
function dark.makeSystem( archetype, run, sort )
    local system = { archetype = archetype, run = run, sort = sort }
    return setmetatable( system, systemMetatable )
end


-- Archetype

--- @class Dark.Archetype
--- @field package filters Dark.Filter[]
local Archetype = {}
local archetypeMetatable = { __index = Archetype }


--- @param ... Dark.Filter | Dark.Archetype
--- @return Dark.Archetype
function dark.makeArchetype( ... )
    local archetype = { filters = {} }

    for index = 1, select( "#", ... ) do
        local item = ( select( index, ... ) )
        local itemType = type( item )

        if itemType == "function" then
            table.insert( archetype.filters, item )

        elseif itemType == "table" then
            for _, filter in ipairs( item.filters ) do
                table.insert( archetype.filters, filter )
            end
        end
    end

    return setmetatable( archetype, archetypeMetatable )
end


--- @package
--- @param entity Dark.Entity
function Archetype:filterEntity( entity )
    for _, filter in ipairs( self.filters ) do
        if not( filter( entity ) ) then return false end
    end

    return true
end


return dark
