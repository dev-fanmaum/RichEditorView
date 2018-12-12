//
//  RichEditor.swift
//
//  Created by Caesar Wirth on 4/1/15.
//  Copyright (c) 2015 Caesar Wirth. All rights reserved.
//

import UIKit
@objc public protocol RichViewerDelegate: class {
    
    /// Called when the inner height of the text being displayed changes
    /// Can be used to update the UI
    @objc optional func richViewer(_ viewer: RichViewer, heightDidChange height: Int)
}

/// RichEditorView is a UIView that displays richly styled text, and allows it to be edited in a WYSIWYG fashion.
@objcMembers open class RichViewer: UIView, UIScrollViewDelegate, UIWebViewDelegate, UIGestureRecognizerDelegate {
    
    // MARK: Public Properties
    
    /// Input accessory view to display over they keyboard.
    var delegate: RichViewerDelegate?
    /// Defaults to nil
    open override var inputAccessoryView: UIView? {
        get { return webView.cjw_inputAccessoryView }
        set { webView.cjw_inputAccessoryView = newValue }
    }
    
    /// The internal UIWebView that is used to display the text.
    open private(set) var webView: UIWebView
    
    /// Whether or not scroll is enabled on the view.
    open var isScrollEnabled: Bool = true {
        didSet {
            webView.scrollView.isScrollEnabled = isScrollEnabled
        }
    }
    
    /// Whether or not to allow user input in the view.
    open var isEditingEnabled: Bool {
        get { return isContentEditable }
        set { isContentEditable = newValue }
    }
    
    /// The content HTML of the text being displayed.
    /// Is continually updated as the text is being edited.
    open private(set) var contentHTML: String = ""
    
    /// The internal height of the text being displayed.
    /// Is continually being updated as the text is edited.
    open private(set) var editorHeight: Int = 0 {
        didSet {
            delegate?.richViewer?(self, heightDidChange: editorHeight)
        }
    }
    
    /// The value we hold in order to be able to set the line height before the JS completely loads.
    private var innerLineHeight: Int = 28
    
    /// The line height of the editor. Defaults to 28.
    open private(set) var lineHeight: Int {
        get {
            if isEditorLoaded, let lineHeight = Int(runJS("RE.getLineHeight();")) {
                return lineHeight
            } else {
                return innerLineHeight
            }
        }
        set {
            innerLineHeight = newValue
            runJS("RE.setLineHeight('\(innerLineHeight)px');")
        }
    }
    
    // MARK: Private Properties
    
    /// Whether or not the editor has finished loading or not yet.
    private var isEditorLoaded = false
    
    /// Value that stores whether or not the content should be editable when the editor is loaded.
    /// Is basically `isEditingEnabled` before the editor is loaded.
    private var editingEnabledVar = true
    
    /// The private internal tap gesture recognizer used to detect taps and focus the editor
    private let tapRecognizer = UITapGestureRecognizer()
    
    /// The inner height of the editor div.
    /// Fetches it from JS every time, so might be slow!
    private var clientHeight: Int {
        let heightString = runJS("document.getElementById('viewer').clientHeight;")
        return Int(heightString) ?? 0
    }
    
    // MARK: Initialization
    
    public override init(frame: CGRect) {
        webView = UIWebView()
        super.init(frame: frame)
        setup()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        webView = UIWebView()
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .white
        
        webView.frame = bounds
        webView.delegate = self
        webView.keyboardDisplayRequiresUserAction = false
        webView.scalesPageToFit = false
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.dataDetectorTypes = UIDataDetectorTypes()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        
        webView.scrollView.isScrollEnabled = isScrollEnabled
        webView.scrollView.bounces = false
        webView.scrollView.delegate = self
        webView.scrollView.clipsToBounds = false
        
        webView.cjw_inputAccessoryView = nil
        
        self.addSubview(webView)
        
        if let filePath = Bundle(for: RichEditorView.self).path(forResource: "viewer", ofType: "html") {
            let url = URL(fileURLWithPath: filePath, isDirectory: false)
            let request = URLRequest(url: url)
            webView.loadRequest(request)
        }
    }
    
    // MARK: - Rich Text Editing
    
    // MARK: Properties
    
    /// The HTML that is currently loaded in the editor view, if it is loaded. If it has not been loaded yet, it is the
    /// HTML that will be loaded into the editor view once it finishes initializing.
    public var html: String {
        get {
            return runJS("RE.getHtml();")
        }
        set {
            contentHTML = newValue
            if isEditorLoaded {
                runJS("RE.setHtml('\(newValue.escaped)');")
                updateHeight()
            }
        }
    }
    
    /// Text representation of the data that has been input into the editor view, if it has been loaded.
    public var text: String {
        return runJS("RE.getText()")
    }
    
    /// Private variable that holds the placeholder text, so you can set the placeholder before the editor loads.
    private var placeholderText: String = ""
    /// The placeholder text that should be shown when there is no user input.
    open var placeholder: String {
        get { return placeholderText }
        set {
            placeholderText = newValue
            runJS("RE.setPlaceholderText('\(newValue.escaped)');")
        }
    }
    
    
    /// The href of the current selection, if the current selection's parent is an anchor tag.
    /// Will be nil if there is no href, or it is an empty string.
    public var selectedHref: String? {
        if !hasRangeSelection { return nil }
        let href = runJS("RE.getSelectedHref();")
        if href == "" {
            return nil
        } else {
            return href
        }
    }
    
    /// Whether or not the selection has a type specifically of "Range".
    public var hasRangeSelection: Bool {
        return runJS("RE.rangeSelectionExists();") == "true" ? true : false
    }
    
    /// Whether or not the selection has a type specifically of "Range" or "Caret".
    public var hasRangeOrCaretSelection: Bool {
        return runJS("RE.rangeOrCaretSelectionExists();") == "true" ? true : false
    }
    
    /// Runs some JavaScript on the UIWebView and returns the result
    /// If there is no result, returns an empty string
    /// - parameter js: The JavaScript string to be run
    /// - returns: The result of the JavaScript that was run
    @discardableResult
    public func runJS(_ js: String) -> String {
        let string = webView.stringByEvaluatingJavaScript(from: js) ?? ""
        return string
    }
    
    
    // MARK: - Delegate Methods
    
    
    // MARK: UIScrollViewDelegate
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // We use this to keep the scroll view from changing its offset when the keyboard comes up
        if !isScrollEnabled {
            scrollView.bounds = webView.bounds
        }
    }
    
    
    // MARK: UIWebViewDelegate
    
    public func webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebView.NavigationType) -> Bool {
        
        // Handle pre-defined editor actions
        let callbackPrefix = "re-callback://"
        if request.url?.absoluteString.hasPrefix(callbackPrefix) == true {
            
            // When we get a callback, we need to fetch the command queue to run the commands
            // It comes in as a JSON array of commands that we need to parse
            let commands = runJS("RE.getCommandQueue();")
            
            if let data = commands.data(using: .utf8) {
                
                let jsonCommands: [String]
                do {
                    jsonCommands = try JSONSerialization.jsonObject(with: data) as? [String] ?? []
                } catch {
                    jsonCommands = []
                    NSLog("RichEditorView: Failed to parse JSON Commands")
                }
                
                jsonCommands.forEach(performCommand)
            }
            
            return false
        }
        
        return true
    }
    
    
    // MARK: UIGestureRecognizerDelegate
    
    /// Delegate method for our UITapGestureDelegate.
    /// Since the internal web view also has gesture recognizers, we have to make sure that we actually receive our taps.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    
    // MARK: - Private Implementation Details
    
    private var isContentEditable: Bool {
        get {
            if isEditorLoaded {
                let value = runJS("RE.editor.isContentEditable")
                editingEnabledVar = Bool(value) ?? false
                return editingEnabledVar
            }
            return editingEnabledVar
        }
        set {
            editingEnabledVar = newValue
            if isEditorLoaded {
                let value = newValue ? "true" : "false"
                runJS("RE.editor.contentEditable = \(value);")
            }
        }
    }
    
    /// The position of the caret relative to the currently shown content.
    /// For example, if the cursor is directly at the top of what is visible, it will return 0.
    /// This also means that it will be negative if it is above what is currently visible.
    /// Can also return 0 if some sort of error occurs between JS and here.
    private var relativeCaretYPosition: Int {
        let string = runJS("RE.getRelativeCaretYPosition();")
        return Int(string) ?? 0
    }
    
    private func updateHeight() {
        let heightString = runJS("document.getElementById('viewer').clientHeight;")
        let height = Int(heightString) ?? 0
        if editorHeight != height {
            editorHeight = height
        }
    }
    
    /// Scrolls the editor to a position where the caret is visible.
    /// Called repeatedly to make sure the caret is always visible when inputting text.
    /// Works only if the `lineHeight` of the editor is available.
    private func scrollCaretToVisible() {
        let scrollView = self.webView.scrollView
        
        let contentHeight = clientHeight > 0 ? CGFloat(clientHeight) : scrollView.frame.height
        scrollView.contentSize = CGSize(width: scrollView.frame.width, height: contentHeight)
        
        // XXX: Maybe find a better way to get the cursor height
        let lineHeight = CGFloat(self.lineHeight)
        let cursorHeight = lineHeight - 4
        let visiblePosition = CGFloat(relativeCaretYPosition)
        var offset: CGPoint?
        
        if visiblePosition + cursorHeight > scrollView.bounds.size.height {
            // Visible caret position goes further than our bounds
            offset = CGPoint(x: 0, y: (visiblePosition + lineHeight) - scrollView.bounds.height + scrollView.contentOffset.y)
            
        } else if visiblePosition < 0 {
            // Visible caret position is above what is currently visible
            var amount = scrollView.contentOffset.y + visiblePosition
            amount = amount < 0 ? 0 : amount
            offset = CGPoint(x: scrollView.contentOffset.x, y: amount)
            
        }
        
        if let offset = offset {
            scrollView.setContentOffset(offset, animated: true)
        }
    }
    
    /// Called when actions are received from JavaScript
    /// - parameter method: String with the name of the method and optional parameters that were passed in
    private func performCommand(_ method: String) {
        if method.hasPrefix("ready") {
            // If loading for the first time, we have to set the content HTML to be displayed
            if !isEditorLoaded {
                isEditorLoaded = true
                html = contentHTML
                isContentEditable = editingEnabledVar
                placeholder = placeholderText
                lineHeight = innerLineHeight
            }
            updateHeight()
        }
        else if method.hasPrefix("input") {
            scrollCaretToVisible()
            let content = runJS("RE.getHtml()")
            contentHTML = content
            updateHeight()
        }
        else if method.hasPrefix("updateHeight") {
            updateHeight()
        }
        else if method.hasPrefix("focus") {
        }
        else if method.hasPrefix("blur") {
        }
        else if method.hasPrefix("action/") {
            let content = runJS("RE.getHtml()")
            contentHTML = content
            
            // If there are any custom actions being called
            // We need to tell the delegate about it
            let actionPrefix = "action/"
            let range = method.range(of: actionPrefix)!
            let action = method.replacingCharacters(in: range, with: "")
        }
    }
    
}
