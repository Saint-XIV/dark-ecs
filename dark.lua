--- @class Dark.SparseSet : table
--- @field private dense any[]
--- @field private sparse { [any] : integer }
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


--- @alias Dark.Entity table
--- @alias Dark.Filter fun( entity : Dark.Entity ) : boolean
--- @alias Dark.Run fun( entity : Dark.Entity, deltaTime : number? )


--- @class Dark.Archetype
--- @field package filters Dark.Filter[]
local Archetype = {}
local archetypeMetatable = { __index = Archetype }


--- @class Dark.System
--- @field package archetype Dark.Archetype
--- @field package run Dark.Run
local System = {}
local systemMetatable = { __index = System }


--- @class World
--- @field package archetypes { [Dark.Archetype] : Dark.SparseSet }
--- @field package systemSet Dark.SparseSet
local World = {}
local worldMetatable = { __index = World }


local lib = {}


-- Factory

--- @param ... Dark.System
--- @return World
function lib.makeWorld( ... )
    local world = {
        archetypes = {},
        systemSet = SparseSet()
    }

    for index = 1, select( "#", ... ) do
        --- @type Dark.System
        local system = ( select( index, ... ) )
        local archetype = system.archetype

        world.archetypes[ archetype ] = SparseSet
        world.systemSet:add( system )
    end

    return setmetatable( world, worldMetatable )
end


--- @param archetype Dark.Archetype
--- @param run Dark.Run
--- @return Dark.System
function lib.makeSystem( archetype, run )
    return setmetatable( { archetype = archetype, run = run }, systemMetatable )
end


--- @param ... Dark.Filter
--- @return Dark.Archetype
function lib.makeArchetype( ... )
    return setmetatable( { filters = { ... } }, archetypeMetatable )
end


-- Filter Helpers

local filterHelpers = {}


--- This filter will only allow entities who have all the components.
--- @param ... string #Component names
--- @return Dark.Filter
function filterHelpers.all( ... )
    local requiredComponents = { ... }

    return function ( entity )
        for _, component in ipairs( requiredComponents ) do
            if entity[ component ] == nil then return false end
        end

        return true
    end
end


--- This filter will allow entities who have any of the components.
--- @param ... string #Component names
--- @return Dark.Filter
function filterHelpers.any( ... )
    local requiredComponents = { ... }

    return function ( entity )
        for _, component in ipairs( requiredComponents ) do
            if entity[ component ] ~= nil then return true end
        end

        return false
    end
end


--- This filter will only allow entities that have these and only these components.
--- @param ... string #Component names
--- @return Dark.Filter
function filterHelpers.exact( ... )
    local requiredComponents = select( "#", ... )
    local requireAll = filterHelpers.all( ... )

    return function ( entity )
        local keyCount = 0

        for _, _ in pairs( entity ) do
            keyCount = keyCount + 1
            if keyCount > requiredComponents then return false end
        end

        if keyCount < requiredComponents then return false end

        return requireAll( entity )
    end
end


--- This filter will reject entities that have any of these components, allowing all others.
--- @param ... string #Component names
--- @return Dark.Filter
function filterHelpers.rejectAny( ... )
    local requiredComponents = { ... }

    return function ( entity )
        for _, component in ipairs( requiredComponents ) do
            if entity[ component ] ~= nil then return false end
        end

        return true
    end
end


--- This filter will reject entities that have all of these components, allowing all others.
--- @param ... string #Component names
--- @return Dark.Filter
function filterHelpers.rejectAll( ... )
    local requiredComponents = { ... }

    return function ( entity )
        for _, component in ipairs( requiredComponents ) do
            if entity[ component ] == nil then return true end
        end

        return false
    end
end


-- World Building

--- @package
--- @param entity Dark.Entity
function Archetype:filterEntity( entity )
    for _, filter in ipairs( self.filters ) do
        if not( filter( entity ) ) then return false end
    end

    return true
end


--- @param entity Dark.Entity
function World:addEntity( entity )
    for archetype, entitySet in pairs( self.archetypes ) do
        if not( archetype:filterEntity( entity ) ) then goto skip end

        entitySet:add( entity )

        ::skip::
    end
end


--- @param entity Dark.Entity
function World:deleteEntity( entity )
    for _, entitySet in pairs( self.archetypes ) do
        entitySet:delete( entity )
    end
end


--- @param system Dark.System
--- @param deltaTime number?
function World:runSystem( system, deltaTime )
    local entitySet = self.archetypes[ system.archetype ]
    local run = system.run

    for entity in entitySet:iterate() do
        run( entity, deltaTime )
    end
end


return lib