import UIKit
import WMF

class ColumnarCollectionViewController: ViewController {
    lazy var layout: WMFColumnarCollectionViewLayout = {
        return WMFColumnarCollectionViewLayout()
    }()
    
    @objc lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.delegate = self
        cv.dataSource = self
        scrollView = cv
        return cv
    }()

    lazy var layoutManager: ColumnarCollectionViewLayoutManager = {
        return ColumnarCollectionViewLayoutManager(view: view, collectionView: collectionView)
    }()
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wmf_addSubviewWithConstraintsToEdges(collectionView)
        collectionView.alwaysBounceVertical = true
        extendedLayoutIncludesOpaqueBars = true
    }

    @objc func contentSizeCategoryDidChange(_ notification: Notification?) {
        collectionView.reloadData()
    }

    private var isFirstAppearance = true

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if isFirstAppearance {
            isFirstAppearance = false
            viewWillHaveFirstAppearance(animated)
            updateEmptyState()
            isEmptyDidChange() // perform initial update even though the value might not have changed
        } else {
            updateEmptyState()
        }
        if let selectedIndexPaths = collectionView.indexPathsForSelectedItems {
            for selectedIndexPath in selectedIndexPaths {
                collectionView.deselectItem(at: selectedIndexPath, animated: animated)
            }
        }
        for cell in collectionView.visibleCells {
            guard let cellWithSubItems = cell as? SubCellProtocol else {
                continue
            }
            cellWithSubItems.deselectSelectedSubItems(animated: animated)
        }
    }
    
    open func viewWillHaveFirstAppearance(_ animated: Bool) {
        // subclassers can override
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            contentSizeCategoryDidChange(nil)
        }
    }
    
    // MARK: - Scroll
    
    override func scrollToTop() {
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: 0 - collectionView.contentInset.top), animated: true)
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard let hintPresenter = self as? ReadingListHintPresenter else {
            return
        }
        hintPresenter.readingListHintController?.scrollViewWillBeginDragging()
    }
    
    // MARK: - Refresh Control
    
    final var isRefreshControlEnabled: Bool = false {
        didSet {
            if isRefreshControlEnabled {
                let refreshControl = UIRefreshControl()
                refreshControl.layer.zPosition = -100
                refreshControl.addTarget(self, action: #selector(refreshControlActivated), for: .valueChanged)
                collectionView.refreshControl = refreshControl
            } else {
                collectionView.refreshControl = nil
            }
        }
    }
    
    var refreshStart: Date = Date()
    @objc func refreshControlActivated() {
        refreshStart = Date()
        self.refresh()
    }
    
    open func refresh() {
        assert(false, "default implementation shouldn't be called")
        self.endRefreshing()
    }
    
    open func endRefreshing() {
        let now = Date()
        let timeInterval = 0.5 - now.timeIntervalSince(refreshStart)
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + timeInterval, execute: {
            self.collectionView.refreshControl?.endRefreshing()
        })
    }
    
    // MARK: - Empty State
    
    var emptyViewType: WMFEmptyViewType = .none
    
    final var isEmpty = true
    final func updateEmptyState() {
        let sectionCount = numberOfSections(in: collectionView)
        
        var isCurrentlyEmpty = true
        for sectionIndex in 0..<sectionCount {
            if self.collectionView(collectionView, numberOfItemsInSection: sectionIndex) > 0 {
                isCurrentlyEmpty = false
                break
            }
        }
        
        guard isCurrentlyEmpty != isEmpty else {
            return
        }
        
        isEmpty = isCurrentlyEmpty
        
        isEmptyDidChange()
    }
    
    private var emptyViewFrame: CGRect {
        let insets = scrollView?.contentInset ?? UIEdgeInsets.zero
        let frame = UIEdgeInsetsInsetRect(view.bounds, insets)
        return frame
    }
    
    open func isEmptyDidChange() {
        if isEmpty {
            wmf_showEmptyView(of: emptyViewType, theme: theme, frame: emptyViewFrame)
        } else {
            wmf_hideEmptyView()
        }
    }
    
    override func scrollViewInsetsDidChange() {
        super.scrollViewInsetsDidChange()
        wmf_setEmptyViewFrame(emptyViewFrame)
    }
    
    // MARK: - Themeable
    
    override func apply(theme: Theme) {
        super.apply(theme: theme)
        guard viewIfLoaded != nil else {
            return
        }
        view.backgroundColor = theme.colors.baseBackground
        collectionView.backgroundColor = theme.colors.baseBackground
        collectionView.indicatorStyle = theme.scrollIndicatorStyle
        collectionView.reloadData()
        wmf_applyTheme(toEmptyView: theme)
    }
}

extension ColumnarCollectionViewController: UICollectionViewDataSource {
    open func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 0
    }
    
    open func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 0
    }
    
    open func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return collectionView.dequeueReusableCell(withReuseIdentifier: "", for: indexPath)
    }
}

extension ColumnarCollectionViewController: UICollectionViewDelegate {

}

extension ColumnarCollectionViewController: WMFColumnarCollectionViewLayoutDelegate {
    open func collectionView(_ collectionView: UICollectionView, prefersWiderColumnForSectionAt index: UInt) -> Bool {
        return index % 2 == 0
    }
    
    open func collectionView(_ collectionView: UICollectionView, estimatedHeightForHeaderInSection section: Int, forColumnWidth columnWidth: CGFloat) -> WMFLayoutEstimate {
        return WMFLayoutEstimate(precalculated: false, height: 0)
    }
    
    open func collectionView(_ collectionView: UICollectionView, estimatedHeightForFooterInSection section: Int, forColumnWidth columnWidth: CGFloat) -> WMFLayoutEstimate {
        return WMFLayoutEstimate(precalculated: false, height: 0)
    }
    
    open func collectionView(_ collectionView: UICollectionView, estimatedHeightForItemAt indexPath: IndexPath, forColumnWidth columnWidth: CGFloat) -> WMFLayoutEstimate {
        return WMFLayoutEstimate(precalculated: false, height: 0)
    }
    
    func metrics(withBoundsSize size: CGSize, readableWidth: CGFloat) -> WMFCVLMetrics {
        return WMFCVLMetrics.singleColumnMetrics(withBoundsSize: size, readableWidth: readableWidth)
    }
}

// MARK: - WMFArticlePreviewingActionsDelegate
extension ColumnarCollectionViewController: WMFArticlePreviewingActionsDelegate {
    func saveArticlePreviewActionSelected(withArticleController articleController: WMFArticleViewController, didSave: Bool, articleURL: URL) {
        if let hintPresenter = self as? ReadingListHintPresenter {
            hintPresenter.readingListHintController?.didSave(didSave, articleURL: articleURL, theme: theme)
        }
        if let eventLoggingEventValuesProviding = self as? EventLoggingEventValuesProviding {
            if didSave {
                ReadingListsFunnel.shared.logSave(category: eventLoggingEventValuesProviding.eventLoggingCategory, label: eventLoggingEventValuesProviding.eventLoggingLabel, articleURL: articleURL)
            } else {
                ReadingListsFunnel.shared.logUnsave(category: eventLoggingEventValuesProviding.eventLoggingCategory, label: eventLoggingEventValuesProviding.eventLoggingLabel, articleURL: articleURL)
            }
        }
    }
    
    func readMoreArticlePreviewActionSelected(withArticleController articleController: WMFArticleViewController) {
        articleController.wmf_removePeekableChildViewControllers()
        wmf_push(articleController, animated: true)
    }
    
    func shareArticlePreviewActionSelected(withArticleController articleController: WMFArticleViewController, shareActivityController: UIActivityViewController) {
        articleController.wmf_removePeekableChildViewControllers()
        present(shareActivityController, animated: true, completion: nil)
    }
    
    func viewOnMapArticlePreviewActionSelected(withArticleController articleController: WMFArticleViewController) {
        articleController.wmf_removePeekableChildViewControllers()
        let placesURL = NSUserActivity.wmf_URLForActivity(of: .places, withArticleURL: articleController.articleURL)
        UIApplication.shared.open(placesURL, options: [:], completionHandler: nil)
    }
}
