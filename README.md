# LibCuckooFilter

Cuckoo Filter for WoW Lua 5.1 environment - Probabilistic set membership testing with minimal memory footprint.

## Features

- Efficiently tests whether an element is a member of a set.
- Low memory usage, suitable for constrained environments.
- Simple API for adding and checking elements.
- Compatible with World of Warcraft Lua 5.1 environment.

## Performance Comparison

Measured on an AMD Ryzen 9 5900X with 10,000 samples using random strings of length 12.

Smaller time is better. The fastest result is shown in **bold**.

| New | Median | Average | Min | Max | Total |
| - | - | - | - | - | - |
| LibBloomFilter | 58.40us | 60.38us | 41.70us | 966.10us | 603.75ms |
| LibPatternedBloomFilter | 508.90us | 572.17us | 366.00us | 3.88ms | 5721.69ms |
| **LibCuckooFilter** | 1.00us | 1.34us | 0.70us | 122.60us | 13.41ms |

| Insert | Median | Average | Min | Max | Total |
| - | - | - | - | - | - |
| LibBloomFilter | 11.80us | 15.28us | 11.40us | 160.00us | 152.76ms |
| **LibPatternedBloomFilter** | 2.20us | 2.22us | 2.00us | 19.20us | 22.23ms |
| LibCuckooFilter | 3.80us | 3.90us | 3.50us | 59.70us | 38.97ms |

| Contains | Median | Average | Min | Max | Total |
| - | - | - | - | - | - |
| LibBloomFilter | 11.70us | 11.80us | 11.50us | 29.60us | 117.96ms |
| **LibPatternedBloomFilter** | 2.20us | 2.19us | 2.00us | 15.20us | 21.94ms |
| LibCuckooFilter | 3.80us | 3.90us | 3.60us | 16.00us | 39.03ms |

| Export | Median | Average | Min | Max | Total |
| - | - | - | - | - | - |
| **LibBloomFilter** | 0.40us | 0.39us | 0.20us | 12.80us | 3.88ms |
| LibPatternedBloomFilter | 0.40us | 0.40us | 0.30us | 1.90us | 4.01ms |
| LibCuckooFilter | 707.90us | 756.49us | 571.10us | 2.75ms | 7564.90ms |

| Import | Median | Average | Min | Max | Total |
| - | - | - | - | - | - |
| **LibBloomFilter** | 0.90us | 0.88us | 0.70us | 3.60us | 8.84ms |
| LibPatternedBloomFilter | 406.20us | 448.20us | 319.10us | 2.87ms | 4482.02ms |
| LibCuckooFilter | 334.10us | 336.10us | 324.70us | 712.90us | 3361.02ms |

## Export Size Comparison

Measured by exporting the filter state after inserting 10,000 values, then serializing with LibSerialize and compressing with LibDeflate.

Smaller is better. The smallest result is shown in **bold**.

| Export Size | Serialized (Per Value) | Compressed (Per Value) |
| - | - | - |
| LibBloomFilter | 14.63KB (~1.50B) | 13.12KB (~1.35B) |
| **LibPatternedBloomFilter** | 14.43KB (~1.48B) | 12.34KB (~1.26B) |
| LibCuckooFilter | 35.88KB (~3.67B) | 30.09KB (~3.08B) |

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
