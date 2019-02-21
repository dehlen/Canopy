//
//  SortedSet.swift
//  SortedSet
//
//  Created by Bradley Hilton on 2/19/16.
//  Copyright © 2016 Brad Hilton. All rights reserved.
//
/// An ordered collection of unique `Element` instances

public struct SortedSet<Element: Hashable & Comparable>: Hashable, RandomAccessCollection {

    public typealias Indices = DefaultIndices<SortedSet<Element>>

    private(set) var array: [Element]
    private(set) var set: Set<Element>

    /// Always zero, which is the index of the first element when non-empty.
    public var startIndex: Int {
        return array.startIndex
    }

    /// A "past-the-end" element index; the successor of the last valid
    /// subscript argument.
    public var endIndex: Int {
        return array.endIndex
    }

    public func index(after i: Int) -> Int {
        return array.index(after: i)
    }

    public func index(before i: Int) -> Int {
        return array.index(before: i)
    }

    public subscript(position: Int) -> Element {
        return array[position]
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(set)
    }

    public func indexOf(_ element: Element) -> Int? {
        guard set.contains(element) else { return nil }
        return indexOf(element, in: range)
    }

    var range: Range<Int> {
        return Range(uncheckedBounds: (startIndex, endIndex))
    }

    func indexOf(_ element: Element, in range: Range<Int>) -> Int {
        guard range.count > 2 else {
            return element == array[range.lowerBound] ? range.lowerBound : (range.upperBound - 1)
        }
        let middleIndex = (range.lowerBound + range.upperBound)/2
        let middle = self[middleIndex]
        if element < middle {
            return indexOf(element, in: range.lowerBound..<middleIndex)
        } else {
            return indexOf(element, in: middleIndex..<range.upperBound)
        }
    }

    /// Construct from an arbitrary sequence with elements of type `Element`.
    public init<S: Sequence>(_ s: S, presorted: Bool = false, noDuplicates: Bool = false) where S.Iterator.Element == Element {
        if noDuplicates {
            if presorted {
                (self.array, self.set) = (Array(s), Set(s))
            } else {
                (self.array, self.set) = (s.sorted(), Set(s))
            }
        } else {
            if presorted {
                (self.array, self.set) = collapse(s)
            } else {
                (self.array, self.set) = collapse(s.sorted())
            }
        }
    }

    /// Construct an empty SortedSet.
    public init() {
        self.array = []
        self.set = []
    }

    /// Insert a member into the sorted set.
    public mutating func insert(_ member: Element) {
        remove(member)
        set.insert(member)
        insert(member, into: range)
    }

    /// Remove the member from the sorted set and return it if it was present.
    @discardableResult
    public mutating func remove(_ member: Element) -> Element? {
        return set.remove(member).map { array.remove(at: indexOf($0, in: range)) }
    }

    private mutating func insert(_ member: Element, into range: Range<Int>) {
        if range.count == 0 {
            return array.insert(member, at: range.lowerBound)
        } else if member < self[range.lowerBound] {
            return array.insert(member, at: range.lowerBound)
        } else if member > self[range.upperBound - 1] {
            return array.insert(member, at: range.upperBound)
        } else if range.count == 2 {
            return array.insert(member, at: range.lowerBound + 1)
        } else  {
            let middleIndex = (range.lowerBound + range.upperBound)/2
            let middle = self[middleIndex]
            if member < middle {
                insert(member, into: range.lowerBound..<middleIndex)
            } else {
                insert(member, into: middleIndex..<range.upperBound)
            }
        }
    }

    /// Append elements of a finite sequence into this `SortedSet`.
    public mutating func formUnion<S : Sequence>(_ sequence: S) where S.Iterator.Element == Element {
        for member in sequence {
            insert(member)
        }
    }
}

private func collapse<Element: Hashable, S : Sequence>(_ s: S) -> ([Element], Set<Element>) where S.Iterator.Element == Element {
    var aSet = Set<Element>()
    return (s.filter { set(&aSet, contains: $0) }, aSet)
}

private func set<Element>(_ set: inout Set<Element>, contains element: Element) -> Bool {
    defer { set.insert(element) }
    return !set.contains(element)
}

public func ==<T>(lhs: SortedSet<T>, rhs: SortedSet<T>) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }
    for (lhs, rhs) in zip(lhs, rhs) where lhs != rhs {
        return false
    }
    return true
}

extension Array where Element: Comparable & Hashable {

    /// Cast SortedSet as an Array
    public init(_ sortedSet: SortedSet<Element>) {
        self = sortedSet.array
    }

}

extension Set where Element: Comparable {

    /// Cast SortedSet as a Set
    public init(_ sortedSet: SortedSet<Element>) {
        self = sortedSet.set
    }

}
