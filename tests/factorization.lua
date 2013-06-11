require"lulpeg":global(_G or _ENV)

-- print"cache"

assert(P"a" == P"a")
assert(S"ab" == S"ab")
assert(R("ac","em") == R("ac","em"))
assert(P"a"^0 == P"a"^0)
assert(R"AZ" == R"AZ")
assert(S"AB" == S"AB")

-- print"booleans"

assert(P(true) + true + true == P(true))
assert(P(false) + false + false == P(false))
assert(P"" == P(true))
assert(S"" == P(false))
assert(R() == P(false))


-- print"unm"

assert(P(true) == -P(false))
assert(-P(true) == P(false))
assert(- -P"a" == #P"a")
assert(-#P"a" == -P"a")
assert(P(-1) == -P(1))

-- print"strings"

assert(P"a" * P"b" == P"ab")
assert(P"" * "a" == P"a")
assert(P"a" * "" == P"a")

-- print"distributivity"

assert(C(P"A" + P"B") == C"A" + C"B")
assert( not (C(P"A" * P"B") == C"A" * C"B"))
assert( not (C(P"A" + P"B") == C"A" + C"C"))
assert(P"A"/1 + P"B"/1 == (P"A" + P"B")/1)

-- print"set and range unions"

assert(R"az"+R"AZ" == R("az", "AZ"))

-- print"captures"
-- local e = _G or _ENV

-- for _, v in ipairs{"C", "Cg", "C"} do end

print"Ok"