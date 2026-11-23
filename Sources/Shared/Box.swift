import Combine

/// A value a view can change and watch (stands in for @State, which needs a compiler plugin).
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}
