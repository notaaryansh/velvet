//
//  OrderedDictionary+insertSorted.swift
//
//  Created by Quirin Schweigert on 15.04.24.
//

import OrderedCollections

public extension OrderedDictionary {
    /// Inserts a new key-value pair into the dictionary in a sorted order.
    mutating func insertSorted(_ value: Value, forKey key: Key, by areInIncreasingOrder: (Key, Key) -> Bool) {
        let index = self.keys.binarySearchIndex(for: key, by: areInIncreasingOrder)
        if index < count && keys[index] == key {
            self.updateValue(value, forKey: key, insertingAt: index)
        } else {
            self.updateValue(value, forKey: key, insertingAt: index)
        }
    }

    mutating func insertSorted(
        _ value: Value,
        forKey key: Key,
        comparingValuesBy areInIncreasingOrder: (Value, Value) -> Bool
    ) {
        let index = self.values.binarySearchIndex(for: value, by: areInIncreasingOrder)
        if index < count && keys[index] == key {
            print("insert sorted inserting at \(index) (\(self.keys.indices.first.map { "\($0)" } ?? "–") - \(self.keys.indices.last.map { "\($0)" } ?? "–"))")
            self.updateValue(value, forKey: key, insertingAt: index)
        } else {
            self.updateValue(value, forKey: key, insertingAt: index)
        }
    }

    mutating func appendOrInsertSorted(
        _ value: Value,
        forKey key: Key,
        comparingValuesBy areInIncreasingOrder: (Value, Value) -> Bool
    ) {
        if let lastValue = values.last, areInIncreasingOrder(lastValue, value) {
            /// Note: subscript appends new element at the end. Default (fast) case.
            self[key] = value
        } else {
            insertSorted(
                value,
                forKey: key,
                comparingValuesBy: areInIncreasingOrder
            )
        }
    }
}

public extension OrderedDictionary where Key: Comparable {
    mutating func insertSorted(_ value: Value, forKey key: Key) {
        insertSorted(value, forKey: key, by: { $0 < $1 })
    }
}

public extension Collection {
    /// Performs a binary search on a sorted collection and returns the index where the element should be inserted.
    func binarySearchIndex(for value: Element, by areInIncreasingOrder: (Element, Element) -> Bool) -> Index {
        var lowerBound = startIndex
        var upperBound = endIndex

        while lowerBound < upperBound {
            let midIndex = index(lowerBound, offsetBy: distance(from: lowerBound, to: upperBound) / 2)
            if areInIncreasingOrder(self[midIndex], value) {
                lowerBound = index(after: midIndex)
            } else {
                upperBound = midIndex
            }
        }

        return lowerBound
    }
}
