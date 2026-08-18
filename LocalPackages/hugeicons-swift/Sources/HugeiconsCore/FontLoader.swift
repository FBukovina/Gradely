import SwiftUI
import CoreText

public enum HugeiconsFontLoader {
    private static var urlToPostScriptName: [URL: String] = [:]
    private static var postScriptNameToStyle: [String: HugeiconsStyle] = [:]
    private static let lock = NSLock()

    @discardableResult
    public static func registerFontOnce(from bundle: Bundle, fontFilename: String, style: HugeiconsStyle? = nil) -> String? {
        guard let url = bundle.url(forResource: fontFilename, withExtension: nil) else {
            return nil
        }
        lock.lock()
        if let existing = urlToPostScriptName[url] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        var registrationError: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)

        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(dataProvider),
              let postScriptName = cgFont.postScriptName as String? else {
            return nil
        }

        lock.lock()
        urlToPostScriptName[url] = postScriptName
        if let style = style {
            postScriptNameToStyle[postScriptName] = style
        }
        lock.unlock()
        return postScriptName
    }

    public static func font(from bundle: Bundle, fontFilename: String, size: CGFloat, style: HugeiconsStyle? = nil) -> Font {
        guard let postScriptName = registerFontOnce(from: bundle, fontFilename: fontFilename, style: style) else {
            return .system(size: size)
        }
        return .custom(postScriptName, size: size)
    }
    
    public static func getStyle(for postScriptName: String) -> HugeiconsStyle? {
        lock.lock()
        defer { lock.unlock() }
        return postScriptNameToStyle[postScriptName]
    }
}


