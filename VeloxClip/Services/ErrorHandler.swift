import Foundation
import Combine

@MainActor
class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()
    
    @Published var currentError: AppError?
    @Published var showError = false
    
    private init() {}
    
    func handle(_ error: Error) {
        let appError: AppError
        
        // Handle different error types
        if let aiError = error as? AIServiceError {
            appError = AppError(
                title: "AI Service Error",
                message: aiError.localizedDescription,
                details: error.localizedDescription
            )
        } else {
            let localized = error as? LocalizedError
            appError = AppError(
                title: "Error",
                message: localized?.errorDescription ?? error.localizedDescription,
                details: localized?.recoverySuggestion ?? error.localizedDescription
            )
        }
        
        currentError = appError
        showError = true
        // No auto-dismiss. This is a menu bar app: the overlay window that
        // renders the alert is hidden almost all the time, so a 5-second timer
        // meant every background failure — ingestion, OCR write-back, deferred
        // maintenance, DB init — self-destructed before anyone could see it,
        // making all the rollback-and-report work unreachable. Errors stay
        // until acknowledged.
    }

    /// Acknowledge the current error (the alert's button, or the dashboard row).
    func dismiss() {
        showError = false
        currentError = nil
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

