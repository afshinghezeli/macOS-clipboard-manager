import Foundation
import Testing

@testable import SpindleUI

@Suite
struct ResourceBundleTests {
    @Test
    func findsTheResourceBundleWithoutBundleModule() {
        #expect(Bundle.spindleUI.bundleURL.lastPathComponent == "Spindle_SpindleUI.bundle")
    }

    @Test
    func resourceBundleCarriesTheEnglishStrings() {
        let path = Bundle.spindleUI.path(
            forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en")
        #expect(path != nil)
    }
}
