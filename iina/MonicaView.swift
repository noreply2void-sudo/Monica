import Cocoa
import ImageIO

class MonicaView: NSView {
    private let imageView = NSImageView()
    private var imageFiles: [URL] = []
    private var currentIndex = 0
    private var currentFileURL: URL?
    private var currentScale: CGFloat = 1.0
    private var originalImageSize = NSSize.zero
    private var showingExif = false
    private var directoryLoaded = false
    
    private let exifLabel = NSTextField()
    private let hintLabel = NSTextField()
    
    private static let imageExtensions = ["jpg", "jpeg", "png", "gif", "tiff", "bmp", "webp"]
    private static let maxScale: CGFloat = 5.0
    private static let minScale: CGFloat = 0.1
    private static let scaleFactor: CGFloat = 0.1
    
    weak var delegate: MonicaViewDelegate?
    
    override var acceptsFirstResponder: Bool { true }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        imageView.frame = bounds
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        addSubview(imageView)
        
        exifLabel.frame = NSRect(x: 10, y: 10, width: 300, height: 200)
        exifLabel.backgroundColor = NSColor.black.withAlphaComponent(0.8)
        exifLabel.textColor = NSColor.white
        exifLabel.font = NSFont.systemFont(ofSize: 12)
        exifLabel.isEditable = false
        exifLabel.isSelectable = true
        exifLabel.isBordered = false
        exifLabel.isHidden = true
        addSubview(exifLabel)
        
        hintLabel.frame = NSRect(x: 100, y: 200, width: 600, height: 200)
        hintLabel.backgroundColor = NSColor.clear
        hintLabel.textColor = NSColor.white
        hintLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        hintLabel.isEditable = false
        hintLabel.isSelectable = false
        hintLabel.isBordered = false
        hintLabel.alignment = .center
        hintLabel.stringValue = """
MonicaView
68kb // 极致macOS多图看图工具

切换 ：← → （或点击图片）     删除 ：D


反馈与支持 // QQ: 123766847
"""
        addSubview(hintLabel)
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 126: previousImage()
        case 124, 125: nextImage()
        case 2: deleteCurrentImage()
        case 34: toggleExifInfo()
        default: super.keyDown(with: event)
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        currentScale = event.deltaY > 0 
            ? min(currentScale + Self.scaleFactor, Self.maxScale)
            : max(currentScale - Self.scaleFactor, Self.minScale)
        updateImageTransform()
    }
    
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        
        if !directoryLoaded {
            selectFolderAndLoadImages()
            return
        }
        
        if event.locationInWindow.x < bounds.width / 2 {
            previousImage()
        } else {
            nextImage()
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }
    
    func loadFile(_ fileURL: URL) {
        currentFileURL = fileURL
        
        if Self.imageExtensions.contains(fileURL.pathExtension.lowercased()),
           FileManager.default.fileExists(atPath: fileURL.path),
           let image = NSImage(contentsOf: fileURL) {
            
            originalImageSize = image.size
            currentScale = 1.0
            resizeWindowForImage(image)
            imageView.image = image
            hintLabel.isHidden = true
            imageFiles = [fileURL]
            currentIndex = 0
            directoryLoaded = false
            updateWindowTitle()
            delegate?.monicaView(self, didLoadFile: fileURL)
        } else if isVideoFile(fileURL) {
            // Handle video file - delegate to main app
            delegate?.monicaView(self, didRequestOpenVideo: fileURL)
        }
    }
    
    private func isVideoFile(_ fileURL: URL) -> Bool {
        let videoExtensions = ["mp4", "mov", "mkv", "avi", "wmv", "flv", "webm", "m4v"]
        return videoExtensions.contains(fileURL.pathExtension.lowercased())
    }
    
    private func resizeWindowForImage(_ image: NSImage) {
        guard let window = window else { return }
        
        let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1920, height: 1080)
        let maxWidth = screenSize.width * 0.9
        let maxHeight = screenSize.height * 0.9
        
        var windowWidth = image.size.width
        var windowHeight = image.size.height
        
        if windowWidth > maxWidth || windowHeight > maxHeight {
            let ratio = image.size.width / image.size.height
            if ratio > maxWidth / maxHeight {
                windowWidth = maxWidth
                windowHeight = windowWidth / ratio
            } else {
                windowHeight = maxHeight
                windowWidth = windowHeight * ratio
            }
        }
        
        windowWidth = max(windowWidth, 400)
        windowHeight = max(windowHeight, 400)
        
        window.setFrame(NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: windowWidth, height: windowHeight), display: true, animate: true)
        imageView.frame = NSRect(origin: .zero, size: NSSize(width: windowWidth, height: windowHeight))
    }
    
    private func updateImageTransform() {
        let scaledWidth = originalImageSize.width * currentScale
        let scaledHeight = originalImageSize.height * currentScale
        guard let window = window else { return }
        
        imageView.frame = NSRect(x: (window.contentView?.frame.size.width ?? bounds.width - scaledWidth) / 2, 
                               y: (window.contentView?.frame.size.height ?? bounds.height - scaledHeight) / 2, 
                               width: scaledWidth, 
                               height: scaledHeight)
    }
    
    private func selectFolderAndLoadImages() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "打开同级文件夹以浏览所有图片"
        
        if let currentFile = currentFileURL {
            panel.directoryURL = currentFile.deletingLastPathComponent()
        }
        
        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
            imageFiles = contents.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
            imageFiles.sort { $0.lastPathComponent < $1.lastPathComponent }
            
            if let currentFile = currentFileURL, let index = imageFiles.firstIndex(of: currentFile) {
                currentIndex = index + 1 < imageFiles.count ? index + 1 : index
            } else {
                currentIndex = 0
            }
            
            directoryLoaded = true
            updateWindowTitle()
            if !imageFiles.isEmpty { updateImageView() }
        } catch {}
    }
    
    private func updateImageView() {
        guard !imageFiles.isEmpty, currentIndex < imageFiles.count else {
            imageView.image = nil
            hintLabel.isHidden = false
            return
        }
        
        let imageURL = imageFiles[currentIndex]
        guard let image = NSImage(contentsOf: imageURL) else { return }
        
        originalImageSize = image.size
        currentScale = 1.0
        resizeWindowForImage(image)
        imageView.image = image
        hintLabel.isHidden = true
        window?.makeFirstResponder(self)
        updateWindowTitle()
        delegate?.monicaView(self, didLoadFile: imageURL)
    }
    
    private func previousImage() {
        guard directoryLoaded else { selectFolderAndLoadImages(); return }
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        updateImageView()
    }
    
    private func nextImage() {
        guard directoryLoaded else { selectFolderAndLoadImages(); return }
        guard currentIndex < imageFiles.count - 1 else { return }
        currentIndex += 1
        updateImageView()
    }
    
    private func deleteCurrentImage() {
        guard !imageFiles.isEmpty, currentIndex < imageFiles.count else { return }
        
        let fileURL = imageFiles[currentIndex]
        let alert = NSAlert()
        alert.messageText = "确认删除"
        alert.informativeText = "确定要删除文件 \"\(fileURL.lastPathComponent)\" 吗？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            imageFiles.remove(at: currentIndex)
            if currentIndex >= imageFiles.count { currentIndex = max(0, imageFiles.count - 1) }
            if !imageFiles.isEmpty { updateImageView() } else { imageView.image = nil; updateWindowTitle() }
            delegate?.monicaView(self, didDeleteFile: fileURL)
        } catch {}
    }
    
    private func updateWindowTitle() {
        guard let window = window else { return }
        if let fileName = imageFiles.isEmpty ? nil : imageFiles[currentIndex].lastPathComponent {
            window.title = "\(fileName) ← →翻页d删除-MonicaView"
        } else {
            window.title = "图片文件右键\"打开方式\"→\"使用MonicaView打开\"，体验极致看图体验：← →翻页d删除"
        }
    }
    
    private func toggleExifInfo() {
        showingExif.toggle()
        exifLabel.isHidden = !showingExif
        if showingExif, let currentFile = currentFileURL ?? (imageFiles.isEmpty ? nil : imageFiles[currentIndex]) {
            loadExifInfo(currentFile)
        }
    }
    
    private func loadExifInfo(_ fileURL: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            exifLabel.stringValue = "无法读取EXIF信息"
            return
        }
        
        var info = ""
        
        if let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            info += "尺寸: \(width) x \(height)\n"
        }
        
        if let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dateTime = exifDict[kCGImagePropertyExifDateTimeOriginal] as? String { info += "拍摄时间: \(dateTime)\n" }
            if let iso = exifDict[kCGImagePropertyExifISOSpeedRatings] as? [Int], let isoValue = iso.first { info += "ISO: \(isoValue)\n" }
            if let fNumber = exifDict[kCGImagePropertyExifFNumber] as? Double { info += "光圈: f\(String(format: "%.1f", fNumber))\n" }
            if let exposureTime = exifDict[kCGImagePropertyExifExposureTime] as? Double { info += "快门: \(String(format: "%.1f", exposureTime))s\n" }
            if let focalLength = exifDict[kCGImagePropertyExifFocalLength] as? Double { info += "焦距: \(String(format: "%.1f", focalLength))mm\n" }
        }
        
        if let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let make = tiffDict[kCGImagePropertyTIFFMake] as? String,
           let model = tiffDict[kCGImagePropertyTIFFModel] as? String {
            info += "设备: \(make) \(model)\n"
        }
        
        exifLabel.stringValue = info.isEmpty ? "无EXIF信息" : info
    }
}

protocol MonicaViewDelegate: AnyObject {
    func monicaView(_ monicaView: MonicaView, didLoadFile fileURL: URL)
    func monicaView(_ monicaView: MonicaView, didDeleteFile fileURL: URL)
    func monicaView(_ monicaView: MonicaView, didRequestOpenVideo fileURL: URL)
}

class MonicaViewController: NSViewController {
    private let monicaView = MonicaView()
    
    weak var delegate: MonicaViewDelegate? {
        didSet {
            monicaView.delegate = delegate
        }
    }
    
    override func loadView() {
        monicaView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view = monicaView
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        // 确保MonicaView在视图出现时获得第一响应者状态
        view.window?.makeFirstResponder(monicaView)
    }
    
    func loadFile(_ fileURL: URL) {
        monicaView.loadFile(fileURL)
    }
}
