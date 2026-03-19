//
//  LRUMemoryCache.swift
//  Mihon IOS
//

import Foundation
import UIKit

// MARK: - Cache Configuration

struct CacheConfiguration: Codable, Hashable {
    var imageCountLimit: Int
    var imageBytesLimit: Int
    var dataCountLimit: Int
    var dataBytesLimit: Int
    var diskImageBytesLimit: Int
    var diskMetadataBytesLimit: Int
    var diskNetworkBytesLimit: Int

    static let `default` = CacheConfiguration(
        imageCountLimit: 100,
        imageBytesLimit: 80 * 1_024 * 1_024,
        dataCountLimit: 200,
        dataBytesLimit: 40 * 1_024 * 1_024,
        diskImageBytesLimit: 200 * 1_024 * 1_024,
        diskMetadataBytesLimit: 32 * 1_024 * 1_024,
        diskNetworkBytesLimit: 80 * 1_024 * 1_024
    )
}

// MARK: - LRU Memory Cache

/// A generic, thread-safe LRU cache backed by `NSCache` with a doubly-linked
/// list to maintain access order. Automatically responds to memory pressure
/// by evicting the least-recently-used half of its entries.
final class LRUMemoryCache<Key: Hashable, Value: AnyObject>: @unchecked Sendable {

    // MARK: - Linked List Node

    private final class Node {
        let key: Key
        var value: Value
        var cost: Int
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value, cost: Int) {
            self.key = key
            self.value = value
            self.cost = cost
        }
    }

    // MARK: - Properties

    private var map: [Key: Node] = [:]
    private var head: Node?  // most recently used
    private var tail: Node?  // least recently used

    private let lock = NSLock()
    private var _countLimit: Int
    private var _totalCostLimit: Int
    private var _totalCost: Int = 0
    private var memoryWarningObserver: NSObjectProtocol?

    var onEvict: ((Key) -> Void)?

    // MARK: - Public interface

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return map.count
    }

    var totalCost: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalCost
    }

    var countLimit: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _countLimit
        }
        set {
            lock.lock()
            _countLimit = newValue
            lock.unlock()
            evictIfNeeded()
        }
    }

    var totalCostLimit: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _totalCostLimit
        }
        set {
            lock.lock()
            _totalCostLimit = newValue
            lock.unlock()
            evictIfNeeded()
        }
    }

    // MARK: - Init

    init(countLimit: Int, totalCostLimit: Int) {
        self._countLimit = countLimit
        self._totalCostLimit = totalCostLimit

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.trimToFraction(0.5)
        }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Access

    func object(forKey key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let node = map[key] else { return nil }
        moveToHead(node)
        return node.value
    }

    func setObject(_ value: Value, forKey key: Key, cost: Int = 0) {
        lock.lock()
        if let existing = map[key] {
            _totalCost -= existing.cost
            existing.value = value
            existing.cost = cost
            _totalCost += cost
            moveToHead(existing)
            lock.unlock()
        } else {
            let node = Node(key: key, value: value, cost: cost)
            map[key] = node
            addToHead(node)
            _totalCost += cost
            lock.unlock()
        }
        evictIfNeeded()
    }

    func removeObject(forKey key: Key) {
        removeObject(forKey: key, notify: true)
    }

    func removeAllObjects() {
        lock.lock()
        map.removeAll()
        head = nil
        tail = nil
        _totalCost = 0
        lock.unlock()
    }

    /// Returns the set of all keys currently in the cache.
    func allKeys() -> Set<Key> {
        lock.lock()
        defer { lock.unlock() }
        return Set(map.keys)
    }

    /// Evict the least-recently-used fraction of entries (e.g. 0.5 = remove half).
    func trimToFraction(_ fraction: Double) {
        lock.lock()
        let targetCount = max(Int(Double(map.count) * (1.0 - fraction)), 0)
        while map.count > targetCount, let lru = tail {
            removeNode(lru)
            map[lru.key] = nil
            _totalCost -= lru.cost
        }
        lock.unlock()
    }

    // MARK: - Linked List Helpers

    private func addToHead(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
    }

    private func removeNode(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if head === node { head = node.next }
        if tail === node { tail = node.prev }
        node.prev = nil
        node.next = nil
    }

    private func moveToHead(_ node: Node) {
        guard head !== node else { return }
        removeNode(node)
        addToHead(node)
    }

    // MARK: - Eviction

    private func evictIfNeeded() {
        lock.lock()
        while map.count > _countLimit, let lru = tail {
            let key = lru.key
            removeNode(lru)
            map[key] = nil
            _totalCost -= lru.cost
            let callback = onEvict
            lock.unlock()
            callback?(key)
            lock.lock()
        }
        while _totalCost > _totalCostLimit, let lru = tail {
            let key = lru.key
            removeNode(lru)
            map[key] = nil
            _totalCost -= lru.cost
            let callback = onEvict
            lock.unlock()
            callback?(key)
            lock.lock()
        }
        lock.unlock()
    }

    private func removeObject(forKey key: Key, notify: Bool) {
        lock.lock()
        guard let node = map[key] else {
            lock.unlock()
            return
        }
        removeNode(node)
        map[key] = nil
        _totalCost -= node.cost
        let callback = notify ? onEvict : nil
        lock.unlock()
        callback?(key)
    }
}
