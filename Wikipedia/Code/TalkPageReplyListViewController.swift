
import UIKit

protocol TalkPageReplyListViewControllerDelegate: class {
    func tappedLink(_ url: URL, viewController: TalkPageReplyListViewController)
    func tappedPublish(topic: TalkPageTopic, composeText: String, viewController: TalkPageReplyListViewController)
}

class TalkPageReplyListViewController: ColumnarCollectionViewController {
    
    weak var delegate: TalkPageReplyListViewControllerDelegate?
    
    private let topic: TalkPageTopic
    private let dataStore: MWKDataStore
    private var fetchedResultsController: NSFetchedResultsController<TalkPageReply>
    
    private let reuseIdentifier = "TalkPageReplyCell"
    
    private var collectionViewUpdater: CollectionViewUpdater<TalkPageReply>!
    
    private lazy var publishButton: UIBarButtonItem = {
        let publishButton = UIBarButtonItem(title: CommonStrings.publishTitle, style: .done, target: self, action: #selector(tappedPublish(_:)))
        publishButton.tintColor = theme.colors.link
        return publishButton
    }()
    
    private var composeText: String?
    private var footerView: TalkPageReplyFooterView?
    private var headerView: TalkPageHeaderView?
    private var originalFooterViewFrame: CGRect?
    
    private var backgroundTapGestureRecognizer: UITapGestureRecognizer!
    private var replyBarButtonItem: UIBarButtonItem!

    private var showingCompose = false {
        didSet {
            if showingCompose != oldValue {
                footerView?.showingCompose = showingCompose
                if let layoutCopy = layout.copy() as? ColumnarCollectionViewLayout {
                    collectionView.setCollectionViewLayout(layoutCopy, animated: true)
                    if showingCompose == true {
                        scrollToBottom()
                    }
                } else {
                    collectionView.reloadData()
                    collectionView.layoutIfNeeded()
                    scrollToBottom()
                }
                
            }
            
            if showingCompose {
                publishButton.isEnabled = false
                navigationItem.rightBarButtonItem = publishButton
                navigationItem.title = replyString
                navigationBar.updateNavigationItems()
            } else {
                navigationItem.rightBarButtonItem = replyBarButtonItem
                navigationBar.updateNavigationItems()
            }
        }
    }
    
    lazy private var fakeProgressController: FakeProgressController = {
        let progressController = FakeProgressController(progress: navigationBar, delegate: navigationBar)
        progressController.delay = 0.0
        return progressController
    }()
    
    private let replyString = WMFLocalizedString("talk-page-reply-title", value: "Reply", comment: "This header label is displayed at the top of a talk page thread once the user taps Reply.")
    
    required init(dataStore: MWKDataStore, topic: TalkPageTopic) {
        self.dataStore = dataStore
        self.topic = topic
        
        let request: NSFetchRequest<TalkPageReply> = TalkPageReply.fetchRequest()
        request.predicate = NSPredicate(format: "topic == %@",  topic)
        request.sortDescriptors = [NSSortDescriptor(key: "sort", ascending: true)]
        self.fetchedResultsController = NSFetchedResultsController(fetchRequest: request, managedObjectContext: dataStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        registerCells()
        setupCollectionViewUpdater()
        setupBackgroundTap()
        setupNavigationBar()
        
        collectionView.keyboardDismissMode = .onDrag
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    func postDidBegin() {
        fakeProgressController.start()
        publishButton.isEnabled = false
        footerView?.composeTextView.isUserInteractionEnabled = false
    }
    
    func postDidEnd() {
        fakeProgressController.stop()
        publishButton.isEnabled = true
        showingCompose = false
        footerView?.resetCompose()
    }

    private var previousKeyboardFrame: CGRect?

    override func keyboardWillChangeFrame(_ notification: Notification) {
        super.keyboardWillChangeFrame(notification)
        if let footerView = footerView,
            let keyboardFrame = keyboardFrame {
            
            if keyboardFrame.height == 0 {
                return
            }
            
            var convertedComposeTextViewFrame = footerView.composeView.convert(footerView.composeTextView.frame, to: view)
            
            //shift keyboard frame if necessary so compose view is in visible window
            let navBarHeight = navigationBar.visibleHeight
            let newHeight = keyboardFrame.minY - navBarHeight - footerView.beKindView.frame.height
            
            convertedComposeTextViewFrame.origin.y = navBarHeight
            convertedComposeTextViewFrame.size.height = newHeight
            
            let newConvertedComposeTextViewFrame = footerView.composeView.convert(convertedComposeTextViewFrame, from: view)
        
            let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0.2
            let curve = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UIView.AnimationOptions) ?? UIView.AnimationOptions.curveLinear
            
            footerView.dividerView.isHidden = true

            let animateCellsIfKeyboardChangedFrame = {
                guard self.previousKeyboardFrame != keyboardFrame else {
                    return
                }
                self.updateAlphaOfVisibleCells(newAlpha: 0)
            }

            UIView.animate(withDuration: duration, delay: 0.0, options: curve, animations: {
                footerView.composeTextView.frame = newConvertedComposeTextViewFrame
                footerView.beKindView.frame.origin.y = newConvertedComposeTextViewFrame.minY + newConvertedComposeTextViewFrame.height
                animateCellsIfKeyboardChangedFrame()
            }, completion: nil)
        }

        previousKeyboardFrame = keyboardFrame
    }
    
    override func keyboardDidChangeFrame(from oldKeyboardFrame: CGRect?, newKeyboardFrame: CGRect?) {
        //no-op, avoiding updateScrollViewInsets() call in superclass
    }

    private func updateAlphaOfVisibleCells(newAlpha: CGFloat) {
        for visibleCell in collectionView.visibleCells {
            guard visibleCell.alpha != newAlpha else {
                continue
            }
            visibleCell.alpha = newAlpha
        }
    }
    
    override func keyboardWillHide(_ notification: Notification) {
        super.keyboardWillHide(notification)
        
        footerView?.dividerView.isHidden = false
        
        let keyboardAnimationDuration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval) ?? 0.2
        let duration = keyboardAnimationDuration == 0 ? 0.2 : keyboardAnimationDuration
        
        UIView.animate(withDuration: duration, animations: {
            self.updateAlphaOfVisibleCells(newAlpha: 1)
            self.footerView?.resetComposeTextViewFrame()
            self.footerView?.resetBeKindViewFrame()
        })
    }
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)

        //todo: should refactor to lean on NavigationBar's extendedView
        if let headerView = headerView {
            navigationBar.shadowAlpha = (collectionView.contentOffset.y + collectionView.adjustedContentInset.top) > headerView.frame.height ? 1 : 0
            
            let convertedHeaderTitleFrame = headerView.convert(headerView.titleLabel.frame, to: view)
            let oldTitle = navigationItem.title
            let newTitle = (collectionView.contentOffset.y + collectionView.adjustedContentInset.top) > convertedHeaderTitleFrame.maxY ? topic.title : nil
            if oldTitle != newTitle {
                navigationItem.title = showingCompose ? replyString : newTitle
                navigationBar.updateNavigationItems()
            }
        } else {
            navigationBar.shadowAlpha = 0
        }
        
    }
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        guard let sectionsCount = fetchedResultsController.sections?.count else {
                return 0
        }
        return sectionsCount
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let sections = fetchedResultsController.sections,
            section < sections.count else {
                return 0
        }
        return sections[section].numberOfObjects
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as? TalkPageReplyCell else {
                return UICollectionViewCell()
        }
        
        configure(cell: cell, at: indexPath)
        return cell
    }
    
    override func collectionView(_ collectionView: UICollectionView, estimatedHeightForItemAt indexPath: IndexPath, forColumnWidth columnWidth: CGFloat) -> ColumnarCollectionViewLayoutHeightEstimate {
        var estimate = ColumnarCollectionViewLayoutHeightEstimate(precalculated: false, height: 54)
        guard let placeholderCell = layoutManager.placeholder(forCellWithReuseIdentifier: reuseIdentifier) as? TalkPageReplyCell else {
            return estimate
        }
        configure(cell: placeholderCell, at: indexPath)
        estimate.height = placeholderCell.sizeThatFits(CGSize(width: columnWidth, height: UIView.noIntrinsicMetric), apply: false).height
        estimate.precalculated = true
        return estimate
    }
    
    override func metrics(with size: CGSize, readableWidth: CGFloat, layoutMargins: UIEdgeInsets) -> ColumnarCollectionViewLayoutMetrics {
        return ColumnarCollectionViewLayoutMetrics.tableViewMetrics(with: size, readableWidth: readableWidth, layoutMargins: layoutMargins)
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionHeader,
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: TalkPageHeaderView.identifier, for: indexPath) as? TalkPageHeaderView {
                headerView = header
                configure(header: header)
                return header
        }
        
        if kind == UICollectionView.elementKindSectionFooter,
            let footer = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: TalkPageReplyFooterView.identifier, for: indexPath) as? TalkPageReplyFooterView {
            self.footerView = footer
            configure(footer: footer)
            return footer
        }
        
        return UICollectionReusableView()
    }
    
    override func collectionView(_ collectionView: UICollectionView, estimatedHeightForHeaderInSection section: Int, forColumnWidth columnWidth: CGFloat) -> ColumnarCollectionViewLayoutHeightEstimate {
        
        var estimate = ColumnarCollectionViewLayoutHeightEstimate(precalculated: false, height: 100)
        guard let header = layoutManager.placeholder(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: TalkPageHeaderView.identifier) as? TalkPageHeaderView else {
            return estimate
        }
        
        configure(header: header)
        estimate.height = header.sizeThatFits(CGSize(width: columnWidth, height: UIView.noIntrinsicMetric), apply: false).height
        estimate.precalculated = true
        return estimate
    }
    
    override func collectionView(_ collectionView: UICollectionView, estimatedHeightForFooterInSection section: Int, forColumnWidth columnWidth: CGFloat) -> ColumnarCollectionViewLayoutHeightEstimate {
        var estimate = ColumnarCollectionViewLayoutHeightEstimate(precalculated: false, height: 100)
        guard let footer = layoutManager.placeholder(forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: TalkPageReplyFooterView.identifier) as? TalkPageReplyFooterView else {
            return estimate
        }
        configure(footer: footer)
        estimate.height = footer.sizeThatFits(CGSize(width: columnWidth, height: UIView.noIntrinsicMetric), apply: false).height
        estimate.precalculated = true
        return estimate
    }

    override func apply(theme: Theme) {
        super.apply(theme: theme)
        view.backgroundColor = theme.colors.paperBackground
    }
}

//MARK: CollectionViewUpdaterDelegate

extension TalkPageReplyListViewController: CollectionViewUpdaterDelegate {
    func collectionViewUpdater<T>(_ updater: CollectionViewUpdater<T>, didUpdate collectionView: UICollectionView) where T : NSFetchRequestResult {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? TalkPageTopicCell,
                let title = fetchedResultsController.object(at: indexPath).text else {
                    continue
            }
            
            cell.configure(title: title)
        }
    }
    
    func collectionViewUpdater<T>(_ updater: CollectionViewUpdater<T>, updateItemAtIndexPath indexPath: IndexPath, in collectionView: UICollectionView) where T : NSFetchRequestResult {
        //no-op
    }
}

//MARK: Private

private extension TalkPageReplyListViewController {
    
    func registerCells() {
        layoutManager.register(TalkPageReplyCell.self, forCellWithReuseIdentifier: reuseIdentifier, addPlaceholder: true)
        layoutManager.register(TalkPageHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: TalkPageHeaderView.identifier, addPlaceholder: true)
        layoutManager.register(TalkPageReplyFooterView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter, withReuseIdentifier: TalkPageReplyFooterView.identifier, addPlaceholder: true)
    }
    
    func setupCollectionViewUpdater() {
        collectionViewUpdater = CollectionViewUpdater(fetchedResultsController: fetchedResultsController, collectionView: collectionView)
        collectionViewUpdater?.delegate = self
        collectionViewUpdater?.performFetch()
    }
    
    func setupNavigationBar() {
        navigationBar.isBarHidingEnabled = false
        navigationBar.shadowAlpha = 0
        let replyImage = UIImage(named: "reply")
        replyBarButtonItem = UIBarButtonItem(image: replyImage, style: .plain, target: self, action: #selector(tappedReplyNavigationItem(_:)))
        replyBarButtonItem.tintColor = theme.colors.link
        navigationItem.rightBarButtonItem = replyBarButtonItem
        navigationItem.title = nil
        navigationBar.updateNavigationItems()
    }
    
    @objc func tappedPublish(_ sender: UIBarButtonItem) {
        
        guard let composeText = composeText,
            composeText.count > 0 else {
                assertionFailure("User should be able to tap Publish if they have not written a reply.")
                return
        }
        view.endEditing(true)
        delegate?.tappedPublish(topic: topic, composeText: composeText, viewController: self)
    }
    
    @objc func tappedReplyNavigationItem(_ sender: UIBarButtonItem) {
        
        showingCompose = true
    }
    
    func setupBackgroundTap() {
        backgroundTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tappedBackground(_:)))
        view.addGestureRecognizer(backgroundTapGestureRecognizer)
    }
    
    @objc func tappedBackground(_ tapGestureRecognizer: UITapGestureRecognizer) {
        view.endEditing(true)
    }
    
    func configure(header: TalkPageHeaderView) {
        
        guard let title = topic.title else {
                return
        }
        
        let headerText = WMFLocalizedString("talk-page-topic-title", value: "Discussion", comment: "This header label is displayed at the top of a talk page topic thread.").localizedUppercase
        
        let viewModel = TalkPageHeaderView.ViewModel(header: headerText, title: title, info: nil)
        
        header.configure(viewModel: viewModel)
        header.layoutMargins = layout.itemLayoutMargins
        header.apply(theme: theme)
    }
    
    func configure(footer: TalkPageReplyFooterView) {
        footer.delegate = self
        footer.showingCompose = showingCompose
        footer.layoutMargins = layout.itemLayoutMargins
        footer.layer.zPosition = 999
        footer.apply(theme: theme)
    }
    
    func configure(cell: TalkPageReplyCell, at indexPath: IndexPath) {
        let item = fetchedResultsController.object(at: indexPath)
        guard let title = item.text,
        item.depth >= 0 else {
            assertionFailure("Invalid depth")
            return
        }
        
        cell.delegate = self
        cell.configure(title: title, depth: UInt(item.depth))
        cell.layoutMargins = layout.itemLayoutMargins
        cell.apply(theme: theme)
    }
    
    func scrollToBottom() {
        let bottomOffset = CGPoint(x: 0, y: (collectionView.contentSize.height - collectionView.frame.size.height) + collectionView.adjustedContentInset.bottom)
        scrollView?.setContentOffset(bottomOffset, animated: true)
    }
}

extension TalkPageReplyListViewController: TalkPageReplyCellDelegate {
    func tappedLink(_ url: URL, cell: TalkPageReplyCell) {
        
        delegate?.tappedLink(url, viewController: self)
    }
}

extension TalkPageReplyListViewController: ReplyButtonFooterViewDelegate {
    func composeTextDidChange(text: String?) {
        publishButton.isEnabled = text?.count ?? 0 > 0
        composeText = text
    }
    
    func tappedReply(from view: TalkPageReplyFooterView) {

        showingCompose = !showingCompose
        originalFooterViewFrame = footerView?.frame
    }
    
    var collectionViewFrame: CGRect {
        return collectionView.frame
    }
}
