import Testing
@testable import ExpensesCore

@Test func developmentEnvironmentUsesLocalBackend() {
    #expect(AppEnvironment.development.apiBaseURL.absoluteString == "http://localhost:8000")
}
