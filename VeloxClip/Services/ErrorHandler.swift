import Foundation
import SwiftUI

@MainActor
class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()
    
    @Published var currentError: AppError?
    @Published var showError = false
    
    private init() {}
    
    func handle(_ error: Error) {
        let appError: AppError
        
        // Handle different error types
        if let llmError = error as? LLMError {
            appError = AppError(
                title: "AI Processing Error",
                message: llmError.localizedDescription,
                details: error.localizedDescription
            )
        } else if let aiError = error as? AIService.AIServiceError {
            appError = AppError(
                title: "AI Service Error",
                message: aiError.localizedDescription,
                details: error.localizedDescription
            )
        } else {
            appError = AppError(
                title: "Error",
                message: error.localizedDescription,
                details: error.localizedDescription
            )
        }
        
        currentError = appError
        showError = true
        
        // Auto-dismiss after 5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if currentError?.id == appError.id {
                showError = false
                currentError = nil
            }
        }
    }
    
    func clear() {
        currentError = nil
        showError = false
    }
}

struct AppError: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let details: String
}

// Error view modifier
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
                Button("Show Details") {
                    // Could show detailed error view
                }
            } message: { error in
                Text(error.message)
            }
    }
}

extension View {
    func errorAlert() -> some View {
        self.modifier(ErrorAlertModifier())
    }
}

