import SwiftUI
import MRTCore
import MRTShared

extension View {
    /// iPad: present sheets as form sheets (iPadOS 18+ `presentationSizing`).
    /// On iPhone, and on iPadOS 17, the system default applies (iPad already
    /// uses a form sheet there); detents keep working on iPhone.
    @ViewBuilder
    func adaptiveSheetSizing() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.form)
        } else {
            self
        }
    }
}
