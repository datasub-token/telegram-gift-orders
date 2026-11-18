import Foundation
import UIKit
import Display
import ComponentFlow
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import AppBundle
import ViewControllerComponent
import MultilineTextComponent
import ButtonComponent
import ListSectionComponent
import EdgeEffect
import GlassBackgroundComponent
import AvatarComponent
import TelegramStringFormatting
import PresentationDataUtils
import UndoUI
import GiftViewScreen
import StarsWithdrawalScreen
import BalanceNeededScreen

// Buy Orders (concept): the order book of one collection, pushed from the first cell of its resale market inside the
// same sheet. The market's top band (back, title, the collection's name, the balance), a card with the best order and
// the two actions, Sell to the best order and Place Order, then every order, best first.

/// An amount with its currency's icon: the golden star (`Premium/Stars/StarLarge`) or GRAM (`Ads/TonBig`), with an
/// optional title before it ("Sell for ★ 112,000").
final class GiftBuyOrderAmountComponent: Component {
    let prefix: String?
    let amount: CurrencyAmount
    let font: UIFont
    let color: UIColor
    let iconSize: CGFloat
    let dateTimeFormat: PresentationDateTimeFormat
    
    init(prefix: String? = nil, amount: CurrencyAmount, font: UIFont, color: UIColor, iconSize: CGFloat, dateTimeFormat: PresentationDateTimeFormat) {
        self.prefix = prefix
        self.amount = amount
        self.font = font
        self.color = color
        self.iconSize = iconSize
        self.dateTimeFormat = dateTimeFormat
    }
    
    static func ==(lhs: GiftBuyOrderAmountComponent, rhs: GiftBuyOrderAmountComponent) -> Bool {
        if lhs.prefix != rhs.prefix {
            return false
        }
        if lhs.amount != rhs.amount {
            return false
        }
        if lhs.font != rhs.font {
            return false
        }
        if lhs.color != rhs.color {
            return false
        }
        if lhs.iconSize != rhs.iconSize {
            return false
        }
        if lhs.dateTimeFormat != rhs.dateTimeFormat {
            return false
        }
        return true
    }
    
    final class View: UIView {
        private let prefixText = ComponentView<Empty>()
        private let icon = UIImageView()
        private let text = ComponentView<Empty>()
        private var currency: CurrencyAmount.Currency?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            self.addSubview(self.icon)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(component: GiftBuyOrderAmountComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let currency = component.amount.currency
            if self.currency != currency {
                self.currency = currency
                switch currency {
                case .stars:
                    self.icon.image = UIImage(bundleImageName: "Premium/Stars/StarLarge")
                case .ton:
                    self.icon.image = generateTintedImage(image: UIImage(bundleImageName: "Ads/TonBig"), color: UIColor(rgb: 0x30a1f5))
                }
            }
            
            let amountString: String
            let iconSize: CGSize
            switch currency {
            case .stars:
                amountString = presentationStringsFormattedNumber(component.amount.amount.value, component.dateTimeFormat.groupingSeparator)
                iconSize = CGSize(width: component.iconSize, height: component.iconSize)
            case .ton:
                amountString = formatTonAmountText(component.amount.amount.value, dateTimeFormat: component.dateTimeFormat)
                iconSize = CGSize(width: floor(component.iconSize * 0.8), height: floor(component.iconSize * 0.8))
            }
            
            var prefixSize = CGSize()
            if let prefix = component.prefix {
                prefixSize = self.prefixText.update(
                    transition: .immediate,
                    component: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(string: prefix, font: component.font, textColor: component.color)),
                        maximumNumberOfLines: 1
                    )),
                    environment: {},
                    containerSize: availableSize
                )
            }
            let textSize = self.text.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: amountString, font: component.font, textColor: component.color)),
                    maximumNumberOfLines: 1
                )),
                environment: {},
                containerSize: availableSize
            )
            
            let prefixSpacing: CGFloat = component.prefix != nil ? 5.0 : 0.0
            let iconSpacing: CGFloat = max(2.0, floor(component.iconSize * 0.1))
            let height = max(textSize.height, iconSize.height, prefixSize.height)
            let size = CGSize(width: prefixSize.width + prefixSpacing + iconSize.width + iconSpacing + textSize.width, height: height)
            
            let textFrame = CGRect(origin: CGPoint(x: size.width - textSize.width, y: floorToScreenPixels((height - textSize.height) / 2.0)), size: textSize)
            if let prefixView = self.prefixText.view {
                if prefixView.superview == nil {
                    self.addSubview(prefixView)
                }
                prefixView.isHidden = component.prefix == nil
                prefixView.frame = CGRect(origin: CGPoint(x: 0.0, y: textFrame.minY), size: prefixSize)
            }
            // the icon sits on the digits' cap height
            let capCenterY = textFrame.minY + component.font.ascender - component.font.capHeight / 2.0
            self.icon.frame = CGRect(origin: CGPoint(x: prefixSize.width + prefixSpacing, y: floorToScreenPixels(capCenterY - iconSize.height / 2.0)), size: iconSize)
            if let textView = self.text.view {
                if textView.superview == nil {
                    self.addSubview(textView)
                }
                textView.frame = textFrame
            }
            
            return size
        }
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

/// The card at the top: "BEST ORDER", the best amount, how many orders are open, and two capsules side by side:
/// Sell (to the best order that is not yours) and Place Order.
private final class GiftBuyOrdersSummaryComponent: Component {
    let theme: PresentationTheme
    let dateTimeFormat: PresentationDateTimeFormat
    let best: CurrencyAmount?
    let count: Int
    let sellAmount: Int64?
    let sell: () -> Void
    let placeOrder: () -> Void
    
    init(theme: PresentationTheme, dateTimeFormat: PresentationDateTimeFormat, best: CurrencyAmount?, count: Int, sellAmount: Int64?, sell: @escaping () -> Void, placeOrder: @escaping () -> Void) {
        self.theme = theme
        self.dateTimeFormat = dateTimeFormat
        self.best = best
        self.count = count
        self.sellAmount = sellAmount
        self.sell = sell
        self.placeOrder = placeOrder
    }
    
    static func ==(lhs: GiftBuyOrdersSummaryComponent, rhs: GiftBuyOrdersSummaryComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.dateTimeFormat != rhs.dateTimeFormat {
            return false
        }
        if lhs.best != rhs.best {
            return false
        }
        if lhs.count != rhs.count {
            return false
        }
        if lhs.sellAmount != rhs.sellAmount {
            return false
        }
        return true
    }
    
    final class View: UIView {
        private let backgroundLayer = SimpleLayer()
        private let label = ComponentView<Empty>()
        private let best = ComponentView<Empty>()
        private let count = ComponentView<Empty>()
        private let sellButton = ComponentView<Empty>()
        private let placeButton = ComponentView<Empty>()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            self.backgroundLayer.cornerRadius = 26.0
            self.layer.addSublayer(self.backgroundLayer)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(component: GiftBuyOrdersSummaryComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let theme = component.theme
            let size = CGSize(width: availableSize.width, height: 168.0)
            let sideInset: CGFloat = 20.0
            
            self.backgroundLayer.backgroundColor = theme.list.itemBlocksBackgroundColor.cgColor
            self.backgroundLayer.frame = CGRect(origin: .zero, size: size)
            
            let labelSize = self.label.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: "BEST ORDER", font: Font.regular(13.0), textColor: theme.list.freeTextColor))
                )),
                environment: {},
                containerSize: CGSize(width: size.width - sideInset * 2.0, height: 100.0)
            )
            if let labelView = self.label.view {
                if labelView.superview == nil {
                    self.addSubview(labelView)
                }
                labelView.frame = CGRect(origin: CGPoint(x: sideInset, y: 16.0), size: labelSize)
            }
            
            let bestComponent: AnyComponent<Empty>
            if let best = component.best {
                bestComponent = AnyComponent(GiftBuyOrderAmountComponent(amount: best, font: Font.with(size: 30.0, weight: .bold, traits: .monospacedNumbers), color: theme.list.itemPrimaryTextColor, iconSize: 31.0, dateTimeFormat: component.dateTimeFormat))
            } else {
                bestComponent = AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: "—", font: Font.bold(30.0), textColor: theme.list.itemSecondaryTextColor))
                ))
            }
            let bestSize = self.best.update(
                transition: .immediate,
                component: bestComponent,
                environment: {},
                containerSize: CGSize(width: size.width - sideInset * 2.0, height: 100.0)
            )
            if let bestView = self.best.view {
                if bestView.superview == nil {
                    self.addSubview(bestView)
                }
                bestView.frame = CGRect(origin: CGPoint(x: sideInset, y: 34.0), size: bestSize)
            }
            
            let countString = component.count == 1 ? "1 open order" : "\(presentationStringsFormattedNumber(Int32(clamping: component.count), component.dateTimeFormat.groupingSeparator)) open orders"
            let countSize = self.count.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: countString, font: Font.regular(15.0), textColor: theme.list.itemSecondaryTextColor))
                )),
                environment: {},
                containerSize: CGSize(width: size.width - sideInset * 2.0, height: 100.0)
            )
            if let countView = self.count.view {
                if countView.superview == nil {
                    self.addSubview(countView)
                }
                countView.frame = CGRect(origin: CGPoint(x: sideInset, y: 74.0), size: countSize)
            }
            
            // two 44-pt capsules, 10 apart: Sell in the accent colour on a 10 % tint, Place Order filled
            let buttonSpacing: CGFloat = 10.0
            let buttonWidth = floor((size.width - sideInset * 2.0 - buttonSpacing) / 2.0)
            let buttonHeight: CGFloat = 44.0
            let buttonY: CGFloat = 106.0
            let accentColor = theme.list.itemAccentColor
            
            let sellContent: AnyComponentWithIdentity<Empty>
            if let sellAmount = component.sellAmount {
                sellContent = AnyComponentWithIdentity(id: AnyHashable(sellAmount), component: AnyComponent(GiftBuyOrderAmountComponent(
                    prefix: "Sell for",
                    amount: CurrencyAmount(amount: StarsAmount(value: sellAmount, nanos: 0), currency: .stars),
                    font: Font.semibold(15.0),
                    color: accentColor,
                    iconSize: 17.0,
                    dateTimeFormat: component.dateTimeFormat
                )))
            } else {
                sellContent = AnyComponentWithIdentity(id: AnyHashable("sell"), component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: "Sell", font: Font.semibold(15.0), textColor: accentColor))
                )))
            }
            let _ = self.sellButton.update(
                transition: transition,
                component: AnyComponent(ButtonComponent(
                    background: ButtonComponent.Background(
                        style: .legacy,
                        color: accentColor.withMultipliedAlpha(0.1),
                        foreground: accentColor,
                        pressedColor: accentColor.withMultipliedAlpha(0.2),
                        cornerRadius: buttonHeight / 2.0
                    ),
                    content: sellContent,
                    isEnabled: component.sellAmount != nil,
                    action: { [weak self] in
                        guard let self, let component = self.component else {
                            return
                        }
                        component.sell()
                    }
                )),
                environment: {},
                containerSize: CGSize(width: buttonWidth, height: buttonHeight)
            )
            if let sellButtonView = self.sellButton.view {
                if sellButtonView.superview == nil {
                    self.addSubview(sellButtonView)
                }
                sellButtonView.frame = CGRect(origin: CGPoint(x: sideInset, y: buttonY), size: CGSize(width: buttonWidth, height: buttonHeight))
            }
            
            let _ = self.placeButton.update(
                transition: transition,
                component: AnyComponent(ButtonComponent(
                    background: ButtonComponent.Background(
                        style: .legacy,
                        color: accentColor,
                        foreground: theme.list.itemCheckColors.foregroundColor,
                        pressedColor: accentColor.withMultipliedAlpha(0.9),
                        cornerRadius: buttonHeight / 2.0
                    ),
                    content: AnyComponentWithIdentity(id: AnyHashable("place"), component: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(string: "Place Order", font: Font.semibold(15.0), textColor: theme.list.itemCheckColors.foregroundColor))
                    ))),
                    action: { [weak self] in
                        guard let self, let component = self.component else {
                            return
                        }
                        component.placeOrder()
                    }
                )),
                environment: {},
                containerSize: CGSize(width: buttonWidth, height: buttonHeight)
            )
            if let placeButtonView = self.placeButton.view {
                if placeButtonView.superview == nil {
                    self.addSubview(placeButtonView)
                }
                placeButtonView.frame = CGRect(origin: CGPoint(x: size.width - sideInset - buttonWidth, y: buttonY), size: CGSize(width: buttonWidth, height: buttonHeight))
            }
            
            self.component = component
            
            return size
        }
        
        private var component: GiftBuyOrdersSummaryComponent?
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

/// One order, 60 high, in the bidders' rows of the auction screen (`GiftAuctionBidScreen`): the place (1–3 on gold,
/// silver and bronze circles, then plain numbers), the buyer's avatar, name and condition, the amount on the right.
/// Your own order reads "You" on a light accent tint.
private final class GiftBuyOrderRowComponent: Component {
    let context: AccountContext
    let theme: PresentationTheme
    let strings: PresentationStrings
    let nameDisplayOrder: PresentationPersonNameOrder
    let dateTimeFormat: PresentationDateTimeFormat
    let order: GiftBuyOrder
    let place: Int
    let action: (() -> Void)?
    
    init(context: AccountContext, theme: PresentationTheme, strings: PresentationStrings, nameDisplayOrder: PresentationPersonNameOrder, dateTimeFormat: PresentationDateTimeFormat, order: GiftBuyOrder, place: Int, action: (() -> Void)?) {
        self.context = context
        self.theme = theme
        self.strings = strings
        self.nameDisplayOrder = nameDisplayOrder
        self.dateTimeFormat = dateTimeFormat
        self.order = order
        self.place = place
        self.action = action
    }
    
    static func ==(lhs: GiftBuyOrderRowComponent, rhs: GiftBuyOrderRowComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings !== rhs.strings {
            return false
        }
        if lhs.nameDisplayOrder != rhs.nameDisplayOrder {
            return false
        }
        if lhs.dateTimeFormat != rhs.dateTimeFormat {
            return false
        }
        if lhs.order != rhs.order {
            return false
        }
        if lhs.place != rhs.place {
            return false
        }
        if (lhs.action == nil) != (rhs.action == nil) {
            return false
        }
        return true
    }
    
    final class View: UIView, ListSectionComponentChildView {
        var customUpdateIsHighlighted: ((Bool) -> Void)?
        var enumerateSiblings: (((UIView) -> Void) -> Void)?
        let separatorInset: CGFloat = 112.0
        
        private let tintLayer = SimpleLayer()
        private let placeBackground = UIImageView()
        private let placeText = ComponentView<Empty>()
        private let avatar = ComponentView<Empty>()
        private let name = ComponentView<Empty>()
        private let condition = ComponentView<Empty>()
        private let amount = ComponentView<Empty>()
        private let button = HighlightTrackingButton()
        
        private var component: GiftBuyOrderRowComponent?
        private var placeBackgroundPlace: Int?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            self.layer.addSublayer(self.tintLayer)
            self.addSubview(self.placeBackground)
            self.addSubview(self.button)
            
            self.button.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
            self.button.highligthedChanged = { [weak self] highlighted in
                self?.customUpdateIsHighlighted?(highlighted)
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        @objc private func pressed() {
            self.component?.action?()
        }
        
        func update(component: GiftBuyOrderRowComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            
            let theme = component.theme
            let order = component.order
            let size = CGSize(width: availableSize.width, height: 60.0)
            
            self.tintLayer.backgroundColor = order.isMine ? theme.list.itemAccentColor.withMultipliedAlpha(0.07).cgColor : UIColor.clear.cgColor
            self.tintLayer.frame = CGRect(origin: .zero, size: size)
            
            // the place: a 24-pt medal for 1–3 (GiftAuctionBidScreen's PeerPlaceComponent colours), then plain numbers,
            // centred in a 40-pt column at x 12
            let placeColumn = CGRect(x: 12.0, y: 0.0, width: 40.0, height: size.height)
            let placeColors: [UIColor]?
            switch component.place {
            case 1:
                placeColors = [UIColor(rgb: 0xffa901), UIColor(rgb: 0xffcd3b)]
            case 2:
                placeColors = [UIColor(rgb: 0x999999), UIColor(rgb: 0xbbbbbb)]
            case 3:
                placeColors = [UIColor(rgb: 0xcb692e), UIColor(rgb: 0xdc9a59)]
            default:
                placeColors = nil
            }
            let placeBackgroundSize = CGSize(width: 24.0, height: 24.0)
            if let placeColors {
                if self.placeBackgroundPlace != component.place {
                    self.placeBackgroundPlace = component.place
                    self.placeBackground.image = generateGradientFilledCircleImage(diameter: placeBackgroundSize.width, colors: placeColors.map { $0.cgColor } as NSArray, direction: .vertical)
                }
                self.placeBackground.isHidden = false
            } else {
                self.placeBackground.isHidden = true
            }
            self.placeBackground.frame = CGRect(origin: CGPoint(x: placeColumn.midX - placeBackgroundSize.width / 2.0, y: floorToScreenPixels((size.height - placeBackgroundSize.height) / 2.0)), size: placeBackgroundSize)
            
            let placeFont = placeColors != nil ? Font.with(size: 14.0, weight: .semibold, traits: .monospacedNumbers) : Font.with(size: 17.0, traits: .monospacedNumbers)
            let placeSize = self.placeText.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: presentationStringsFormattedNumber(Int32(clamping: component.place), component.dateTimeFormat.groupingSeparator), font: placeFont, textColor: placeColors != nil ? .white : theme.list.itemSecondaryTextColor))
                )),
                environment: {},
                containerSize: CGSize(width: 60.0, height: 40.0)
            )
            if let placeView = self.placeText.view {
                if placeView.superview == nil {
                    placeView.isUserInteractionEnabled = false
                    self.insertSubview(placeView, aboveSubview: self.placeBackground)
                }
                placeView.frame = CGRect(origin: CGPoint(x: floorToScreenPixels(placeColumn.midX - placeSize.width / 2.0), y: floorToScreenPixels((size.height - placeSize.height) / 2.0)), size: placeSize)
            }
            
            let avatarSize = CGSize(width: 40.0, height: 40.0)
            let _ = self.avatar.update(
                transition: .immediate,
                component: AnyComponent(AvatarComponent(
                    context: component.context,
                    theme: theme,
                    peer: order.peer
                )),
                environment: {},
                containerSize: avatarSize
            )
            if let avatarView = self.avatar.view {
                if avatarView.superview == nil {
                    avatarView.isUserInteractionEnabled = false
                    self.insertSubview(avatarView, belowSubview: self.button)
                }
                avatarView.frame = CGRect(origin: CGPoint(x: 60.0, y: floorToScreenPixels((size.height - avatarSize.height) / 2.0)), size: avatarSize)
            }
            
            let amountSize = self.amount.update(
                transition: .immediate,
                component: AnyComponent(GiftBuyOrderAmountComponent(
                    amount: order.amount,
                    font: Font.with(size: 15.0, weight: .semibold, traits: .monospacedNumbers),
                    color: theme.list.itemPrimaryTextColor,
                    iconSize: 17.0,
                    dateTimeFormat: component.dateTimeFormat
                )),
                environment: {},
                containerSize: CGSize(width: size.width, height: size.height)
            )
            if let amountView = self.amount.view {
                if amountView.superview == nil {
                    amountView.isUserInteractionEnabled = false
                    self.insertSubview(amountView, belowSubview: self.button)
                }
                amountView.frame = CGRect(origin: CGPoint(x: size.width - 16.0 - amountSize.width, y: floorToScreenPixels((size.height - amountSize.height) / 2.0)), size: amountSize)
            }
            
            let textX: CGFloat = 112.0
            let textWidth = max(1.0, size.width - textX - amountSize.width - 16.0 - 8.0)
            
            let nameString = order.isMine ? "You" : order.peer.displayTitle(strings: component.strings, displayOrder: component.nameDisplayOrder)
            let nameSize = self.name.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: nameString, font: order.isMine ? Font.semibold(17.0) : Font.regular(17.0), textColor: theme.list.itemPrimaryTextColor)),
                    maximumNumberOfLines: 1
                )),
                environment: {},
                containerSize: CGSize(width: textWidth, height: 100.0)
            )
            if let nameView = self.name.view {
                if nameView.superview == nil {
                    nameView.isUserInteractionEnabled = false
                    self.insertSubview(nameView, belowSubview: self.button)
                }
                nameView.frame = CGRect(origin: CGPoint(x: textX, y: 10.0), size: nameSize)
            }
            
            let conditionSize = self.condition.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: order.condition.title, font: Font.regular(13.0), textColor: theme.list.itemSecondaryTextColor)),
                    maximumNumberOfLines: 1
                )),
                environment: {},
                containerSize: CGSize(width: textWidth, height: 100.0)
            )
            if let conditionView = self.condition.view {
                if conditionView.superview == nil {
                    conditionView.isUserInteractionEnabled = false
                    self.insertSubview(conditionView, belowSubview: self.button)
                }
                conditionView.frame = CGRect(origin: CGPoint(x: textX, y: 33.0), size: conditionSize)
            }
            
            self.button.isEnabled = component.action != nil
            self.button.frame = CGRect(origin: .zero, size: size)
            
            return size
        }
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

final class GiftBuyOrdersScreenComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment
    
    let context: AccountContext
    let ordersContext: GiftBuyOrdersContext
    let overNavigationContainer: UIView
    
    init(context: AccountContext, ordersContext: GiftBuyOrdersContext, overNavigationContainer: UIView) {
        self.context = context
        self.ordersContext = ordersContext
        self.overNavigationContainer = overNavigationContainer
    }
    
    static func ==(lhs: GiftBuyOrdersScreenComponent, rhs: GiftBuyOrdersScreenComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.ordersContext !== rhs.ordersContext {
            return false
        }
        return true
    }
    
    private final class ScrollView: UIScrollView {
        override func touchesShouldCancel(in view: UIView) -> Bool {
            return true
        }
    }
    
    final class View: UIView {
        private let scrollView: ScrollView
        private let edgeEffectView: EdgeEffectView
        
        private let balance = ComponentView<Empty>()
        private let balanceBackgroundView: GlassContextExtractableContainer
        private let title = ComponentView<Empty>()
        private let subtitle = ComponentView<Empty>()
        
        private let summary = ComponentView<Empty>()
        private let list = ComponentView<Empty>()
        
        private var ordersState: GiftBuyOrdersContext.State?
        private var ordersDisposable: Disposable?
        
        private var profileGiftsContext: ProfileGiftsContext?
        private var ownGiftsDisposable: Disposable?
        private var ownGifts: [StarGift.UniqueGift] = []
        
        private var component: GiftBuyOrdersScreenComponent?
        private weak var state: EmptyComponentState?
        private var environment: EnvironmentType?
        private var isUpdating = false
        
        override init(frame: CGRect) {
            self.balanceBackgroundView = GlassContextExtractableContainer()
            
            self.scrollView = ScrollView()
            self.scrollView.showsVerticalScrollIndicator = true
            self.scrollView.showsHorizontalScrollIndicator = false
            self.scrollView.scrollsToTop = false
            self.scrollView.delaysContentTouches = false
            self.scrollView.canCancelContentTouches = true
            self.scrollView.contentInsetAdjustmentBehavior = .never
            if #available(iOS 13.0, *) {
                self.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
            }
            self.scrollView.alwaysBounceVertical = true
            
            self.edgeEffectView = EdgeEffectView()
            
            super.init(frame: frame)
            
            self.addSubview(self.scrollView)
            self.addSubview(self.edgeEffectView)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        deinit {
            self.ordersDisposable?.dispose()
            self.ownGiftsDisposable?.dispose()
        }
        
        /// Your gifts of this collection: the Sell button sells the first one an order accepts.
        private func loadOwnGifts(component: GiftBuyOrdersScreenComponent) {
            let giftId = component.ordersContext.gift.id
            let profileGiftsContext = ProfileGiftsContext(account: component.context.account, peerId: component.context.account.peerId, filter: [.unique, .displayed, .hidden])
            self.profileGiftsContext = profileGiftsContext
            self.ownGiftsDisposable = (profileGiftsContext.state
            |> deliverOnMainQueue).startStrict(next: { [weak self] state in
                guard let self else {
                    return
                }
                var ownGifts: [StarGift.UniqueGift] = []
                for gift in state.filteredGifts + state.gifts {
                    if case let .unique(uniqueGift) = gift.gift, uniqueGift.giftId == giftId, !ownGifts.contains(where: { $0.slug == uniqueGift.slug }) {
                        ownGifts.append(uniqueGift)
                    }
                }
                if self.ownGifts != ownGifts {
                    self.ownGifts = ownGifts
                    if !self.isUpdating {
                        self.state?.updated(transition: .easeInOut(duration: 0.2))
                    }
                }
            })
        }
        
        /// What the Sell button sells and to whom: your first gift of the collection that the best order you did not
        /// place accepts. Without a gift of your own, the cheapest listing stands in, so that the flow can be tried.
        private func sellTarget() -> (gift: StarGift.UniqueGift, order: GiftBuyOrder)? {
            guard let component = self.component, let ordersState = self.ordersState else {
                return nil
            }
            var gifts = self.ownGifts
            if gifts.isEmpty, let listings = component.ordersContext.resaleGiftsContext.currentState?.gifts {
                for gift in listings {
                    if case let .unique(uniqueGift) = gift {
                        gifts.append(uniqueGift)
                        break
                    }
                }
            }
            for order in ordersState.orders where !order.isMine && order.amount.currency == .stars {
                if let gift = gifts.first(where: { order.condition.matches($0) }) {
                    return (gift, order)
                }
            }
            return nil
        }
        
        private func openPlaceOrder() {
            guard let component = self.component, let controller = self.environment?.controller() else {
                return
            }
            let ordersContext = component.ordersContext
            let screen = StarsWithdrawScreen(context: component.context, mode: .starGiftBuyOrder(gift: ordersContext.gift, completion: { [weak self] amount, duration in
                self?.commitOrder(amount: amount, duration: duration)
            }))
            controller.push(screen)
        }
        
        /// Places the order once the balance covers it, the way an offer does: missing Stars are bought first.
        private func commitOrder(amount: CurrencyAmount, duration: Int32) {
            guard let component = self.component else {
                return
            }
            let context = component.context
            let ordersContext = component.ordersContext
            let held = GiftBuyOrdersStorage.shared.currentHeldAmounts(accountPeerId: context.account.peerId)
            
            switch amount.currency {
            case .stars:
                let available = (context.starsContext?.currentState?.balance.value ?? 0) - held.stars
                if let starsContext = context.starsContext, amount.amount.value > available {
                    let requiredStars = amount.amount.value - available
                    let _ = (context.engine.payments.starsTopUpOptions()
                    |> take(1)
                    |> deliverOnMainQueue).startStandalone(next: { [weak self] options in
                        guard let self, let controller = self.environment?.controller() else {
                            return
                        }
                        let purchaseController = context.sharedContext.makeStarsPurchaseScreen(
                            context: context,
                            starsContext: starsContext,
                            options: options,
                            purpose: .starGiftOffer(requiredStars: requiredStars),
                            targetPeerId: nil,
                            customTheme: nil,
                            completion: { stars in
                                starsContext.add(balance: StarsAmount(value: stars, nanos: 0))
                                ordersContext.placeOrder(amount: amount, duration: duration)
                            }
                        )
                        controller.push(purchaseController)
                    })
                    return
                }
            case .ton:
                let available = (context.tonContext?.currentState?.balance.value ?? 0) - held.ton
                if amount.amount.value > available {
                    guard let controller = self.environment?.controller() else {
                        return
                    }
                    var fragmentUrl = "https://fragment.com/ads/topup"
                    if let data = context.currentAppConfiguration.with({ $0 }).data, let value = data["ton_topup_url"] as? String {
                        fragmentUrl = value
                    }
                    controller.push(BalanceNeededScreen(
                        context: context,
                        amount: StarsAmount(value: amount.amount.value - max(0, available), nanos: 0),
                        buttonAction: {
                            context.sharedContext.applicationBindings.openUrl(fragmentUrl)
                        }
                    ))
                    return
                }
            }
            ordersContext.placeOrder(amount: amount, duration: duration)
        }
        
        /// Telegram's accept-offer confirmation, with the order's buyer and price.
        private func openSell() {
            guard let component = self.component, let controller = self.environment?.controller(), let target = self.sellTarget() else {
                return
            }
            let gift = target.gift
            let order = target.order
            let context = component.context
            let ordersContext = component.ordersContext
            let alertController = giftOfferAlertController(
                context: context,
                updatedPresentationData: nil,
                gift: gift,
                peer: order.peer,
                amount: order.amount,
                commit: { [weak self] in
                    if case let .sample(index) = order.id {
                        ordersContext.markSold(sampleIndex: index)
                    }
                    self?.presentSoldToast(gift: gift, order: order)
                }
            )
            controller.present(alertController, in: .window(.root))
        }
        
        private func presentSoldToast(gift: StarGift.UniqueGift, order: GiftBuyOrder) {
            guard let component = self.component, let controller = self.environment?.controller() else {
                return
            }
            let context = component.context
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            
            var animationFile: TelegramMediaFile?
            for attribute in gift.attributes {
                if case let .model(_, file, _, _) = attribute {
                    animationFile = file
                    break
                }
            }
            let buyerName = order.peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
            let amountString = presentationStringsFormattedNumber(order.amount.amount.value, presentationData.dateTimeFormat.groupingSeparator)
            let text = "Sold to **\(buyerName)** for **\(amountString) Stars**."
            
            let content: UndoOverlayContent
            if let animationFile {
                content = .sticker(context: context, file: animationFile, loop: false, title: nil, text: text, undoText: nil, customAction: nil)
            } else {
                content = .image(image: UIImage(bundleImageName: "Premium/Stars/StarLarge") ?? UIImage(), title: nil, text: text, round: false, undoText: nil)
            }
            controller.present(UndoOverlayController(presentationData: presentationData, content: content, elevatedLayout: false, action: { _ in
                return true
            }), in: .current)
        }
        
        /// Your own order: cancelling it gives its Stars back.
        private func openCancel(order: GiftBuyOrder) {
            guard let component = self.component, let controller = self.environment?.controller(), case let .mine(id) = order.id else {
                return
            }
            let context = component.context
            let ordersContext = component.ordersContext
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            
            let amountString: String
            let currencyName: String
            switch order.amount.currency {
            case .stars:
                amountString = "\(presentationStringsFormattedNumber(order.amount.amount.value, presentationData.dateTimeFormat.groupingSeparator)) Stars"
                currencyName = "Stars"
            case .ton:
                amountString = "\(formatTonAmountText(order.amount.amount.value, dateTimeFormat: presentationData.dateTimeFormat)) GRAM"
                currencyName = "GRAM"
            }
            let giftTitle = ordersContext.gift.title ?? "gift"
            let article = giftTitle.lowercased().first.flatMap({ "aeiou".contains($0) }) == true ? "an" : "a"
            controller.present(textAlertController(
                context: context,
                title: "Cancel Order",
                text: "Your order to buy \(article) \(giftTitle) for **\(amountString)** will be removed, and the \(currencyName) it holds will return to your balance.",
                actions: [
                    TextAlertAction(type: .genericAction, title: "Keep", action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Cancel Order", action: {
                        ordersContext.cancelOrder(id: id)
                    })
                ],
                parseMarkdown: true
            ), in: .window(.root))
        }
        
        func update(component: GiftBuyOrdersScreenComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
            self.isUpdating = true
            defer {
                self.isUpdating = false
            }
            
            let environment = environment[EnvironmentType.self].value
            let themeUpdated = self.environment?.theme !== environment.theme
            self.environment = environment
            self.state = state
            
            if self.component == nil {
                self.ordersDisposable = (component.ordersContext.state
                |> deliverOnMainQueue).startStrict(next: { [weak self] ordersState in
                    guard let self else {
                        return
                    }
                    let isFirstState = self.ordersState == nil
                    self.ordersState = ordersState
                    if !self.isUpdating {
                        self.state?.updated(transition: isFirstState ? .immediate : .spring(duration: 0.4))
                    }
                })
                self.loadOwnGifts(component: component)
            }
            self.component = component
            
            let theme = environment.theme
            let strings = environment.strings
            let presentationData = component.context.sharedContext.currentPresentationData.with { $0 }
            
            if themeUpdated {
                self.backgroundColor = theme.list.blocksBackgroundColor
            }
            
            // the market's top band: the same edge, balance, title and subtitle as `GiftStoreScreen` without filters
            let edgeEffectFrame = CGRect(origin: .zero, size: CGSize(width: availableSize.width, height: environment.navigationHeight + 8.0))
            transition.setFrame(view: self.edgeEffectView, frame: edgeEffectFrame)
            self.edgeEffectView.update(content: theme.list.blocksBackgroundColor, blur: true, rect: edgeEffectFrame, edge: .top, edgeSize: min(30.0, edgeEffectFrame.height), transition: transition)
            
            let balanceSize = self.balance.update(
                transition: .immediate,
                component: AnyComponent(BalanceComponent(
                    context: component.context,
                    theme: theme,
                    action: { [weak self] in
                        guard let self, let component = self.component, let starsContext = component.context.starsContext, let controller = self.environment?.controller() else {
                            return
                        }
                        controller.push(component.context.sharedContext.makeStarsTransactionsScreen(context: component.context, starsContext: starsContext))
                    }
                )),
                environment: {},
                containerSize: availableSize
            )
            if let balanceView = self.balance.view {
                if balanceView.superview == nil {
                    self.balanceBackgroundView.contentView.addSubview(balanceView)
                }
                balanceView.frame = CGRect(origin: .zero, size: balanceSize)
                
                let balanceBackgroundFrame = CGRect(origin: CGPoint(x: availableSize.width - environment.safeInsets.right - environment.navigationBarTrailingButtonsInset - 16.0 - balanceSize.width, y: environment.navigationHeight - 60.0 + 2.0 + floor((60.0 - 44.0) * 0.5)), size: balanceSize)
                transition.setFrame(view: self.balanceBackgroundView, frame: balanceBackgroundFrame)
                self.balanceBackgroundView.update(size: balanceBackgroundFrame.size, cornerRadius: balanceBackgroundFrame.height * 0.5, isDark: theme.overallDarkAppearance, tintColor: .init(kind: .panel), isInteractive: true, transition: transition)
            }
            if self.balanceBackgroundView.superview == nil {
                component.overNavigationContainer.addSubview(self.balanceBackgroundView)
            }
            
            var topInset: CGFloat = 0.0
            if environment.statusBarHeight > 0.0 {
                topInset = environment.statusBarHeight - 6.0
            }
            let headerSideInset: CGFloat = 24.0 + environment.safeInsets.left
            
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: "Buy Orders", font: Font.semibold(17.0), textColor: theme.rootController.navigationBar.primaryTextColor)),
                    horizontalAlignment: .center
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - headerSideInset * 2.0, height: 100.0)
            )
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    component.overNavigationContainer.addSubview(titleView)
                }
                transition.setFrame(view: titleView, frame: CGRect(origin: CGPoint(x: floor((availableSize.width - titleSize.width) / 2.0), y: topInset + 22.0), size: titleSize))
            }
            
            let subtitleSize = self.subtitle.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: component.ordersContext.gift.title ?? "Gift", font: Font.regular(13.0), textColor: theme.rootController.navigationBar.secondaryTextColor)),
                    horizontalAlignment: .center,
                    maximumNumberOfLines: 1
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - headerSideInset * 2.0, height: 100.0)
            )
            if let subtitleView = self.subtitle.view {
                if subtitleView.superview == nil {
                    component.overNavigationContainer.addSubview(subtitleView)
                }
                transition.setFrame(view: subtitleView, frame: CGRect(origin: CGPoint(x: floor((availableSize.width - subtitleSize.width) / 2.0), y: topInset + 43.0), size: subtitleSize))
            }
            
            // the content: the summary card 10 under the band, the list 24 under it
            let sideInset: CGFloat = 16.0 + environment.safeInsets.left
            let contentWidth = availableSize.width - sideInset - 16.0 - environment.safeInsets.right
            var contentHeight = environment.navigationHeight + 10.0
            
            let orders = self.ordersState?.orders ?? []
            let sellTarget = self.sellTarget()
            
            let summarySize = self.summary.update(
                transition: transition,
                component: AnyComponent(GiftBuyOrdersSummaryComponent(
                    theme: theme,
                    dateTimeFormat: environment.dateTimeFormat,
                    best: orders.first?.amount,
                    count: orders.count,
                    sellAmount: sellTarget?.order.amount.amount.value,
                    sell: { [weak self] in
                        self?.openSell()
                    },
                    placeOrder: { [weak self] in
                        self?.openPlaceOrder()
                    }
                )),
                environment: {},
                containerSize: CGSize(width: contentWidth, height: 1000.0)
            )
            if let summaryView = self.summary.view {
                if summaryView.superview == nil {
                    self.scrollView.addSubview(summaryView)
                }
                transition.setFrame(view: summaryView, frame: CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: summarySize))
            }
            contentHeight += summarySize.height + 24.0
            
            var listItems: [AnyComponentWithIdentity<Empty>] = []
            for (index, order) in orders.enumerated() {
                listItems.append(AnyComponentWithIdentity(id: AnyHashable(order.id), component: AnyComponent(GiftBuyOrderRowComponent(
                    context: component.context,
                    theme: theme,
                    strings: strings,
                    nameDisplayOrder: presentationData.nameDisplayOrder,
                    dateTimeFormat: environment.dateTimeFormat,
                    order: order,
                    place: index + 1,
                    action: order.isMine ? { [weak self] in
                        self?.openCancel(order: order)
                    } : nil
                ))))
            }
            let listSize = self.list.update(
                transition: transition,
                component: AnyComponent(ListSectionComponent(
                    theme: theme,
                    style: .glass,
                    header: AnyComponent(MultilineTextComponent(
                        text: .plain(NSAttributedString(string: "ALL ORDERS", font: Font.regular(presentationData.listsFontSize.itemListBaseHeaderFontSize), textColor: theme.list.freeTextColor)),
                        maximumNumberOfLines: 0
                    )),
                    footer: nil,
                    items: listItems
                )),
                environment: {},
                containerSize: CGSize(width: contentWidth, height: 10000.0)
            )
            if let listView = self.list.view {
                if listView.superview == nil {
                    self.scrollView.addSubview(listView)
                }
                transition.setFrame(view: listView, frame: CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: listSize))
            }
            contentHeight += listSize.height
            contentHeight += 24.0 + environment.safeInsets.bottom
            
            if self.scrollView.frame != CGRect(origin: .zero, size: availableSize) {
                self.scrollView.frame = CGRect(origin: .zero, size: availableSize)
            }
            let contentSize = CGSize(width: availableSize.width, height: contentHeight)
            if self.scrollView.contentSize != contentSize {
                self.scrollView.contentSize = contentSize
            }
            let scrollInsets = UIEdgeInsets(top: environment.navigationHeight, left: 0.0, bottom: 0.0, right: 0.0)
            if self.scrollView.verticalScrollIndicatorInsets != scrollInsets {
                self.scrollView.verticalScrollIndicatorInsets = scrollInsets
            }
            
            return availableSize
        }
    }
    
    func makeView() -> View {
        return View()
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

/// Pushed over the market inside the same sheet, with the market's transparent glass bar (its back button returns).
final class GiftBuyOrdersScreen: ViewControllerComponentContainer {
    private let overNavigationContainer: UIView
    
    init(context: AccountContext, ordersContext: GiftBuyOrdersContext) {
        let overNavigationContainer = SparseContainerView()
        self.overNavigationContainer = overNavigationContainer
        
        super.init(context: context, component: GiftBuyOrdersScreenComponent(
            context: context,
            ordersContext: ordersContext,
            overNavigationContainer: overNavigationContainer
        ), navigationBarAppearance: .transparent, theme: .default, updatedPresentationData: nil)
        
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: context.sharedContext.currentPresentationData.with { $0 }.strings.Common_Back, style: .plain, target: nil, action: nil)
        
        if let navigationBar = self.navigationBar {
            navigationBar.customOverBackgroundContentView.insertSubview(self.overNavigationContainer, at: 0)
        }
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
