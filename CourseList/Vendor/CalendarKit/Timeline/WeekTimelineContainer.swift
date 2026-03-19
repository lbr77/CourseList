import UIKit

public final class WeekTimelineContainer: UIView {
    public let timeline: WeekTimelineView
    public weak var delegate: UIScrollViewDelegate?
    public var contentOffset: CGPoint = .zero
    public var contentSize: CGSize = .zero

    public init(_ timeline: WeekTimelineView) {
        self.timeline = timeline
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        timeline.frame = bounds
        contentSize = bounds.size
    }

    public func prepareForReuse() {
        timeline.prepareForReuse()
    }

    public func scrollToFirstEvent(animated: Bool) {
    }

    public func scrollTo(hour24: Float, animated: Bool = true) {
    }

    public func setContentOffset(_ newValue: CGPoint, animated: Bool) {
        contentOffset = newValue
    }
}
