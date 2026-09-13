import Foundation

nonisolated struct CanvasPrimitiveSelection: Equatable, Sendable {
    let blockID: UUID
    let propertyKey: BlockProperty.Key
    let propertyPath: [Int]

    init(blockID: UUID, propertyKey: BlockProperty.Key, propertyPath: [Int] = []) {
        self.blockID = blockID
        self.propertyKey = propertyKey
        self.propertyPath = propertyPath
    }
}

nonisolated struct CanvasMessage: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let event: Event
    let blockID: UUID?
    let blockIDs: [UUID]?
    let extendsSelection: Bool?
    let blockType: BlockType?
    let reusableDefinitionID: UUID?
    let globalDefinitionID: UUID?
    let isGlobalLinked: Bool?
    let placement: Placement?
    let propertyKey: BlockProperty.Key?
    let propertyPath: [Int]?
    let propertyValue: String?
    let assetFilename: String?
    let assetMediaType: String?
    let assetData: String?
    let assetID: UUID?

    init(
        version: Int = currentVersion,
        event: Event,
        blockID: UUID? = nil,
        blockIDs: [UUID]? = nil,
        extendsSelection: Bool? = nil,
        blockType: BlockType? = nil,
        reusableDefinitionID: UUID? = nil,
        globalDefinitionID: UUID? = nil,
        isGlobalLinked: Bool? = nil,
        placement: Placement? = nil,
        propertyKey: BlockProperty.Key? = nil,
        propertyPath: [Int]? = nil,
        propertyValue: String? = nil,
        assetFilename: String? = nil,
        assetMediaType: String? = nil,
        assetData: String? = nil,
        assetID: UUID? = nil
    ) {
        self.version = version
        self.event = event
        self.blockID = blockID
        self.blockIDs = blockIDs
        self.extendsSelection = extendsSelection
        self.blockType = blockType
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
        case selectBlock
        case selectPrimitive
        case deleteBlocks
        case duplicateBlocks
        case copyBlocks
        case pasteBlocks
        case insertBlock
        case insertReusableBlock
        case insertGlobalBlock
        case setGlobalLink
        case moveBlock
        case editBlock
        case editHTMLBlock
        case importImageAsset
        case insertImageBlock
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

        var blockPlacement: BlockPlacement? {
            switch kind {
            case .before:
                targetID.map(BlockPlacement.before)
            case .after:
                targetID.map(BlockPlacement.after)
            case .inside:
                if let targetID, let slotID, !slotID.isEmpty {
                    .insideSlot(targetID, slotID)
                } else {
                    targetID.map(BlockPlacement.inside)
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
        case .selectBlock:
            blockID != nil && blockType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement == nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .selectPrimitive:
            blockID != nil && blockIDs == nil && extendsSelection == nil && blockType == nil &&
                reusableDefinitionID == nil && globalDefinitionID == nil && isGlobalLinked == nil && placement == nil &&
                propertyKey != nil && propertyValue == nil && hasNoAssetPayload
        case .deleteBlocks, .duplicateBlocks, .copyBlocks, .pasteBlocks:
            blockID == nil && blockIDs?.isEmpty == false && extendsSelection == nil && blockType == nil &&
                reusableDefinitionID == nil && globalDefinitionID == nil && isGlobalLinked == nil && placement == nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .insertBlock:
            blockID == nil && blockType != nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement?.blockPlacement != nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .insertReusableBlock:
            blockID == nil && blockType == nil && reusableDefinitionID != nil &&
                globalDefinitionID == nil && placement?.blockPlacement != nil && propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .insertGlobalBlock:
            blockID == nil && blockType == nil && reusableDefinitionID == nil && globalDefinitionID != nil &&
                placement?.blockPlacement != nil && propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .setGlobalLink:
            blockID != nil && blockType == nil && reusableDefinitionID == nil && globalDefinitionID == nil &&
                isGlobalLinked != nil && placement == nil && propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .moveBlock:
            (blockID != nil || blockIDs?.isEmpty == false) && blockType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement?.blockPlacement != nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .editBlock, .editHTMLBlock:
            blockID != nil && blockType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement == nil &&
                propertyKey != nil && propertyValue != nil && hasNoAssetPayload
        case .importImageAsset:
            blockID != nil && blockType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement == nil &&
                propertyValue == nil && (
                    (assetID != nil && assetFilename == nil && assetMediaType == nil && assetData == nil) ||
                    (assetID == nil && assetFilename != nil && assetMediaType != nil && assetData != nil)
                )
        case .insertImageBlock:
            blockID == nil && blockType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement?.blockPlacement != nil &&
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
