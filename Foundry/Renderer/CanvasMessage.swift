import Foundation

nonisolated struct CanvasPrimitiveSelection: Equatable, Sendable {
    let partID: UUID
    let propertyKey: PartProperty.Key
    let propertyPath: [Int]

    init(partID: UUID, propertyKey: PartProperty.Key, propertyPath: [Int] = []) {
        self.partID = partID
        self.propertyKey = propertyKey
        self.propertyPath = propertyPath
    }
}

nonisolated struct CanvasMessage: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let event: Event
    let partID: UUID?
    let partIDs: [UUID]?
    let extendsSelection: Bool?
    let partType: PartType?
    let reusableDefinitionID: UUID?
    let globalDefinitionID: UUID?
    let isGlobalLinked: Bool?
    let placement: Placement?
    let propertyKey: PartProperty.Key?
    let propertyPath: [Int]?
    let propertyValue: String?
    let assetFilename: String?
    let assetMediaType: String?
    let assetData: String?
    let assetID: UUID?

    init(
        version: Int = currentVersion,
        event: Event,
        partID: UUID? = nil,
        partIDs: [UUID]? = nil,
        extendsSelection: Bool? = nil,
        partType: PartType? = nil,
        reusableDefinitionID: UUID? = nil,
        globalDefinitionID: UUID? = nil,
        isGlobalLinked: Bool? = nil,
        placement: Placement? = nil,
        propertyKey: PartProperty.Key? = nil,
        propertyPath: [Int]? = nil,
        propertyValue: String? = nil,
        assetFilename: String? = nil,
        assetMediaType: String? = nil,
        assetData: String? = nil,
        assetID: UUID? = nil
    ) {
        self.version = version
        self.event = event
        self.partID = partID
        self.partIDs = partIDs
        self.extendsSelection = extendsSelection
        self.partType = partType
        self.reusableDefinitionID = reusableDefinitionID
        self.globalDefinitionID = globalDefinitionID
        self.isGlobalLinked = isGlobalLinked
        self.placement = placement
        self.propertyKey = propertyKey
        self.propertyPath = propertyPath
        self.propertyValue = propertyValue
        self.assetFilename = assetFilename
        self.assetMediaType = assetMediaType
        self.assetData = assetData
        self.assetID = assetID
    }

    nonisolated enum Event: String, Codable, Sendable {
        case clearSelection
        case selectPart
        case selectPrimitive
        case deleteParts
        case duplicateParts
        case copyParts
        case pasteParts
        case insertPart
        case insertReusablePart
        case insertGlobalPart
        case setGlobalLink
        case movePart
        case editPart
        case editHTMLPart
        case importImageAsset
        case insertImagePart
    }

    nonisolated struct Placement: Codable, Equatable, Sendable {
        let kind: Kind
        let targetID: UUID?
        let slotID: String?

        init(kind: Kind, targetID: UUID?, slotID: String? = nil) {
            self.kind = kind
            self.targetID = targetID
            self.slotID = slotID
        }

        nonisolated enum Kind: String, Codable, Sendable {
            case before
            case after
            case inside
            case end
        }

        var partPlacement: PartPlacement? {
            switch kind {
            case .before:
                targetID.map(PartPlacement.before)
            case .after:
                targetID.map(PartPlacement.after)
            case .inside:
                if let targetID, let slotID, !slotID.isEmpty {
                    .insideSlot(targetID, slotID)
                } else {
                    targetID.map(PartPlacement.inside)
                }
            case .end:
                .end
            }
        }
    }

    static func decode(_ body: Any) -> CanvasMessage? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              let message = try? JSONDecoder().decode(CanvasMessage.self, from: data),
              message.version == currentVersion,
              message.isValid else {
            return nil
        }
        return message
    }

    private var isValid: Bool {
        guard propertyPath?.allSatisfy({ $0 >= 0 }) != false else { return false }
        return switch event {
        case .clearSelection:
            partID == nil && partIDs == nil && extendsSelection == nil && partType == nil &&
                reusableDefinitionID == nil && globalDefinitionID == nil && isGlobalLinked == nil && placement == nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .selectPart:
            partID != nil && partType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement == nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .selectPrimitive:
            partID != nil && partIDs == nil && extendsSelection == nil && partType == nil &&
                reusableDefinitionID == nil && globalDefinitionID == nil && isGlobalLinked == nil && placement == nil &&
                propertyKey != nil && propertyValue == nil && hasNoAssetPayload
        case .deleteParts, .duplicateParts, .copyParts, .pasteParts:
            partID == nil && partIDs?.isEmpty == false && extendsSelection == nil && partType == nil &&
                reusableDefinitionID == nil && globalDefinitionID == nil && isGlobalLinked == nil && placement == nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .insertPart:
            partID == nil && partType != nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement?.partPlacement != nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .insertReusablePart:
            partID == nil && partType == nil && reusableDefinitionID != nil &&
                globalDefinitionID == nil && placement?.partPlacement != nil && propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .insertGlobalPart:
            partID == nil && partType == nil && reusableDefinitionID == nil && globalDefinitionID != nil &&
                placement?.partPlacement != nil && propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .setGlobalLink:
            partID != nil && partType == nil && reusableDefinitionID == nil && globalDefinitionID == nil &&
                isGlobalLinked != nil && placement == nil && propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .movePart:
            (partID != nil || partIDs?.isEmpty == false) && partType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement?.partPlacement != nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .editPart, .editHTMLPart:
            partID != nil && partType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement == nil &&
                propertyKey != nil && propertyValue != nil && hasNoAssetPayload
        case .importImageAsset:
            partID != nil && partType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement == nil &&
                propertyValue == nil && (
                    (assetID != nil && assetFilename == nil && assetMediaType == nil && assetData == nil) ||
                    (assetID == nil && assetFilename != nil && assetMediaType != nil && assetData != nil)
                )
        case .insertImagePart:
            partID == nil && partType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement?.partPlacement != nil &&
                propertyKey == nil && propertyValue == nil && (
                    (assetID != nil && assetFilename == nil && assetMediaType == nil && assetData == nil) ||
                    (assetID == nil && assetFilename != nil && assetMediaType != nil && assetData != nil)
                )
        }
    }

    private var hasNoAssetPayload: Bool {
        assetFilename == nil && assetMediaType == nil && assetData == nil && assetID == nil
    }
}
