import SwiftUI

// The presentation half of ErrorHandler.
//
// This used to live in Services/ErrorHandler.swift, which forced that file —
// and therefore the whole Services layer — to import SwiftUI purely to host an
// alert modifier. The observable error state stays in Services; how it is shown
// belongs here.
struct ErrorAlertModifier: ViewModifier {
    @ObservedObject var errorHandler = ErrorHandler.shared

    func body(content: Content) -> some View {
        content
            .alert(
                errorHandler.currentError?.title ?? "Error",
                isPresented: $errorHandler.showError,
                presenting: errorHandler.currentError
            ) { error in
                Button("OK") {
                    errorHandler.clear()
                }
            } message: { error in
                // details carries the recoverySuggestion when the error has one
                // — "Update VeloxClip to open it" is the actionable half.
                if error.details != error.message, !error.details.isEmpty {
                    Text("\(error.message)\n\n\(error.details)")
                } else {
                    Text(error.message)
                }
            }
    }
}

extension View {
    func errorAlert() -> some View {
        self.modifier(ErrorAlertModifier())
    }
}
