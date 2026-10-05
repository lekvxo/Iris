import SwiftUI
import UIKit

// UIKit gives predictable select-all behavior with the headset keyboard.
struct AddressField: UIViewRepresentable {
    // The current page's address. Editing never writes back to it.
    let text: String
    var submit: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = "Search or enter a website"
        field.borderStyle = .roundedRect
        field.keyboardType = .webSearch
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .go
        field.clearButtonMode = .whileEditing
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        // A long address must scroll inside the field, rather than determine the
        // toolbar's width or extend under adjacent controls.
        CGSize(width: proposal.width ?? 180, height: proposal.height ?? 44)
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if !field.isFirstResponder { field.text = text }
    }
    @MainActor final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AddressField
        init(_ parent: AddressField) { self.parent = parent }
        func textFieldDidBeginEditing(_ field: UITextField) {
            DispatchQueue.main.async { field.selectAll(nil) }
        }
        // Leaving the field without submitting puts the page's address back.
        func textFieldDidEndEditing(_ field: UITextField) { field.text = parent.text }
        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.submit(field.text ?? "")
            field.resignFirstResponder()
            return true
        }
    }
}
