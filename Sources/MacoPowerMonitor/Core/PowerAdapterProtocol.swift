import Foundation

enum PowerAdapterProtocol: String, Codable, Sendable {
    case usbPowerDelivery
    case applePrivate
    case quickCharge
    case usbTypeC
    case wireless
    case legacyUSB
    case unknown

    var displayName: String {
        switch self {
        case .usbPowerDelivery:
            return "USB Power Delivery"
        case .applePrivate:
            return "Apple 私有充电协议"
        case .quickCharge:
            return "Qualcomm Quick Charge"
        case .usbTypeC:
            return "USB-C 供电"
        case .wireless:
            return "无线供电"
        case .legacyUSB:
            return "USB 传统供电"
        case .unknown:
            return "协议未公开"
        }
    }

    var shortName: String {
        switch self {
        case .usbPowerDelivery:
            return "USB PD"
        case .applePrivate:
            return "Apple 私有"
        case .quickCharge:
            return "QC"
        case .usbTypeC:
            return "USB-C"
        case .wireless:
            return "无线"
        case .legacyUSB:
            return "USB"
        case .unknown:
            return "未知"
        }
    }
}

struct PowerAdapterProtocolDetection: Sendable {
    let `protocol`: PowerAdapterProtocol
    let detail: String?
    let vendorID: Int?
    let productID: Int?
    let pdRevisionCode: Int?
}

enum PowerAdapterProtocolDetector {
    static func detect(
        adapterDetails: [String: Any],
        fedDetails: [String: Any]? = nil
    ) -> PowerAdapterProtocolDetection {
        let combinedText = searchableText(in: [adapterDetails, fedDetails ?? [:]]).lowercased()
        let vendorID = fedDetails?.intValue("FedVendorID") ?? adapterDetails.intValue("VendorID")
        let productID = fedDetails?.intValue("FedProductID") ?? adapterDetails.intValue("ProductID")
        let pdRevision = fedDetails?.intValue("FedPdSpecRevision")
        let externallyConnected = fedDetails?.boolishValue("FedExternalConnected") ?? false

        if adapterDetails.boolishValue("IsWireless") || combinedText.contains("wireless") || combinedText.contains("magsafe battery") {
            return PowerAdapterProtocolDetection(
                protocol: .wireless,
                detail: "系统报告为无线电源",
                vendorID: vendorID,
                productID: productID,
                pdRevisionCode: pdRevision
            )
        }

        if (externallyConnected && (pdRevision ?? 0) > 0)
            || combinedText.contains("usb power delivery")
            || combinedText.contains("usb-pd")
            || combinedText.contains("usb pd") {
            return PowerAdapterProtocolDetection(
                protocol: .usbPowerDelivery,
                detail: pdDetail(revisionCode: pdRevision, vendorID: vendorID, productID: productID),
                vendorID: vendorID,
                productID: productID,
                pdRevisionCode: pdRevision
            )
        }

        if combinedText.contains("quick charge")
            || combinedText.contains("qc2")
            || combinedText.contains("qc 2")
            || combinedText.contains("qc3")
            || combinedText.contains("qc 3") {
            return PowerAdapterProtocolDetection(
                protocol: .quickCharge,
                detail: "系统注册表包含 Quick Charge 标识",
                vendorID: vendorID,
                productID: productID,
                pdRevisionCode: pdRevision
            )
        }

        if combinedText.contains("apple 2.4a")
            || combinedText.contains("apple charging")
            || combinedText.contains("mfi")
            || combinedText.contains("iphone brick") {
            return PowerAdapterProtocolDetection(
                protocol: .applePrivate,
                detail: "系统仅报告 Apple 充电器标识，未报告 USB PD 协商",
                vendorID: vendorID,
                productID: productID,
                pdRevisionCode: pdRevision
            )
        }

        if adapterDetails["UsbHvcMenu"] != nil
            || adapterDetails["USBHVCMenu"] != nil
            || combinedText.contains("usb-c")
            || combinedText.contains("type-c") {
            return PowerAdapterProtocolDetection(
                protocol: .usbTypeC,
                detail: "检测到 USB-C 高压档位，但系统未公开具体协议",
                vendorID: vendorID,
                productID: productID,
                pdRevisionCode: pdRevision
            )
        }

        if adapterDetails.intValue("AdapterVoltage") != nil || adapterDetails.intValue("Current") != nil {
            return PowerAdapterProtocolDetection(
                protocol: .unknown,
                detail: "已检测到外接电源，macOS 未公开协议标识",
                vendorID: vendorID,
                productID: productID,
                pdRevisionCode: pdRevision
            )
        }

        return PowerAdapterProtocolDetection(
            protocol: .unknown,
            detail: nil,
            vendorID: vendorID,
            productID: productID,
            pdRevisionCode: pdRevision
        )
    }

    private static func pdDetail(revisionCode: Int?, vendorID: Int?, productID: Int?) -> String {
        var parts: [String] = []

        if let revisionCode {
            parts.append("PD 修订码 \(revisionCode)")
        }

        if let vendorID, vendorID > 0 {
            parts.append(String(format: "VID 0x%04X", vendorID))
        }

        if let productID, productID > 0 {
            parts.append(String(format: "PID 0x%04X", productID))
        }

        return parts.isEmpty ? "检测到 USB PD 协商" : parts.joined(separator: " · ")
    }

    private static func searchableText(in dictionaries: [[String: Any]]) -> String {
        dictionaries.flatMap { dictionary in
            dictionary.compactMap { key, value -> String? in
                if let string = value as? String {
                    return "\(key) \(string)"
                }
                if value is [String: Any] || value is [[String: Any]] {
                    return "\(key) \(String(describing: value))"
                }
                return key
            }
        }.joined(separator: " ")
    }
}

private extension Dictionary where Key == String, Value == Any {
    func intValue(_ key: String) -> Int? {
        if let value = self[key] as? Int {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.intValue
        }
        return nil
    }

    func boolishValue(_ key: String) -> Bool {
        if let value = self[key] as? Bool {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.boolValue
        }
        if let value = self[key] as? String {
            return ["yes", "true", "1"].contains(value.lowercased())
        }
        return false
    }
}
