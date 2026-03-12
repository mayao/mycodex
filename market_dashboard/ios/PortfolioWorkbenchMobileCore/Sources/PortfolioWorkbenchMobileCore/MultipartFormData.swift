import Foundation

struct MultipartFormDataBody {
    let boundary: String
    private(set) var data = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func appendField(name: String, value: String) {
        data.append("--\(boundary)\r\n".utf8Data)
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8Data)
        data.append("\(value)\r\n".utf8Data)
    }

    mutating func appendFile(
        name: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) {
        data.append("--\(boundary)\r\n".utf8Data)
        data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".utf8Data)
        data.append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        data.append(fileData)
        data.append("\r\n".utf8Data)
    }

    mutating func finalize() {
        data.append("--\(boundary)--\r\n".utf8Data)
    }
}

private extension String {
    var utf8Data: Data {
        Data(utf8)
    }
}
