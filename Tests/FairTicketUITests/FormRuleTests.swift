import Foundation
import Testing
import FairTicketKit
@testable import FairTicketUI

/// Rules the interface derives on its own: which page owns a field, how list text is
/// split, how the cart is built and reordered.
///
/// These are the places where a frontend can silently disagree with the engine, so
/// they are asserted against the captured capabilities payload rather than against
/// hand-written expectations.
@MainActor
@Suite("表单规则")
struct FormRuleTests {

    /// Put one entry per seat into the cart, which is the version-5 way of choosing
    /// seats: there is no `seat_types` field any more.
    private func fillCart(_ model: AppModel, seats: [String]) {
        model.setCart(
            seats.map {
                CartItem(
                    fromStation: "北京西",
                    toStation: "郑州东",
                    trainScope: CartItem.scopeAll,
                    seatType: $0
                )
            }
        )
    }

    @Test("每个分组归属到正确的页面")
    func sectionsOwnTheirKeys() {
        #expect(ConfigSection.owning("cart_items") == .cart)
        #expect(ConfigSection.owning("train_date") == .trip)
        #expect(ConfigSection.owning("auto_submit") == .trip)
        #expect(ConfigSection.owning("passenger_names") == .passengers)
        #expect(ConfigSection.owning("passenger_ticket_types") == .passengers)
        #expect(ConfigSection.owning("berth_preference") == .position)
        #expect(ConfigSection.owning("quiet_carriage_preference") == .position)
        // Advanced parameters have no dedicated page: they fall through to 高级参数,
        // which is what keeps a newly added backend field reachable.
        #expect(ConfigSection.owning("query_interval_seconds") == nil)
    }

    @Test("每个可编辑字段都有控件")
    func editableKeysAllHaveControls() throws {
        let capabilities = try #require(CapabilitiesSnapshot.load())
        let specKeys = Set(capabilities.fieldSpecs.map(\.key))
        let specLess = Set(capabilities.editableKeys).subtracting(specKeys)

        // Version 5 dropped the one compatibility key that used to have no control of
        // its own, so the two sets must now agree exactly.  This mirrors the guard in
        // the engine's own test_sidecar_protocol.py: a new settings key that nobody can
        // reach cannot slip into the interface unnoticed.
        #expect(specLess.isEmpty, "有字段没有任何控件：\(specLess.sorted())")
    }

    @Test("带控件的字段都能在界面上找到")
    func everyFieldWithAControlIsReachable() throws {
        let capabilities = try #require(CapabilitiesSnapshot.load())

        for spec in capabilities.fieldSpecs {
            let owned = ConfigSection.owning(spec.key)
            #expect(
                owned != nil || spec.page == "advanced",
                "\(spec.key) 既不属于任何页面，也不是高级参数，界面上将无法修改"
            )
        }
    }

    @Test("四个页面认领的字段互不重叠")
    func sectionsDoNotOverlap() {
        let claimed = ConfigSection.configuration.flatMap { ConfigSection.keys(for: $0) }
        #expect(claimed.count == Set(claimed).count, "同一个字段被两个页面认领")
    }

    @Test("购物车字段带 cart 类型，页面据此渲染「添加备选」入口")
    func theCartEntryPointIsFoundByKind() throws {
        let capabilities = try #require(CapabilitiesSnapshot.load())
        let cart = try #require(capabilities.spec(for: "cart_items"))

        // The cart page appends its「添加备选」card by looking for this kind, not for a
        // group name: a rename on the Python side must not be able to take the only way
        // to fill the cart off the screen.
        #expect(cart.kind == .cart)
        #expect(capabilities.groupOrder.contains(cart.group), "购物车分组必须出现在分组顺序里")

        let ticketTypes = try #require(capabilities.spec(for: "passenger_ticket_types"))
        #expect(ticketTypes.kind == .ticketTypes)

        // And the two composite widgets the form draws for itself.
        #expect(capabilities.spec(for: "seat_position_preferences")?.kind == .seatMap)
        #expect(capabilities.spec(for: "berth_preference")?.kind == .berths)
    }

    @Test("列表字段按后端接受的全部分隔符切分")
    func listTextSplitsLikeTheBackend() {
        let model = AppModel.preview()
        model.setListText("passenger_names", "张三，李四、王五;赵六；钱七\n孙八\t周九")

        let items = model.listItems("passenger_names")
        #expect(items.count == 7)
        #expect(items.first == "张三")
        #expect(items.last == "周九")
        #expect(model.passengerCountForDisplay() == items.count)
    }

    @Test("列表字段忽略空白与多余分隔符")
    func listTextIgnoresNoise() {
        let model = AppModel.preview()
        model.setListText("passenger_names", " , 张三 ，， ,  ")

        #expect(model.listItems("passenger_names") == ["张三"])
    }

    @Test("导入后的数组形态也能显示为一行文本")
    func listTextRendersImportedArrays() {
        let model = AppModel.preview()
        model.setStringList("passenger_names", ["张三", "李四"])

        #expect(model.listText("passenger_names") == "张三，李四")
        #expect(model.listItems("passenger_names") == ["张三", "李四"])
    }

    // MARK: - Draft row

    @Test("草稿行按「席别 × 车次」展开，与桌面窗口同序")
    func draftExpandsSeatsAndTrainsInTheDesktopOrder() {
        let model = AppModel.preview()
        model.setCart([])
        model.cartDraft.fromStation = "北京西"
        model.cartDraft.toStation = "郑州东"
        model.cartDraft.trainScope = CartItem.scopeSpecific
        model.cartDraft.trainCode = "g79, G95"
        model.cartDraft.seatTypes = ["二等座", "一等座"]

        let entries = model.cartDraftEntries()

        // Seats outer, trains inner — the order the desktop form expands in, so the
        // add button's count and what lands in the cart cannot disagree.
        #expect(entries.map(\.seatType) == ["二等座", "二等座", "一等座", "一等座"])
        #expect(entries.map(\.trainCode) == ["G79", "G95", "G79", "G95"], "车次应统一为大写")
    }

    @Test("不限车次的项目不带车次")
    func anUnlimitedEntryCarriesNoTrainCode() {
        let model = AppModel.preview()
        model.setCart([])
        model.cartDraft.fromStation = "北京西"
        model.cartDraft.toStation = "郑州东"
        model.cartDraft.trainScope = CartItem.scopeAll
        model.cartDraft.trainCode = "G79"
        model.cartDraft.seatTypes = ["二等座"]

        let entry = model.cartDraftEntries().first
        #expect(entry?.trainCode == "", "不限车次与指定车次不能同时成立，后端会直接拒绝")
        #expect(entry?.scopeLabel == "不限车次")
    }

    @Test("未选席别时草稿不产出任何条目")
    func anEmptySeatSelectionYieldsNothing() {
        let model = AppModel.preview()
        model.setCart([])
        model.cartDraft.fromStation = "北京西"
        model.cartDraft.toStation = "郑州东"

        #expect(model.cartDraftEntries().isEmpty)
        #expect(model.pendingCartAdditions().isEmpty)
    }

    @Test("重复条目只登记一次，并保留原有位置")
    func duplicatesAreCountedButNotAddedTwice() {
        let model = AppModel.preview()
        model.setCart([])
        fillCart(model, seats: ["二等座"])
        model.cartDraft.fromStation = "北京西"
        model.cartDraft.toStation = "郑州东"
        model.cartDraft.trainScope = CartItem.scopeAll
        model.cartDraft.seatTypes = ["二等座", "一等座"]

        #expect(model.cartDraftEntries().count == 2)
        #expect(model.pendingCartAdditions().count == 1, "二等座已经在购物车里了")

        model.commitCartDraft()
        #expect(model.cartItems.count == 2)
        #expect(model.cartItems.first?.seatType == "二等座", "原位置不能被顶掉")
    }

    @Test("加入后清空席别，但保留站对，便于继续添加")
    func committingKeepsTheStationPair() {
        let model = AppModel.preview()
        model.setCart([])
        model.cartDraft.fromStation = "北京西"
        model.cartDraft.toStation = "郑州东"
        model.cartDraft.trainScope = CartItem.scopeAll
        model.cartDraft.seatTypes = ["二等座"]

        #expect(model.commitCartDraft())
        #expect(model.cartItems.count == 1)
        #expect(model.cartDraft.seatTypes.isEmpty)
        #expect(model.cartDraft.fromStation == "北京西")
        #expect(model.cartDraft.toStation == "郑州东")

        // Nothing left to add, so the button must not claim otherwise.
        #expect(!model.commitCartDraft())
    }

    @Test("交换站点只换草稿里的出发与到达")
    func swappingStationsKeepsTheRest() {
        let model = AppModel.preview()
        model.setCart([])
        model.cartDraft.fromStation = "北京西"
        model.cartDraft.toStation = "郑州东"
        model.setString("train_date", "2026-09-28")

        model.swapDraftStations()

        #expect(model.cartDraft.fromStation == "郑州东")
        #expect(model.cartDraft.toStation == "北京西")
        #expect(model.string("train_date") == "2026-09-28")
    }

    // MARK: - The cart itself

    @Test("席别由购物车推导，按顺序去重")
    func seatLabelsComeFromTheCart() {
        let model = AppModel.preview()
        model.setCart([])

        fillCart(model, seats: ["二等座", "硬卧", "二等座"])
        // setCart keeps what it is given, including an exact duplicate; the derived
        // label list is what the seat map and the berth editor read.
        #expect(model.cartSeatLabels() == ["二等座", "硬卧"])

        model.setCart([])
        #expect(model.cartSeatLabels().isEmpty)
    }

    @Test("拖动调整购物车顺序，其余条目保持不动")
    func reorderingKeepsTheOtherEntries() {
        let model = AppModel.preview()
        model.setCart([])
        fillCart(model, seats: ["二等座", "一等座", "硬卧"])

        let last = model.cartItems[2].id
        let first = model.cartItems[0].id
        model.moveCartItem(last, to: first)

        #expect(model.cartSeatLabels() == ["硬卧", "二等座", "一等座"])
    }

    @Test("移除一项不影响其他项")
    func removingOneEntryKeepsTheRest() {
        let model = AppModel.preview()
        model.setCart([])
        fillCart(model, seats: ["二等座", "一等座"])

        model.removeCartItem(model.cartItems[0].id)

        #expect(model.cartSeatLabels() == ["一等座"])
    }

    @Test("购物车条目的读写是自洽的，未知车次范围退化为不限车次")
    func cartItemRoundTripsThroughJSON() throws {
        let item = CartItem(
            fromStation: "北京西",
            toStation: "郑州东",
            trainScope: CartItem.scopeSpecific,
            trainCode: "G79",
            seatType: "二等座"
        )

        #expect(CartItem(json: item.json) == item)
        #expect(item.isComplete)

        // An entry with no seat, or a "specific" entry with no train, is not attemptable
        // — the validator rejects both, so the list marks them instead of hiding it.
        #expect(!CartItem(fromStation: "北京西", toStation: "郑州东").isComplete)
        #expect(!CartItem(fromStation: "北京西", toStation: "郑州东", trainScope: CartItem.scopeSpecific).isComplete)

        // An unrecognised scope reads as the permissive value rather than silently
        // becoming a specific train the entry does not name.
        let unknown = try #require(
            CartItem(json: .object([
                "from_station": .string("北京西"),
                "to_station": .string("郑州东"),
                "train_scope": .string("whatever"),
                "seat_type": .string("二等座"),
            ]))
        )
        #expect(unknown.trainScope == CartItem.scopeAll)
    }

    // MARK: - Seat map

    @Test("座位关系图只提供后端允许的字母")
    func seatMapLettersComeFromTheEngineTable() throws {
        let model = AppModel.preview()
        let capabilities = try #require(model.capabilities)

        for label in capabilities.seatGroups.seated {
            let product = try #require(capabilities.seats.first { $0.label == label })
            // Only products with a seat map participate; 硬座/软座/无座 have none, and
            // business class is resolved from `dw_flag` at order time (its own test).
            guard
                capabilities.seatLayouts.choosableCodes.contains(product.submitCode),
                product.submitCode != capabilities.seatLayouts.businessCode
            else { continue }

            fillCart(model, seats: [label])
            let letters = model.seatMapLetters()
            let allowed = capabilities.seatLayouts.lettersByCode[product.submitCode] ?? []
            #expect(Set(letters) == Set(allowed), "\(label) 的字母集合与后端不一致")
            #expect(Set(letters).count == letters.count, "\(label) 出现了重复字母")
        }
    }

    @Test("商务座按后端的安全交集只提供 A/F")
    func businessClassUsesTheSafeIntersection() throws {
        let model = AppModel.preview()
        let capabilities = try #require(model.capabilities)
        model.setCart([])
        // Business class is selected separately by `dw_flag` and resolved at order
        // time, so the map must not offer letters the engine cannot honour.
        let label = try #require(
            capabilities.seats.first { $0.submitCode == capabilities.seatLayouts.businessCode }?.label,
            "快照里没有商务座"
        )

        fillCart(model, seats: [label])
        #expect(model.seatMapLetters() == ["A", "F"])
    }

    @Test("座位偏好按字母顺序排列且不重复")
    func seatPositionsStaySorted() {
        let model = AppModel.preview()
        model.setStringList("seat_position_preferences", [])

        model.toggleSeatPosition("2F")
        model.toggleSeatPosition("1A")
        model.toggleSeatPosition("1D")
        #expect(model.seatPositions() == ["1A", "1D", "2F"])

        model.toggleSeatPosition("1A")
        #expect(model.seatPositions() == ["1D", "2F"])
    }

    @Test("铺位数量按后端接受的范围钳制")
    func berthCountsRespectBackendBounds() {
        let model = AppModel.preview()

        model.setBerth(lower: 6, middle: 5, upper: 1)
        let counts = model.berthCounts()
        #expect(counts.lower == 6, "上限由后端校验，前端只负责不写负数")
        #expect(counts.middle == 5)
        #expect(counts.upper == 1)

        model.setBerth(lower: -3, middle: 0, upper: 0)
        #expect(model.berthCounts().lower == 0)
    }

    // MARK: - Passenger ticket types

    @Test("票种留空即删除该项，而不是写入空字符串")
    func anEmptyTicketTypeIsOmitted() {
        let model = AppModel.preview()

        model.setTicketType("student", for: "张三")
        #expect(model.ticketType(for: "张三") == "student")

        model.setTicketType("", for: "张三")
        #expect(model.ticketType(for: "张三") == "")
        // The engine reads a missing key as "follow the contact record"; an empty
        // string would be rejected as an unknown ticket type.
        #expect(model.ticketTypes()["张三"] == nil)
    }

    @Test("改乘车人列表时，被删掉的票种设置一并清理")
    func editingPassengersPrunesOrphanedTicketTypes() {
        let model = AppModel.preview()
        model.setListText("passenger_names", "张三，李四")
        model.setTicketType("student", for: "李四")

        model.setListText("passenger_names", "张三")

        #expect(
            model.ticketTypes().isEmpty,
            "后端会拒绝为未选中的乘车人设置票种，留着它会报一条用户看不到的人名的错"
        )
    }
}
