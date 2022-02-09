//
//  LaunchController.swift
//  XIV on Mac
//
//  Created by Marc-Aurel Zent on 02.02.22.
//

import Cocoa

class LaunchController: NSViewController, NSWindowDelegate {
    
    var loginSheetWinController: NSWindowController?
    var settings: FFXIVSettings = FFXIVSettings()
    var newsTable = FrontierTableView(iconText: "􀤦")
    var topicsTable = FrontierTableView(iconText: "􀥅")
    
    @IBOutlet private var loginButton: NSButton!
    @IBOutlet private var userField: NSTextField!
    @IBOutlet private var passwdField: NSTextField!
    @IBOutlet private var otpField: NSTextField!
    @IBOutlet private var scrollView: AnimatingScrollView!
    @IBOutlet private var newsView: NSScrollView!
    @IBOutlet private var topicsView: NSScrollView!
    
    override func loadView() {
        super.loadView()
        newsView.documentView = newsTable.tableView
        topicsView.documentView = topicsTable.tableView
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        update(FFXIVSettings.storedSettings())
        loginSheetWinController = storyboard?.instantiateController(withIdentifier: "LoginSheet") as? NSWindowController
        view.window?.delegate = self
        view.window?.isMovableByWindowBackground = true
        DispatchQueue.global(qos: .userInteractive).async {
            if let frontier = Frontier.info {
                self.populateNews(frontier)
            }
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
            NSApp.hide(nil)
            return false
        }
    
    private func populateNews(_ info: Frontier.Info) {
        DispatchQueue.main.async {
            self.scrollView.banners = info.banner
            self.topicsTable.add(items: info.topics)
            self.newsTable.add(items: info.pinned + info.news)
        }
    }
    
    private func update(_ settings: FFXIVSettings) {
        settings.serialize()
        self.settings = settings
        userField.stringValue = settings.credentials?.username ?? ""
        passwdField.stringValue = settings.credentials?.password ?? ""
    }
    
    @IBAction func doLogin(_ sender: Any) {
        view.window?.beginSheet(loginSheetWinController!.window!)
        settings.credentials = FFXIVLoginCredentials(username: userField.stringValue, password: passwdField.stringValue, oneTimePassword: otpField.stringValue)
        doLogin()
    }
    
    func doLogin() {
        let queue = OperationQueue()
        let op = LoginOperation(settings: settings)
        op.completionBlock = {
            switch op.loginResult {
            case .success(let sid, let updatedSettings)?:
                DispatchQueue.main.async {
                    self.startGame(sid: sid, settings: updatedSettings)
                }
            case .incorrectCredentials:
                DispatchQueue.main.async {
                    self.loginSheetWinController?.window?.close()
                    self.settings.credentials!.deleteLogin()
                    var updatedSettings = self.settings
                    updatedSettings.credentials = nil
                    self.update(updatedSettings)
                    self.otpField.stringValue = ""
                }
            default:
                DispatchQueue.main.async {
                    self.loginSheetWinController?.window?.close()
                }
            }
        }
        queue.addOperation(op)
    }
    
    func startGame(sid: String, settings: FFXIVSettings) {
        let queue = OperationQueue()
        let op = StartGameOperation(settings: settings, sid: sid)
        queue.addOperation(op)
    }

}

final class BannerView: NSImageView {
    
    var banner: Frontier.Info.Banner? {
        didSet {
            self.image = NSImage(contentsOf: URL(string: banner!.lsbBanner)!)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if let banner = banner {
            let url = URL(string: banner.link)!
            NSWorkspace.shared.open(url)
        }
    }

}

final class AnimatingScrollView: NSScrollView {
    
    private var width: CGFloat  {
        return self.contentSize.width
    }
    
    private var height: CGFloat  {
        return self.contentSize.height
    }
    
    private let animationDuration = 2.0
    private let stayDuration = 8.0
    private var index = 0
    private var timer = Timer()
    
    var banners: [Frontier.Info.Banner]? {
        didSet {
            let banners = banners!
            self.documentView?.setFrameSize(NSSize(width: width * CGFloat(banners.count), height: height))
            for (i, banner) in banners.enumerated() {
                let bannerView = BannerView()
                bannerView.frame = CGRect(x: CGFloat(i) * width, y: 0, width: width, height: height)
                bannerView.imageScaling = .scaleNone
                bannerView.banner = banner
                self.documentView?.addSubview(bannerView)
            }
            self.startTimer()
        }
    }
    
    
    private func startTimer() {
        self.timer.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: stayDuration, repeats: true, block: { _ in
            self.animate()
            })
    }
    
    // This will override and cancel any running scroll animations
    override public func scroll(_ clipView: NSClipView, to point: NSPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView.setBoundsOrigin(point)
        CATransaction.commit()
        super.scroll(clipView, to: point)
        index = Int(floor((point.x + width / 2) / width))
        let snap_x = CGFloat(index) * width
        scroll(toPoint: NSPoint(x: snap_x, y: 0), animationDuration: animationDuration)
        self.startTimer()
    }

    private func scroll(toPoint: NSPoint, animationDuration: Double) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = animationDuration
        contentView.animator().setBoundsOrigin(toPoint)
        reflectScrolledClipView(contentView)
        NSAnimationContext.endGrouping()
    }
    
    private func animate() {
        if let banners = banners {
            index = (index + 1) % banners.count
            self.scroll(toPoint: NSPoint(x: Int(width) * index, y: 0), animationDuration: animationDuration)
        }
    }

}

class FrontierTableView: NSObject {
    static let columnText = "text"
    static let columnIcon = "icon"
    
    var items: [Frontier.Info.News] = [] {
        didSet {
            tableView.reloadData()
        }
    }
    
    var iconText: String
    var tableView: NSTableView
    
    init(iconText: String) {
        self.iconText = iconText
        tableView = NSTableView(frame: .zero)
        super.init()
        tableView.intercellSpacing = NSSize(width: 0, height: 9)
        tableView.rowSizeStyle = .large
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        let icon = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: FrontierTableView.columnIcon))
        let text = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: FrontierTableView.columnText))
        icon.width = 20
        text.width = 433
        tableView.addTableColumn(icon)
        tableView.addTableColumn(text)
        tableView.action = #selector(onItemClicked)
    }
        
    func add(items: [Frontier.Info.News]) {
        self.items += items
    }
    
    @objc private func onItemClicked() {
        print("row \(tableView.clickedRow), col \(tableView.clickedColumn) clicked")
    }
}


extension FrontierTableView: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch (tableColumn?.identifier)!.rawValue {
        case FrontierTableView.columnIcon:
            return createCell(name: iconText)
        case FrontierTableView.columnText:
            return createCell(name: items[row].title)
        default:
            fatalError("FrontierTableView identifier not found")
        }
    }
    
    private func createCell(name: String) -> NSView {
        let text = NSTextField(string: name)
        text.cell?.usesSingleLineMode = false
        text.cell?.wraps = true
        text.cell?.lineBreakMode = .byWordWrapping
        text.isEditable = false
        text.isBordered = false
        text.drawsBackground = false
        text.preferredMaxLayoutWidth = 433
        return text
    }

    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return createCell(name: items[row].title).intrinsicContentSize.height
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }
    
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = NSTableRowView()
        rowView.isEmphasized = false
        return rowView
    }
}

