//
//  RuntimeCacheStore.swift
//  Mihon IOS
//

import Foundation

/// Main-actor LRU store for ephemeral runtime caches used by `AppModel`.
@MainActor
final class RuntimeCacheStore<Key: Hashable, Value> {
    private final class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    private var map: [Key: Node]
    private var head: Node?
    private var tail: Node?

    var countLimit: Int {
        didSet {
            countLimit = max(countLimit, 0)
            trimToLimit()
        }
    }

    init(countLimit: Int, seed: [Key: Value] = [:]) {
        self.countLimit = max(countLimit, 0)
        self.map = [:]

        for (key, value) in seed {
            let node = Node(key: key, value: value)
            map[key] = node
            addToHead(node)
        }
        trimToLimit()
    }

    var count: Int {
        map.count
    }

    func value(forKey key: Key) -> Value? {
        guard let node = map[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    func peekValue(forKey key: Key) -> Value? {
        map[key]?.value
    }

    func setValue(_ value: Value, forKey key: Key) {
        if let existing = map[key] {
            existing.value = value
            moveToHead(existing)
        } else {
            let node = Node(key: key, value: value)
            map[key] = node
            addToHead(node)
        }
        trimToLimit()
    }

    func removeValue(forKey key: Key) {
        guard let node = map[key] else { return }
        removeNode(node)
        map[key] = nil
    }

    func removeAll() {
        map.removeAll()
        head = nil
        tail = nil
    }

    func trimToFraction(_ fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        let targetCount = max(Int(Double(map.count) * (1.0 - clamped)), 0)
        while map.count > targetCount, let node = tail {
            removeValue(forKey: node.key)
        }
    }

    func snapshot() -> [Key: Value] {
        map.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = pair.value.value
        }
    }

    private func trimToLimit() {
        while map.count > countLimit, let node = tail {
            removeValue(forKey: node.key)
        }
    }

    private func addToHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil {
            tail = node
        }
    }

    private func removeNode(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if head === node {
            head = node.next
        }
        if tail === node {
            tail = node.prev
        }
        node.prev = nil
        node.next = nil
    }

    private func moveToHead(_ node: Node) {
        guard head !== node else { return }
        removeNode(node)
        addToHead(node)
    }
}
