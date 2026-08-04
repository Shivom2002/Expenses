// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExpensesCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ExpensesCore", targets: ["ExpensesCore"])
    ],
    targets: [
        .target(name: "ExpensesCore"),
        .testTarget(name: "ExpensesCoreTests", dependencies: ["ExpensesCore"])
    ]
)
