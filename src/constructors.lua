
-- Constructors

-- Patterns have the following, optional fields:
-- 
-- - type: the pattern type. ~1 to 1 correspondance with the pattern constructors
--     described in the LPeg documentation.
-- - pattern: the one subpattern held by the pattern, like most captures, or 
--     `#pt`, `-pt` and `pt^n`.
-- - aux: any other type of data associated to the pattern. Like the string of a
--     `P"string"`, the range of an `R`, or the list of subpatterns of a `+` or
--     `*` pattern. In some cases, the data is pre-processed. in that case,
--     the `as_is` field holds the data as passed to the constructor.
-- - as_is: see aux.
-- - meta: A table holding meta information about patterns, like their
--     minimal and maximal width, the form they can take when compiled, 
--     whether they are terminal or not (no V patterns), and so on.


local ipairs, newproxy, print, setmetatable 
    = ipairs, newproxy, print, setmetatable

local t, u, dtst, compat
    = require"table", require"util", require"datastructures", require"compat"

--[[DBG]] local debug = require"debug"

local t_concat, t_sort
    = t.concat, t.sort

local copy, getuniqueid, id, map
    , nop, weakkey, weakval
    = u.copy, u.getuniqueid, u.id, u.map
    , u.nop, u.weakkey, u.weakval

local _ENV = u.noglobals()



--- The type of cache for each kind of pattern:
--
-- Patterns are memoized using different strategies, depending on what kind of
-- data is associated with them.


local patternwith = {
    constant = {
        "Cp", "true", "false"
    },
    -- only aux
    aux = {
        "string", "any",
        "char", "range", "set", 
        "ref", "sequence", "choice",
        "Carg", "Cb"
    },
    -- only sub pattern
    subpt = {
        "unm", "lookahead", "C", "Cf", 
        "Cg", "Cs", "Ct", "/zero"
    }, 
    -- both
    both = {
        "behind", "at least", "at most", "Ctag", "Cmt",
        "/string", "/number", "/table", "/function"
    },
    none = "grammar", "Cc"
}



-------------------------------------------------------------------------------
return function(Builder, LL) --- module wrapper.
--


local split_int, S_tostring 
    = Builder.charset.split_int, Builder.set.tostring


-------------------------------------------------------------------------------
--- Base pattern constructor
--

local newpattern do 
    -- This deals with the Lua 5.1/5.2 compatibility, and restricted 
    -- environements without access to newproxy and/or debug.setmetatable.
    local setmetatable = setmetatable

    function LL.get_direct (p) return p end

    if compat.lua52_len then
        -- Lua 5.2 or LuaJIT + 5.2 compat. No need to do the proxy dance.
        function newpattern(pt)
            return setmetatable(pt,LL) 
        end    
    elseif compat.proxies then -- Lua 5.1 / LuaJIT without compat.
        local d_setmetatable, newproxy
            = compat.debug.setmetatable, newproxy

        local proxycache = weakkey{}
        local __index_LL = {__index = LL}
        LL.proxycache = proxycache
        function newpattern(cons) 
            local pt = newproxy()
            setmetatable(cons, __index_LL)
            proxycache[pt]=cons
            d_setmetatable(pt,LL) 
            return pt
        end
        function LL:__index(k)
            return proxycache[self][k]
        end
        function LL:__newindex(k, v)
            proxycache[self][k] = v
        end
        function LL.get_direct(p) return proxycache[p] end
    else
        -- Fallback if neither __len(table) nor newproxy work 
        -- for example in restricted sandboxes.
        if LL.warnings then
            print("Warning: The `__len` metatethod won't work with patterns, "
                .."use `LL.L(pattern)` for lookaheads.")
        end
        function newpattern(pt)
            return setmetatable(pt,LL) 
        end    
    end
end


-------------------------------------------------------------------------------
--- The caches
--

local ptcache, meta
local
function resetcache()
    ptcache, meta = {}, weakkey{}

    -- Patterns with aux only.
    for _, p in ipairs(patternwith.aux) do
        ptcache[p] = weakval{}
    end

    -- Patterns with only one sub-pattern.
    for _, p in ipairs(patternwith.subpt) do
        ptcache[p] = weakval{}
    end

    -- Patterns with both
    for _, p in ipairs(patternwith.both) do
        ptcache[p] = {}
    end

    return ptcache
end
LL.resetptcache = resetcache

resetcache()


-------------------------------------------------------------------------------
--- Individual pattern constructor
--

local constructors = {}
Builder.constructors = constructors

constructors["constant"] = {
    truept  = newpattern{ ptype = "true" },
    falsept = newpattern{ ptype = "false" },
    Cppt    = newpattern{ ptype = "Cp" }
}

-- data manglers that produce cache keys for each aux type.
-- `id()` for unspecified cases.
local getauxkey = {
    string = function(aux, as_is) return as_is end,
    table = copy,
    set = function(aux, as_is)
        return S_tostring(aux)
    end,
    range = function(aux, as_is)
        return t_concat(as_is, "|")
    end,
    sequence = function(aux, as_is) 
        return t_concat(map(getuniqueid, aux),"|") 
    end
}

getauxkey.choice = getauxkey.sequence

constructors["aux"] = function(typ, aux, as_is)
     -- dprint("CONS: ", typ, pt, aux, as_is)
    local cache = ptcache[typ]
    local key = (getauxkey[typ] or id)(aux, as_is)
    if not cache[key] then
        cache[key] = newpattern{
            ptype = typ,
            aux = aux,
            as_is = as_is
        }
    end
    return cache[key]
end

-- no cache for grammars
constructors["none"] = function(typ, aux)
    -- [[DBG]] print("CONS: ", typ, _, aux)
    -- [[DBG]] print(debug.traceback(1))
    return newpattern{
        ptype = typ,
        aux = aux
    }
end

constructors["subpt"] = function(typ, pt)
    -- [[DP]]print("CONS: ", typ, pt, aux) 
    local cache = ptcache[typ]
    if not cache[pt] then
        cache[pt] = newpattern{
            ptype = typ,
            pattern = pt
        }
    end
    return cache[pt]
end

constructors["both"] = function(typ, pt, aux)
     -- dprint("CONS: ", typ, pt, aux)
    local cache = ptcache[typ][aux]
    if not cache then
        ptcache[typ][aux] = weakval{}
        cache = ptcache[typ][aux]
    end
    if not cache[pt] then
        cache[pt] = newpattern{
            ptype = typ,
            pattern = pt,
            aux = aux,
            cache = cache -- needed to keep the cache as long as the pattern exists.
        }
    end
    return cache[pt]
end

end -- module wrapper

--                   The Romantic WTF public license.
--                   --------------------------------
--                   a.k.a. version "<3" or simply v3
--
--
--            Dear user,
--
--            The LuLPeg library
--
--                                             \ 
--                                              '.,__
--                                           \  /
--                                            '/,__
--                                            /
--                                           /
--                                          /
--                       has been          / released
--                  ~ ~ ~ ~ ~ ~ ~ ~       ~ ~ ~ ~ ~ ~ ~ ~ 
--                under  the  Romantic   WTF Public License.
--               ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~`,´ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ 
--               I hereby grant you an irrevocable license to
--                ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
--                  do what the gentle caress you want to
--                       ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~  
--                           with   this   lovely
--                              ~ ~ ~ ~ ~ ~ ~ ~ 
--                               / thing...
--                              /  ~ ~ ~ ~
--                             /    Love,
--                        #   /      '.'
--                        #######      ·
--                        #####
--                        ###
--                        #
--
--            -- Pierre-Yves
--
--
--            P.S.: Even though I poured my heart into this work, 
--                  I _cannot_ provide any warranty regarding 
--                  its fitness for _any_ purpose. You
--                  acknowledge that I will not be held liable
--                  for any damage its use could incur.
