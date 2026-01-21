# LibCuckooFilter

Cuckoo Filter for WoW Lua 5.1 environment - Probabilistic set membership testing with minimal memory footprint.

## Features

- Efficiently tests whether an element is a member of a set.
- Low memory usage, suitable for constrained environments.
- Simple API for adding and checking elements.
- Compatible with World of Warcraft Lua 5.1 environment.

## Installation

To install LibCuckooFilter, simply download the `LibCuckooFilter.lua` file and include it in your WoW addon folder. Then, you can load it using LibStub in your addon code.

```lua
local LibCuckooFilter = LibStub("LibCuckooFilter")
```

## Usage

```lua
-- Create a new Cuckoo Filter with expected 1000 values
local filter = LibCuckooFilter.New(1000)

-- Add values to the filter
for i = 1, 1000 do
    filter:Insert("value" .. i)
end

-- Check for membership
for i = 1, 1200 do
    local value = "value" .. i
    if filter:Contains(value) then
        print(value .. " is possibly in the set.")
    else
        print(value .. " is definitely not in the set.")
    end
end

-- Export the filter state, so you can serialize it
local state = filter:Export()

-- Import the filter state into a new filter
local newFilter = LibCuckooFilter.Import(state)
```

## API

### LibCuckooFilter.New(capacity, bucketSize, fingerprintBits, maxKicks)

Creates a new Cuckoo Filter instance.

- `capacity`: Capacity of the Cuckoo Filter (expected number of values).
- `bucketSize`: (Optional) Number of entries per bucket (default: 4).
- `fingerprintBits`: (Optional) Number of bits per fingerprint (default: 12).
- `maxKicks`: (Optional) Maximum number of kicks during insertion (default: 512).
- Returns: A new Cuckoo Filter instance.

### filter:Insert(value)

Insert a value into the Cuckoo Filter.

- `value`: The value to insert (any).

### filter:Contains(value)

Determine if a value is possibly in the Cuckoo Filter.

- `value`: The value to check (any).
- Returns: `true` if the value is possibly in the set, `false` if definitely not.

### filter:Delete(value)

Delete a value from the cuckoo filter.

- `value`: The value to delete (any).

### filter:Export()

Export the current state of the Cuckoo Filter.

- Returns: A compact representation of the Cuckoo Filter state.

### LibCuckooFilter.Import(state)

Import the Cuckoo Filter state from a compact representation.

- `state`: A compact representation of the Cuckoo Filter state.
- Returns: A new Cuckoo Filter instance.

### filter:Clear()

Clear all values from the Cuckoo Filter.

### filter:GetFalsePositiveRate()

Estimate the current false positive rate of the patterned bloom filter.

- Returns: Estimated false positive rate (number).

## License

This library is released under the MIT License. See the LICENSE file for details.
