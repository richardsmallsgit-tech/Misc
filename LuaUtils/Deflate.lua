local Deflate = {}
local BitWriter = {}
BitWriter.__index = BitWriter
function BitWriter.new()
	return setmetatable({ bytes = {}, b = 0, n = 0 }, BitWriter)
end
function BitWriter:putBits(value, nbits)
	if nbits == 0 then
		return
	end
	self.b = self.b + ((value & ((1 << nbits) - 1)) << self.n)
	self.n = self.n + nbits
	while self.n >= 8 do
		self.bytes[#self.bytes + 1] = self.b & 0xff
		self.b = self.b >> 8
		self.n = self.n - 8
	end
end
function BitWriter:finish()
	if self.n > 0 then
		self.bytes[#self.bytes + 1] = self.b & 0xff
		self.b = 0
		self.n = 0
	end
	return self.bytes
end
local function huffmanCodes(depths, nvalues)
	local nbits = 1
	local blCount = {}
	for i = 0, 63 do
		blCount[i] = 0
	end
	for i = 0, nvalues - 1 do
		local d = (i < #depths) and depths[i + 1] or 0
		if d > nbits then
			nbits = d
		end
		blCount[d] = blCount[d] + 1
	end
	blCount[0] = 0
	local nextCode = {}
	for i = 0, nbits do
		nextCode[i] = 0
	end
	local code = 0
	for i = 1, nbits do
		code = (code + blCount[i - 1]) * 2
		nextCode[i] = code
	end
	local codes = {}
	for i = 0, nvalues - 1 do
		codes[i + 1] = { code = 0, len = 0 }
	end
	for i = 0, nvalues - 1 do
		local len = (i < #depths) and depths[i + 1] or 0
		if len > 0 then
			local c = nextCode[len]
			local rcode = 0
			for j = 1, len do
				rcode = rcode + (((c >> (j - 1)) & 1) << (len - j))
			end
			codes[i + 1] = { code = rcode, len = len }
			nextCode[len] = nextCode[len] + 1
		end
	end
	return codes
end
local function fixedLitDepths()
	local depths = {}
	local cnt = { 144, 112, 24, 8 }
	local dpt = { 8, 9, 7, 8 }
	local idx = 0
	for i = 1, 4 do
		for k = 1, cnt[i] do
			depths[idx + 1] = dpt[i]
			idx = idx + 1
		end
	end
	return depths
end
local lenBase =
	{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local lenExtra = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local distBase = {
	1,
	2,
	3,
	4,
	5,
	7,
	9,
	13,
	17,
	25,
	33,
	49,
	65,
	97,
	129,
	193,
	257,
	385,
	513,
	769,
	1025,
	1537,
	2049,
	3073,
	4097,
	6145,
	8193,
	12289,
	16385,
	24577,
}
local distExtra = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local function lengthToCode(len)
	for i = #lenBase - 1, 0, -1 do
		if len >= lenBase[i + 1] then
			return 256 + i + 1, lenExtra[i + 1], len - lenBase[i + 1]
		end
	end
	error("InvalidOperationException")
end
local function distanceToCode(dist)
	for i = #distBase - 1, 0, -1 do
		if dist >= distBase[i + 1] then
			return i, distExtra[i + 1], dist - distBase[i + 1]
		end
	end
	error("InvalidOperationException")
end
local minMatch = 3
local maxMatch = 258
local window = 32768
local maxChain = 32
local function tokenize(data)
	local n = #data
	local hashHead = {}
	local hashPrev = {}
	local function h3(p)
		if p + 2 < n then
			return (data[p + 1] << 16) | (data[p + 2] << 8) | data[p + 3]
		end
		return nil
	end
	local function insertHash(p)
		local key = h3(p)
		if key ~= nil then
			local prev = hashHead[key]
			if prev ~= nil then
				hashPrev[p] = prev
			else
				hashPrev[p] = nil
			end
			hashHead[key] = p
		end
	end
	local function findMatch(p)
		local key = h3(p)
		if key == nil then
			return 0, 0
		end
		local bestLen, bestDist = 0, 0
		local cand = hashHead[key]
		local has = cand ~= nil
		local chain = 0
		local limit = math.min(n - 1, p + maxMatch - 1)
		while has and chain < maxChain do
			if p - cand > window then
				break
			end
			local l = 0
			while p + l <= limit and data[cand + l + 1] == data[p + l + 1] do
				l = l + 1
			end
			if l > bestLen then
				bestLen = l
				bestDist = p - cand
				if l >= maxMatch then
					break
				end
			end
			local nxt = hashPrev[cand]
			has = nxt ~= nil
			cand = nxt or 0
			chain = chain + 1
		end
		if bestLen >= minMatch then
			return bestLen, bestDist
		end
		return 0, 0
	end
	local tokens = {}
	local pos = 0
	while pos < n do
		local mlen, mdist = 0, 0
		if pos + 2 < n then
			mlen, mdist = findMatch(pos)
		end
		if mlen >= minMatch then
			tokens[#tokens + 1] = { kind = "match", len = mlen, dist = mdist }
			for p2 = pos, pos + mlen - 1 do
				insertHash(p2)
			end
			pos = pos + mlen
		else
			tokens[#tokens + 1] = { kind = "lit", b = data[pos + 1] }
			insertHash(pos)
			pos = pos + 1
		end
	end
	return tokens
end
function Deflate.compress(data)
	local bw = BitWriter.new()
	bw:putBits(1, 1)
	bw:putBits(1, 2)
	local litCodes = huffmanCodes(fixedLitDepths(), 288)
	local distDepths = {}
	for i = 1, 32 do
		distDepths[i] = 5
	end
	local distCodes = huffmanCodes(distDepths, 32)
	if #data > 0 then
		for _, tok in ipairs(tokenize(data)) do
			if tok.kind == "lit" then
				local c = litCodes[tok.b + 1]
				bw:putBits(c.code, c.len)
			elseif tok.kind == "match" then
				local lcode, lxb, lxv = lengthToCode(tok.len)
				local lc = litCodes[lcode + 1]
				bw:putBits(lc.code, lc.len)
				bw:putBits(lxv, lxb)
				local dcode, dxb, dxv = distanceToCode(tok.dist)
				local dc = distCodes[dcode + 1]
				bw:putBits(dc.code, dc.len)
				bw:putBits(dxv, dxb)
			end
		end
	end
	local eob = litCodes[256 + 1]
	bw:putBits(eob.code, eob.len)
	return bw:finish()
end
return Deflate
