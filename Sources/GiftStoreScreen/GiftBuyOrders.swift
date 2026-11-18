import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramStringFormatting

// Buy Orders (concept): standing orders to buy any gift of a collection at a set price, shown as the collection's
// order book on its resale market. There is no server API for them yet, so the book is put together on the device:
// a few sample buyers bidding just under the collection's cheapest listing, plus the orders you place yourself, which
// are kept in UserDefaults for each gift type. Placing an order, cancelling it or selling to an order changes only
// this local book: no Stars and no gifts move.

enum GiftBuyOrderCondition: Equatable {
    case any
    case model(String)
    case backdrop(String)
    
    var title: String {
        switch self {
        case .any:
            return "Any model"
        case let .model(name):
            return "Model: \(name)"
        case let .backdrop(name):
            return "Backdrop: \(name)"
        }
    }
    
    func matches(_ gift: StarGift.UniqueGift) -> Bool {
        switch self {
        case .any:
            return true
        case let .model(name):
            return gift.attributes.contains(where: { attribute in
                if case let .model(modelName, _, _, _) = attribute {
                    return modelName == name
                }
                return false
            })
        case let .backdrop(name):
            return gift.attributes.contains(where: { attribute in
                if case let .backdrop(backdropName, _, _, _, _, _, _) = attribute {
                    return backdropName == name
                }
                return false
            })
        }
    }
}

struct GiftBuyOrder: Equatable {
    enum Id: Hashable {
        case sample(Int)
        case mine(String)
    }
    
    let id: Id
    let peer: EnginePeer
    let amount: CurrencyAmount
    let condition: GiftBuyOrderCondition
    /// The order's value in Stars: orders placed in GRAM are ranked by it.
    let rank: Int64
    
    var isMine: Bool {
        if case .mine = self.id {
            return true
        }
        return false
    }
}

/// Your own orders and the sample orders you sold to, for each gift type, in UserDefaults.
final class GiftBuyOrdersStorage {
    static let shared = GiftBuyOrdersStorage()
    
    struct Order: Codable, Equatable {
        var id: String
        var isTon: Bool
        var amount: Int64
        var date: Int32
        var duration: Int32
    }
    
    struct Book: Codable, Equatable {
        var orders: [Order] = []
        var soldTo: [Int] = []
    }
    
    private var version = 0
    private let versionPromise = ValuePromise<Int>(0, ignoreRepeated: true)
    
    var updates: Signal<Int, NoError> {
        return self.versionPromise.get()
    }
    
    private func key(accountPeerId: EnginePeer.Id) -> String {
        return "giftBuyOrders_\(accountPeerId.toInt64())"
    }
    
    private func books(accountPeerId: EnginePeer.Id) -> [String: Book] {
        guard let data = UserDefaults.standard.data(forKey: self.key(accountPeerId: accountPeerId)), let books = try? JSONDecoder().decode([String: Book].self, from: data) else {
            return [:]
        }
        return books
    }
    
    /// The book of one gift type, without the orders whose time has run out.
    func book(accountPeerId: EnginePeer.Id, giftId: Int64) -> Book {
        var book = self.books(accountPeerId: accountPeerId)["\(giftId)"] ?? Book()
        let timestamp = Int32(Date().timeIntervalSince1970)
        book.orders.removeAll(where: { $0.date + $0.duration <= timestamp })
        return book
    }
    
    func update(accountPeerId: EnginePeer.Id, giftId: Int64, _ f: (inout Book) -> Void) {
        var books = self.books(accountPeerId: accountPeerId)
        var book = books["\(giftId)"] ?? Book()
        f(&book)
        books["\(giftId)"] = book
        if let data = try? JSONEncoder().encode(books) {
            UserDefaults.standard.set(data, forKey: self.key(accountPeerId: accountPeerId))
        }
        self.version += 1
        self.versionPromise.set(self.version)
    }
    
    /// Stars and nanotons held by your open orders in all collections.
    func currentHeldAmounts(accountPeerId: EnginePeer.Id) -> (stars: Int64, ton: Int64) {
        let timestamp = Int32(Date().timeIntervalSince1970)
        var stars: Int64 = 0
        var ton: Int64 = 0
        for (_, book) in self.books(accountPeerId: accountPeerId) {
            for order in book.orders where order.date + order.duration > timestamp {
                if order.isTon {
                    ton += order.amount
                } else {
                    stars += order.amount
                }
            }
        }
        return (stars, ton)
    }
    
    func heldAmounts(accountPeerId: EnginePeer.Id) -> Signal<(stars: Int64, ton: Int64), NoError> {
        return self.updates
        |> map { [weak self] _ -> (stars: Int64, ton: Int64) in
            return self?.currentHeldAmounts(accountPeerId: accountPeerId) ?? (0, 0)
        }
    }
}

private struct GiftBuyOrdersRandom {
    private var state: UInt64
    
    init(seed: Int64) {
        self.state = UInt64(bitPattern: seed) ^ 0x9e3779b97f4a7c15
    }
    
    mutating func next() -> UInt64 {
        self.state = self.state &* 6364136223846793005 &+ 1442695040888963407
        return self.state >> 33
    }
}

/// The sample buyers: first and last name, and the avatar colour (the peer id modulo 7 picks it).
private let sampleBuyers: [(firstName: String, lastName: String?, color: Int64)] = [
    ("Arthur", "K.", 5),
    ("Nikita", nil, 0),
    ("Sofia", "M.", 6),
    ("Timur", nil, 3),
    ("Lena", nil, 1),
    ("Gift", "Whale", 2),
    ("Mia", "R.", 4),
    ("Daniel", nil, 5),
    ("Oleg", "S.", 0),
    ("Kate", nil, 6),
    ("Max", "T.", 3),
    ("Eva", nil, 1)
]

/// The sample orders' prices as fractions of the cheapest listing, best first.
private let sampleRatios: [Double] = [0.949, 0.936, 0.924, 0.890, 0.856, 0.839]

private func sampleBuyerPeer(index: Int) -> EnginePeer {
    let buyer = sampleBuyers[index]
    let id = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(7_000_000_000 + Int64(index) * 7 + buyer.color))
    return .user(TelegramUser(id: id, accessHash: nil, firstName: buyer.firstName, lastName: buyer.lastName, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
}

/// The same sample book every time for a gift type: six buyers, prices just under the cheapest listing, rounded the
/// way people round them, two of them asking for a backdrop or a model of the collection.
private func sampleBuyOrders(giftId: Int64, cheapest: Int64, attributes: [StarGift.UniqueGift.Attribute]) -> [GiftBuyOrder] {
    var random = GiftBuyOrdersRandom(seed: giftId)
    let firstBuyer = Int(random.next() % UInt64(sampleBuyers.count))
    
    var models: [String] = []
    var backdrops: [String] = []
    for attribute in attributes {
        switch attribute {
        case let .model(name, _, _, _):
            models.append(name)
        case let .backdrop(name, _, _, _, _, _, _):
            backdrops.append(name)
        default:
            break
        }
    }
    models.sort()
    backdrops.sort()
    let modelIndex = Int(random.next() % UInt64(max(1, models.count)))
    let backdropIndex = Int(random.next() % UInt64(max(1, backdrops.count)))
    
    let step: Int64
    if cheapest >= 20_000 {
        step = 500
    } else if cheapest >= 2_000 {
        step = 50
    } else if cheapest >= 200 {
        step = 5
    } else {
        step = 1
    }
    
    var orders: [GiftBuyOrder] = []
    var previousPrice: Int64 = cheapest
    for i in 0 ..< sampleRatios.count {
        var price = Int64((Double(cheapest) * sampleRatios[i] / Double(step)).rounded()) * step
        price = max(step, min(price, previousPrice - step))
        previousPrice = price
        
        var condition: GiftBuyOrderCondition = .any
        if i == 2, !backdrops.isEmpty {
            condition = .backdrop(backdrops[backdropIndex])
        } else if i == 5, !models.isEmpty {
            condition = .model(models[modelIndex])
        }
        
        let buyerIndex = (firstBuyer + i) % sampleBuyers.count
        orders.append(GiftBuyOrder(
            id: .sample(buyerIndex),
            peer: sampleBuyerPeer(index: buyerIndex),
            amount: CurrencyAmount(amount: StarsAmount(value: price, nanos: 0), currency: .stars),
            condition: condition,
            rank: price
        ))
    }
    return orders
}

/// The order book of one collection: the sample orders and yours, best first (yours first among equal ones).
final class GiftBuyOrdersContext {
    struct State: Equatable {
        var orders: [GiftBuyOrder]
    }
    
    let context: AccountContext
    let gift: StarGift.Gift
    let resaleGiftsContext: ResaleGiftsContext
    
    private let statePromise = Promise<State>()
    var state: Signal<State, NoError> {
        return self.statePromise.get()
    }
    
    init(context: AccountContext, gift: StarGift.Gift, resaleGiftsContext: ResaleGiftsContext) {
        self.context = context
        self.gift = gift
        self.resaleGiftsContext = resaleGiftsContext
        
        let giftId = gift.id
        let accountPeerId = context.account.peerId
        let minResaleStars = gift.availability?.minResaleStars
        let fallbackPrice = max(gift.price * 10, 100)
        let configuration = StarsSubscriptionConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
        
        let accountPeer: Signal<EnginePeer?, NoError> = .single(nil)
        |> then(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: accountPeerId)))
        
        // the collection's models and backdrops, and its cheapest listing while the market is not filtered
        let listings: Signal<([StarGift.UniqueGift.Attribute], Int64?), NoError> = .single(([], nil))
        |> then(resaleGiftsContext.state
            |> filter { state in
                return state.filterAttributes.isEmpty && !state.starsOnly
            }
            |> map { state -> ([StarGift.UniqueGift.Attribute], Int64?) in
                var cheapest: Int64?
                for gift in state.gifts {
                    if case let .unique(uniqueGift) = gift, let price = uniqueGift.resellAmounts?.first(where: { $0.currency == .stars })?.amount.value {
                        cheapest = min(cheapest ?? price, price)
                    }
                }
                return (state.attributes, cheapest)
            }
        )
        
        self.statePromise.set(combineLatest(queue: Queue.mainQueue(),
            GiftBuyOrdersStorage.shared.updates,
            accountPeer,
            listings
        )
        |> map { _, accountPeer, listings -> State in
            let book = GiftBuyOrdersStorage.shared.book(accountPeerId: accountPeerId, giftId: giftId)
            let cheapest = minResaleStars ?? listings.1 ?? fallbackPrice
            
            var orders = sampleBuyOrders(giftId: giftId, cheapest: cheapest, attributes: listings.0).filter { order in
                if case let .sample(index) = order.id, book.soldTo.contains(index) {
                    return false
                }
                return true
            }
            if let accountPeer {
                for order in book.orders {
                    let amount = CurrencyAmount(amount: StarsAmount(value: order.amount, nanos: 0), currency: order.isTon ? .ton : .stars)
                    let rank: Int64
                    if order.isTon {
                        rank = convertTonToStars(amount.amount, tonUsdRate: configuration.tonUsdRate, starsUsdRate: Double(configuration.usdWithdrawRate))
                    } else {
                        rank = order.amount
                    }
                    orders.append(GiftBuyOrder(id: .mine(order.id), peer: accountPeer, amount: amount, condition: .any, rank: rank))
                }
            }
            orders.sort(by: { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank > rhs.rank
                }
                return lhs.isMine && !rhs.isMine
            })
            return State(orders: orders)
        }
        |> distinctUntilChanged)
    }
    
    func placeOrder(amount: CurrencyAmount, duration: Int32) {
        GiftBuyOrdersStorage.shared.update(accountPeerId: self.context.account.peerId, giftId: self.gift.id, { book in
            book.orders.append(GiftBuyOrdersStorage.Order(
                id: UUID().uuidString,
                isTon: amount.currency == .ton,
                amount: amount.amount.value,
                date: Int32(Date().timeIntervalSince1970),
                duration: duration
            ))
        })
    }
    
    func cancelOrder(id: String) {
        GiftBuyOrdersStorage.shared.update(accountPeerId: self.context.account.peerId, giftId: self.gift.id, { book in
            book.orders.removeAll(where: { $0.id == id })
        })
    }
    
    /// You sold a gift to this sample buyer: their order leaves the book.
    func markSold(sampleIndex: Int) {
        GiftBuyOrdersStorage.shared.update(accountPeerId: self.context.account.peerId, giftId: self.gift.id, { book in
            if !book.soldTo.contains(sampleIndex) {
                book.soldTo.append(sampleIndex)
            }
        })
    }
}
