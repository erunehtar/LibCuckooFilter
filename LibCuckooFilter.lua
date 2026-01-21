-- MIT License
--
-- Copyright (c) 2026 Erunehtar
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--
--
-- Cuckoo Filter implementation for WoW Lua 5.1 environment.
-- Based on: "Cuckoo Filter: Practically Better Than Bloom" (Fan et al., 2014)
--
-- Credits:
--   The Cuckoo filter was invented by Bin Fan, David G. Andersen, Michael Kaminsky,
--   and Michael D. Mitzenmacher.
--
-- Optimized for 32-bit Lua environment with partial-key Cuckoo hashing.
-- Uses FNV-1a hash function and bidirectional XOR-based alternate bucket calculation.
-- Supports insertion, membership testing, deletion, clear, export/import, and false positive rate estimation.

local MAJOR, MINOR = "LibCuckooFilter", 3
assert(LibStub, MAJOR .. " requires LibStub")

local LibCuckooFilter = LibStub:NewLibrary(MAJOR, MINOR)
if not LibCuckooFilter then return end -- no upgrade needed

-- Local lua references
local assert, type, setmetatable, pairs, ipairs = assert, type, setmetatable, pairs, ipairs
local band, bxor, rshift = bit.band, bit.bxor, bit.rshift
local ceil, log, exp, random = math.ceil, math.log, math.exp, fastrandom
local tostring, strbyte = tostring, strbyte
local tinsert, tremove = table.insert, table.remove

-- Constants
local LOG2 = log(2)                 -- Natural log of 2
local UINT32_MODULO = 2 ^ 32        -- Modulo for 32-bit arithmetic
local DEFAULT_SEED = 0              -- Default seed for hash function
local DEFAULT_BUCKET_SIZE = 4       -- Default entries per bucket
local DEFAULT_FINGERPRINT_BITS = 12 -- Default bits per fingerprint
local DEFAULT_MAX_KICKS = 512       -- Default maximum kicks during insertion

--- Helper function: Find next power of 2
--- @param value integer Input number.
--- @return integer powerOfTwo Next power of two greater than or equal to value.
local function NextPowerOfTwo(value)
    if value == 0 then
        return 1
    end
    return 2 ^ ceil(log(value) / LOG2)
end

--- FNV-1a hash function (32-bit)
--- @param value string Input string to hash.
--- @param seed integer? Seed value.
--- @return integer hash 32-bit hash value.
local function FNV1a32(value, seed)
    local str = tostring(value)
    local len = #str
    local hash = 2166136261 + (seed or 0) * 13
    for i = 1, len do
        hash = bxor(hash, strbyte(str, i))
        hash = (hash * 16777619) % UINT32_MODULO
    end
    return hash
end

--- Compute the fingerprint of a value.
--- @param value any Value to compute the fingerprint for.
--- @return integer fingerprint The computed fingerprint.
local function Fingerprint(self, value)
    -- Use upper bits of hash for fingerprint to reduce correlation with bucket index
    local h = FNV1a32(value, self.seed)
    local fp = band(rshift(h, 16), self.fingerprintMask)
    return fp == 0 and 1 or fp
end

--- Compute the bucket index for a given hash.
--- @param hash integer Hash value.
--- @return integer index The computed bucket index (1-based).
local function BucketIndex(self, hash)
    return (hash % self.numBuckets) + 1
end

--- Compute the alternate bucket index for a given index and fingerprint.
--- Uses partial-key Cuckoo hashing: i' = (i XOR hash(fp)) mod numBuckets
--- This is bidirectional: alternate(alternate(i, fp), fp) = i
--- @param index integer Original bucket index (1-based).
--- @param fingerprint integer Fingerprint value.
--- @return integer altIndex The computed alternate bucket index (1-based).
local function AlternateBucketIndex(self, index, fingerprint)
    -- Mix the fingerprint to get a hash value
    local h = fingerprint * 0x5bd1e995
    h = bxor(h, rshift(h, 15))

    -- Keep hash in valid bucket range for XOR operation
    h = h % self.numBuckets

    -- XOR with 0-based index (both values now in [0, numBuckets-1])
    -- Apply modulo to keep XOR result in valid range while maintaining bidirectionality
    local alt = bxor((index - 1) % self.numBuckets, h) % self.numBuckets

    -- Map back to 1-based bucket index
    return alt + 1
end

--- @class LibCuckooFilter Cuckoo Filter data structure.
--- @field New fun(capacity: integer, seed: integer?, bucketSize: number?, fingerprintBits: integer?, maxKicks: integer?): LibCuckooFilter
--- @field Insert fun(self: LibCuckooFilter, value: any): boolean
--- @field Contains fun(self: LibCuckooFilter, value: any): boolean
--- @field Delete fun(self: LibCuckooFilter, value: any): boolean
--- @field Clear fun(self: LibCuckooFilter)
--- @field Export fun(self: LibCuckooFilter): integer[]
--- @field Import fun(state: integer[]): LibCuckooFilter
--- @field EstimateFalsePositiveRate fun(self: LibCuckooFilter): number
--- @field numBuckets integer Number of buckets in the filter.
--- @field bucketSize integer Number of entries per bucket.
--- @field fingerprintBits integer Number of bits per fingerprint.
--- @field fingerprintMask integer Bitmask for fingerprint extraction.
--- @field buckets table<integer, integer[]> Table of buckets (each bucket is an array of fingerprints).
--- @field itemCount integer Number of items currently stored.
--- @field maxKicks integer Maximum number of kicks during insertion.

--- @class LibCuckooFilterState Compact representation of a Cuckoo Filter state.
--- @field [1] integer Seed for the hash function.
--- @field [2] integer Number of buckets in the filter.
--- @field [3] integer Number of entries per bucket.
--- @field [4] integer Number of bits per fingerprint.
--- @field [5] integer Maximum number of kicks during insertion.
--- @field [6] table<integer, integer[]> Table of non-empty buckets (each bucket is an array of fingerprints).

LibCuckooFilter.__index = LibCuckooFilter

--- Create a new Cuckoo Filter instance.
--- @param capacity integer Capacity of the filter (expected number of values).
--- @param seed integer? Seed for the hash function (default: 0).
--- @param bucketSize integer? Number of entries per bucket (default: 4).
--- @param fingerprintBits integer? Number of bits per fingerprint (default: 12).
--- @param maxKicks integer? Maximum number of kicks during insertion (default: 512).
--- @return LibCuckooFilter instance The new Cuckoo Filter instance.
function LibCuckooFilter.New(capacity, seed, bucketSize, fingerprintBits, maxKicks)
    assert(capacity and capacity > 0, "capacity must be greater than 0")
    seed = seed or DEFAULT_SEED
    assert(type(seed) == "number", "seed must be a number")
    bucketSize = bucketSize or DEFAULT_BUCKET_SIZE
    assert(bucketSize > 0, "bucketSize must be positive")
    fingerprintBits = fingerprintBits or DEFAULT_FINGERPRINT_BITS
    assert(fingerprintBits > 0 and fingerprintBits <= 16, "fingerprintBits must be between 1 and 16")
    maxKicks = maxKicks or DEFAULT_MAX_KICKS

    -- Important: numBuckets must be power of 2 for XOR-based alternate bucket to work
    local numBuckets = NextPowerOfTwo(ceil(capacity / bucketSize))
    return setmetatable({
        seed = seed,
        numBuckets = numBuckets,
        bucketSize = bucketSize,
        fingerprintBits = fingerprintBits,
        fingerprintMask = (2 ^ fingerprintBits) - 1,
        buckets = {},
        itemCount = 0,
        maxKicks = maxKicks,
    }, LibCuckooFilter)
end

--- Insert a value into the filter.
--- @param value any Value to insert.
--- @return boolean success True if insertion succeeded, false if the filter is full.
function LibCuckooFilter:Insert(value)
    assert(value ~= nil, "value cannot be nil")
    local fingerprint = Fingerprint(self, value)
    local hash = FNV1a32(value, self.seed)
    local i1 = BucketIndex(self, hash)
    local i2 = AlternateBucketIndex(self, i1, fingerprint)

    -- Try first bucket
    local bucket = self.buckets[i1]
    if not bucket then
        self.buckets[i1] = { fingerprint }
        self.itemCount = self.itemCount + 1
        return true
    elseif #bucket < self.bucketSize then
        tinsert(bucket, fingerprint)
        self.itemCount = self.itemCount + 1
        return true
    end

    -- Try alternate bucket
    bucket = self.buckets[i2]
    if not bucket then
        self.buckets[i2] = { fingerprint }
        self.itemCount = self.itemCount + 1
        return true
    elseif #bucket < self.bucketSize then
        tinsert(bucket, fingerprint)
        self.itemCount = self.itemCount + 1
        return true
    end

    -- Both full, relocate using Cuckoo eviction
    local evictIndex = (hash % 2 == 0) and i1 or i2
    local evictFp = fingerprint

    for kick = 1, self.maxKicks do
        -- Randomly pick a position in the bucket to evict
        local bucket = self.buckets[evictIndex]
        local pos = random(self.bucketSize)
        evictFp, bucket[pos] = bucket[pos], evictFp

        -- Compute alternate bucket for the evicted fingerprint
        evictIndex = AlternateBucketIndex(self, evictIndex, evictFp)

        -- Check if alternate bucket has space
        bucket = self.buckets[evictIndex]
        if not bucket then
            self.buckets[evictIndex] = { evictFp }
            self.itemCount = self.itemCount + 1
            return true
        elseif #bucket < self.bucketSize then
            tinsert(bucket, evictFp)
            self.itemCount = self.itemCount + 1
            return true
        end
        -- Alternate bucket is full, continue eviction loop
    end

    return false -- Filter full after max kicks
end

--- Determine if a value is possibly in the filter.
--- @param value any Value to check.
--- @return boolean contains True if value might be in the set, false if definitely not.
function LibCuckooFilter:Contains(value)
    assert(value ~= nil, "value cannot be nil")
    local fingerprint = Fingerprint(self, value)
    local hash = FNV1a32(value, self.seed)
    local i1 = BucketIndex(self, hash)
    local i2 = AlternateBucketIndex(self, i1, fingerprint)

    local bucket = self.buckets[i1]
    if bucket then
        for _, fp in ipairs(bucket) do
            if fp == fingerprint then return true end
        end
    end

    bucket = self.buckets[i2]
    if bucket then
        for _, fp in ipairs(bucket) do
            if fp == fingerprint then return true end
        end
    end

    return false
end

--- Delete a value from the filter.
--- Note: May cause false negatives if the same fingerprint was inserted multiple times.
--- @param value any Value to delete.
--- @return boolean success True if deletion succeeded, false if value not found.
function LibCuckooFilter:Delete(value)
    assert(value ~= nil, "value cannot be nil")
    local fingerprint = Fingerprint(self, value)
    local hash = FNV1a32(value, self.seed)
    local i1 = BucketIndex(self, hash)
    local i2 = AlternateBucketIndex(self, i1, fingerprint)

    -- Try first bucket
    local bucket = self.buckets[i1]
    if bucket then
        for i, fp in ipairs(bucket) do
            if fp == fingerprint then
                tremove(bucket, i)
                self.itemCount = self.itemCount - 1
                if #bucket == 0 then
                    self.buckets[i1] = nil
                end
                return true
            end
        end
    end

    -- Try alternate bucket
    bucket = self.buckets[i2]
    if bucket then
        for i, fp in ipairs(bucket) do
            if fp == fingerprint then
                tremove(bucket, i)
                self.itemCount = self.itemCount - 1
                if #bucket == 0 then
                    self.buckets[i2] = nil
                end
                return true
            end
        end
    end

    return false -- Fingerprint not found
end

--- Clear all values from the filter.
function LibCuckooFilter:Clear()
    self.buckets = {}
    self.itemCount = 0
end

--- Export the current state of the filter.
--- @return LibCuckooFilterState state Compact representation of the filter.
function LibCuckooFilter:Export()
    local state = {}
    state[1] = self.seed
    state[2] = self.numBuckets
    state[3] = self.bucketSize
    state[4] = self.fingerprintBits
    state[5] = self.maxKicks

    local nonEmptyBuckets = {} --- @type table<integer, integer[]>
    for bucketIdx, bucket in pairs(self.buckets) do
        if #bucket > 0 then
            nonEmptyBuckets[bucketIdx] = bucket
        end
    end
    state[6] = nonEmptyBuckets

    return state
end

--- Import a new Cuckoo Filter from a compact representation.
--- @param state LibCuckooFilterState Compact representation of the filter.
--- @return LibCuckooFilter instance The imported Cuckoo Filter instance.
function LibCuckooFilter.Import(state)
    assert(state and type(state) == "table", "state must be a table")
    assert(state[1] ~= nil, "invalid seed in state")
    assert(state[2] and state[2] > 0, "invalid numBuckets in state")
    assert(state[3] and state[3] > 0, "invalid bucketSize in state")
    assert(state[4] and state[4] > 0, "invalid fingerprintBits in state")
    assert(state[5] and state[5] > 0, "invalid maxKicks in state")
    assert(state[6] and type(state[6]) == "table", "invalid buckets in state")
    local seed = state[1]
    local numBuckets = state[2]
    local bucketSize = state[3]
    local fingerprintBits = state[4]
    local maxKicks = state[5]
    local buckets = state[6]

    -- Recalculate fingerprint mask
    local fingerprintMask = (2 ^ fingerprintBits) - 1

    -- Recalculate item count
    local itemCount = 0
    for _, bucket in pairs(buckets) do
        itemCount = itemCount + #bucket
    end

    return setmetatable({
        seed = seed,
        numBuckets = numBuckets,
        bucketSize = bucketSize,
        fingerprintBits = fingerprintBits,
        fingerprintMask = fingerprintMask,
        buckets = buckets,
        itemCount = itemCount,
        maxKicks = maxKicks,
    }, LibCuckooFilter)
end

--- Estimate the current false positive rate (FPR) of the filter based on current load factor.
--- @return number fpr Estimated false positive rate.
function LibCuckooFilter:EstimateFalsePositiveRate()
    local loadFactor = self.itemCount / (self.numBuckets * self.bucketSize)
    if loadFactor >= 1 then
        return 1.0 -- Filter is full, FPR is 100%
    end
    return (1 - exp(-2 * loadFactor)) ^ 2
end

-------------------------------------------------------------------------------
-- TESTS: Verify Cuckoo Filter correctness
-------------------------------------------------------------------------------

--[[ -- Uncomment to run tests when loading this file

local function RunLibCuckooFilterTests()
    print("=== LibCuckooFilter Tests ===")

    -- Test 1: Basic insertion and membership
    local cf = LibCuckooFilter.New(100)
    assert(not cf:Contains("item1"), "Test 1 Failed: Empty filter should not contain items")

    assert(cf:Insert("item1"), "Test 1 Failed: Should insert item1")
    assert(cf:Insert("item2"), "Test 1 Failed: Should insert item2")
    assert(cf:Insert("item3"), "Test 1 Failed: Should insert item3")
    assert(cf:Contains("item1"), "Test 1 Failed: Should contain inserted item1")
    assert(cf:Contains("item2"), "Test 1 Failed: Should contain inserted item2")
    assert(cf:Contains("item3"), "Test 1 Failed: Should contain inserted item3")
    print("Test 1 PASSED: Basic insertion and membership")

    -- Test 2: Deletion (unique feature of Cuckoo Filter)
    local cf2 = LibCuckooFilter.New(100)
    cf2:Insert("delete1")
    cf2:Insert("delete2")
    assert(cf2:Contains("delete1"), "Test 2 Failed: Should contain delete1")

    assert(cf2:Delete("delete1"), "Test 2 Failed: Should delete delete1")
    assert(not cf2:Contains("delete1"), "Test 2 Failed: Should not contain delete1 after deletion")
    assert(cf2:Contains("delete2"), "Test 2 Failed: Should still contain delete2")

    -- Deleting non-existent item should return false
    assert(not cf2:Delete("nonexistent"), "Test 2 Failed: Deleting non-existent should return false")
    print("Test 2 PASSED: Deletion functionality")

    -- Test 3: False positives vs true negatives
    local testCf = LibCuckooFilter.New(100000 * 1.5) -- avoid high load
    for i = 1, 50000 do
        local item = "test_" .. i
        testCf:Insert(item)
    end

    local falsePositives = 0
    local testCount = 100000
    for i = 50001, 50000 + testCount do
        local item = "test_" .. i
        if testCf:Contains(item) then
            falsePositives = falsePositives + 1
        end
    end

    local actualFPR = falsePositives / testCount
    local estimatedFPR = testCf:EstimateFalsePositiveRate()
    print(string.format("Test 3 PASSED: FP Rate - Actual: %.4f, Estimated: %.4f", actualFPR, estimatedFPR))
    assert(actualFPR < 0.05, "Test 3 Failed: False positive rate too high")

    -- Test 4: Export and Import
    local cf4 = LibCuckooFilter.New(100)
    for i = 1, 100 do
        cf4:Insert("export" .. i)
    end

    local exported = cf4:Export()
    local imported = LibCuckooFilter.Import(exported)

    for i = 1, 100 do
        assert(imported:Contains("export" .. i), "Test 4 Failed: Imported filter should contain export" .. i)
    end
    print("Test 4 PASSED: Export and Import")

    -- Test 5: Clear functionality
    local cf5 = LibCuckooFilter.New(100)
    cf5:Insert("clear1")
    cf5:Insert("clear2")
    assert(cf5:Contains("clear1"), "Test 5 Failed: Should contain clear1 before clear")

    cf5:Clear()
    assert(not cf5:Contains("clear1"), "Test 5 Failed: Should not contain clear1 after clear")
    assert(not cf5:Contains("clear2"), "Test 5 Failed: Should not contain clear2 after clear")
    print("Test 5 PASSED: Clear functionality")

    -- Test 6: No false negatives (critical property)
    local cf6 = LibCuckooFilter.New(100000 * 1.5) -- avoid high load
    local items = {}
    for i = 1, 100000 do
        items[i] = "item_" .. i
        assert(cf6:Insert(items[i]), "Test 6 Failed: Insert failed for " .. items[i])
    end

    for i = 1, 100000 do
        assert(cf6:Contains(items[i]), "Test 6 Failed: False negative detected for " .. items[i])
    end
    print("Test 6 PASSED: No false negatives")

    -- Test 7: Deletion doesn't affect other items
    local cf7 = LibCuckooFilter.New(100)
    cf7:Insert("keep1")
    cf7:Insert("keep2")
    cf7:Insert("remove1")
    cf7:Insert("keep3")

    cf7:Delete("remove1")

    assert(cf7:Contains("keep1"), "Test 7 Failed: keep1 should still be present")
    assert(cf7:Contains("keep2"), "Test 7 Failed: keep2 should still be present")
    assert(cf7:Contains("keep3"), "Test 7 Failed: keep3 should still be present")
    assert(not cf7:Contains("remove1"), "Test 7 Failed: remove1 should be deleted")
    print("Test 7 PASSED: Deletion isolation")

    -- Test 8: Different seeds produce different filters
    local pbf8a = LibCuckooFilter.New(100, 123)
    local pbf8b = LibCuckooFilter.New(100, 456)
    pbf8a:Insert("seed_test")
    pbf8b:Insert("seed_test")
    local export8a = pbf8a:Export()
    local export8b = pbf8b:Export()
    local export8aBuckets = export8a[6] --- @type table<integer, integer[]>
    local export8bBuckets = export8b[6] --- @type table<integer, integer[]>
    local different = false
    for bucketIdx, bucket in pairs(export8aBuckets) do
        local otherBucket = export8bBuckets[bucketIdx]
        if otherBucket then
            for i, fp in ipairs(bucket) do
                if fp ~= otherBucket[i] then
                    different = true
                    break
                end
            end
        else
            different = true
            break
        end
        if different then break end
    end

    assert(different, "Test 8 Failed: Filters with different seeds should differ")
    print("Test 8 PASSED: Different seeds produce different filters")

    print("=== All LibCuckooFilter Tests PASSED ===\n")
end

RunLibCuckooFilterTests()

]] --
