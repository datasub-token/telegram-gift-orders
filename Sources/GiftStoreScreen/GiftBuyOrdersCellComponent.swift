import Foundation
import UIKit
import Display
import ComponentFlow
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AppBundle
import MultilineTextComponent
import PlainButtonComponent
import GiftItemComponent
import AnimatedAvatarSetNode

/// Buy Orders (concept): the first cell of a collection's resale market. A card in the grid's cell size, as white as
/// the shop's cells: the three best buyers' avatars, "Buy Orders", how many there are, the best order in the shop's
/// Stars price capsule and a blue corner ribbon (the grid's own `Premium/GiftRibbon`).
final class GiftBuyOrdersCellComponent: Component {
    let context: AccountContext
    let theme: PresentationTheme
    let peers: [EnginePeer]
    let count: Int
    let bestStars: Int64?
    let groupingSeparator: String
    
    init(
        context: AccountContext,
        theme: PresentationTheme,
        peers: [EnginePeer],
        count: Int,
        bestStars: Int64?,
        groupingSeparator: String
    ) {
        self.context = context
        self.theme = theme
        self.peers = peers
        self.count = count
        self.bestStars = bestStars
        self.groupingSeparator = groupingSeparator
    }
    
    static func ==(lhs: GiftBuyOrdersCellComponent, rhs: GiftBuyOrdersCellComponent) -> Bool {
        if lhs.context !== rhs.context {
            return false
        }
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.peers != rhs.peers {
            return false
        }
        if lhs.count != rhs.count {
            return false
        }
        if lhs.bestStars != rhs.bestStars {
            return false
        }
        if lhs.groupingSeparator != rhs.groupingSeparator {
            return false
        }
        return true
    }
    
    final class View: UIView {
        private let backgroundLayer = SimpleLayer()
        private let avatarsContext = AnimatedAvatarSetContext()
        private let avatarsView = AnimatedAvatarSetView()
        private let title = ComponentView<Empty>()
        private let subtitle = ComponentView<Empty>()
        private let price = ComponentView<Empty>()
        private let ribbon = UIImageView()
        private let ribbonText = ComponentView<Empty>()
        
        private var component: GiftBuyOrdersCellComponent?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            self.backgroundLayer.masksToBounds = true
            if #available(iOS 13.0, *) {
                self.backgroundLayer.cornerCurve = .circular
            }
            self.layer.addSublayer(self.backgroundLayer)
            
            self.avatarsView.isUserInteractionEnabled = false
            self.addSubview(self.avatarsView)
            self.addSubview(self.ribbon)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(component: GiftBuyOrdersCellComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            let previousComponent = self.component
            self.component = component
            
            let size = CGSize(width: availableSize.width, height: 154.0)
            let theme = component.theme
            
            // the grid's glass-style cell: corner 16 (GiftItemComponent, `.glass`)
            self.backgroundLayer.backgroundColor = theme.list.itemBlocksBackgroundColor.cgColor
            self.backgroundLayer.cornerRadius = 16.0
            transition.setFrame(layer: self.backgroundLayer, frame: CGRect(origin: .zero, size: size))
            
            // the best buyers: 30-pt avatars, 20 apart, each cutting a 1.5-pt ring out of the next
            let avatarSize = CGSize(width: 30.0, height: 30.0)
            let avatarStep: CGFloat = 20.0
            let peers = Array(component.peers.prefix(3))
            let avatarsContent = self.avatarsContext.update(peers: peers, animated: previousComponent != nil)
            let _ = self.avatarsView.update(
                context: component.context,
                content: avatarsContent,
                itemSize: avatarSize,
                customSpacing: avatarSize.width - avatarStep,
                animation: transition.animation.isImmediate ? .None : .System(duration: 0.25, transition: ControlledTransition(duration: 0.25, curve: .easeInOut, interactive: false)),
                synchronousLoad: true
            )
            let avatarsWidth = peers.isEmpty ? 0.0 : avatarSize.width + avatarStep * CGFloat(peers.count - 1)
            transition.setFrame(view: self.avatarsView, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - avatarsWidth) / 2.0), y: 20.0), size: CGSize(width: avatarsWidth, height: avatarSize.height)))
            
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: "Buy Orders", font: Font.semibold(14.0), textColor: theme.list.itemPrimaryTextColor)),
                    horizontalAlignment: .center,
                    maximumNumberOfLines: 1
                )),
                environment: {},
                containerSize: CGSize(width: size.width - 12.0, height: 100.0)
            )
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    titleView.isUserInteractionEnabled = false
                    self.addSubview(titleView)
                }
                titleView.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - titleSize.width) / 2.0), y: floorToScreenPixels(70.0 - titleSize.height / 2.0)), size: titleSize)
            }
            
            let countString = component.count == 1 ? "1 order" : "\(presentationStringsFormattedNumber(Int32(clamping: component.count), component.groupingSeparator)) orders"
            let subtitleSize = self.subtitle.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: countString, font: Font.regular(12.0), textColor: theme.list.itemSecondaryTextColor)),
                    horizontalAlignment: .center,
                    maximumNumberOfLines: 1
                )),
                environment: {},
                containerSize: CGSize(width: size.width - 12.0, height: 100.0)
            )
            if let subtitleView = self.subtitle.view {
                if subtitleView.superview == nil {
                    subtitleView.isUserInteractionEnabled = false
                    self.addSubview(subtitleView)
                }
                subtitleView.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - subtitleSize.width) / 2.0), y: floorToScreenPixels(88.0 - subtitleSize.height / 2.0)), size: subtitleSize)
            }
            
            // the shop's Stars price capsule: #FFC83D at 20 %, the golden star, semibold 11 in #D3720A
            // (GiftItemComponent, `.starGift` with a "#" price), 10 above the cell's bottom
            if let bestStars = component.bestStars {
                let priceSize = self.price.update(
                    transition: .immediate,
                    component: AnyComponent(StarsButtonContentComponent(
                        context: component.context,
                        text: "# \(presentationStringsFormattedNumber(bestStars, component.groupingSeparator))",
                        color: theme.overallDarkAppearance ? UIColor(rgb: 0xffc337) : UIColor(rgb: 0xd3720a)
                    )),
                    environment: {},
                    containerSize: size
                )
                if let priceView = self.price.view {
                    if priceView.superview == nil {
                        priceView.isUserInteractionEnabled = false
                        self.addSubview(priceView)
                    }
                    priceView.isHidden = false
                    priceView.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - priceSize.width) / 2.0), y: size.height - priceSize.height - 10.0), size: priceSize)
                }
            } else {
                self.price.view?.isHidden = true
            }
            
            // the corner ribbon in the grid's blue (GiftItemComponent.Ribbon.Color.blue), 2 pt over the top and right edges
            if self.ribbon.image == nil || previousComponent?.theme !== theme {
                let colors: [UIColor]
                if theme.overallDarkAppearance {
                    colors = [UIColor(rgb: 0x142e42), UIColor(rgb: 0x354f5b)]
                } else {
                    colors = [UIColor(rgb: 0x34a4fc), UIColor(rgb: 0x6fd3ff)]
                }
                self.ribbon.image = generateGradientTintedImage(image: UIImage(bundleImageName: "Premium/GiftRibbon"), colors: colors, direction: .mirroredDiagonal)
            }
            let ribbonOffset = CGPoint(x: 2.0, y: -2.0)
            if let ribbonImage = self.ribbon.image {
                self.ribbon.frame = CGRect(origin: CGPoint(x: size.width - ribbonImage.size.width + ribbonOffset.x, y: ribbonOffset.y), size: ribbonImage.size)
            }
            let ribbonTextSize = self.ribbonText.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: "orders", font: Font.semibold(10.0), textColor: .white)),
                    horizontalAlignment: .center
                )),
                environment: {},
                containerSize: size
            )
            if let ribbonTextView = self.ribbonText.view {
                if ribbonTextView.superview == nil {
                    ribbonTextView.isUserInteractionEnabled = false
                    self.addSubview(ribbonTextView)
                }
                ribbonTextView.bounds = CGRect(origin: .zero, size: ribbonTextSize)
                ribbonTextView.transform = CGAffineTransform(rotationAngle: .pi / 4.0)
                ribbonTextView.center = CGPoint(x: size.width - 22.0 + ribbonOffset.x, y: 22.0 + ribbonOffset.y)
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

/// The cell in the market's grid: it follows the collection's order book and opens the Buy Orders screen.
final class GiftBuyOrdersGridItem {
    let ordersContext: GiftBuyOrdersContext
    
    private let cell = ComponentView<Empty>()
    private var ordersState: GiftBuyOrdersContext.State?
    private var ordersDisposable: Disposable?
    
    private var theme: PresentationTheme?
    private var groupingSeparator: String = ""
    private var controller: (() -> ViewController?)?
    private var size: CGSize?
    
    init(context: AccountContext, gift: StarGift.Gift, resaleGiftsContext: ResaleGiftsContext) {
        self.ordersContext = GiftBuyOrdersContext(context: context, gift: gift, resaleGiftsContext: resaleGiftsContext)
        
        self.ordersDisposable = (self.ordersContext.state
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            guard let self else {
                return
            }
            let isFirstState = self.ordersState == nil
            self.ordersState = state
            self.updateCell(transition: isFirstState ? .immediate : .easeInOut(duration: 0.25))
        })
    }
    
    deinit {
        self.ordersDisposable?.dispose()
    }
    
    func update(containerView: UIView, belowView: UIView, frame: CGRect, theme: PresentationTheme, groupingSeparator: String, controller: @escaping () -> ViewController?, transition: ComponentTransition) {
        self.theme = theme
        self.groupingSeparator = groupingSeparator
        self.controller = controller
        self.size = frame.size
        
        self.updateCell(transition: .immediate)
        
        if let cellView = self.cell.view {
            if cellView.superview == nil {
                if belowView.superview === containerView {
                    containerView.insertSubview(cellView, belowSubview: belowView)
                } else {
                    containerView.addSubview(cellView)
                }
            }
            transition.setFrame(view: cellView, frame: frame)
        }
    }
    
    private func updateCell(transition: ComponentTransition) {
        guard let theme = self.theme, let size = self.size else {
            return
        }
        let orders = self.ordersState?.orders ?? []
        let _ = self.cell.update(
            transition: transition,
            component: AnyComponent(PlainButtonComponent(
                content: AnyComponent(GiftBuyOrdersCellComponent(
                    context: self.ordersContext.context,
                    theme: theme,
                    peers: orders.prefix(3).map(\.peer),
                    count: orders.count,
                    bestStars: orders.first(where: { $0.amount.currency == .stars })?.amount.amount.value,
                    groupingSeparator: self.groupingSeparator
                )),
                effectAlignment: .center,
                action: { [weak self] in
                    self?.openOrders()
                },
                animateAlpha: false
            )),
            environment: {},
            containerSize: size
        )
    }
    
    private func openOrders() {
        guard let controller = self.controller?() else {
            return
        }
        controller.push(GiftBuyOrdersScreen(context: self.ordersContext.context, ordersContext: self.ordersContext))
    }
}
