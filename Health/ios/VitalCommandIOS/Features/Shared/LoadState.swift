enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        guard case let .loaded(value) = self else {
            return nil
        }

        return value
    }

    var errorMessage: String? {
        guard case let .failed(message) = self else {
            return nil
        }

        return message
    }
}
