import Foundation

nonisolated struct CanvasMessage: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let event: Event
    let componentID: UUID?
    let componentIDs: [UUID]?
    let extendsSelection: Bool?
    let componentType: ComponentType?
    let reusableDefinitionID: UUID?
    let globalDefinitionID: UUID?
    let isGlobalLinked: Bool?
    let placement: Placement?
    let propertyKey: ComponentProperty.Key?
    let propertyValue: String?
    let assetFilename: String?
    let assetMediaType: String?
    let assetData: String?

    init(
        version: Int = currentVersion,
        event: Event,
        componentID: UUID? = nil,
        componentIDs: [UUID]? = nil,
        extendsSelection: Bool? = nil,
        componentType: ComponentType? = nil,
        reusableDefinitionID: UUID? = nil,
        globalDefinitionID: UUID? = nil,
        isGlobalLinked: Bool? = nil,
        placement: Placement? = nil,
        propertyKey: ComponentProperty.Key? = nil,
        propertyValue: String? = nil,
        assetFilename: String? = nil,
        assetMediaType: String? = nil,
        assetData: String? = nil
    ) {
        self.version = version
        self.event = event
        self.componentID = componentID
        self.componentIDs = componentIDs
        self.extendsSelection = extendsSelection
        self.componentType = componentType
        self.reusableDefinitionID = reusableDefinitionID
        self.globalDefinitionID = globalDefinitionID
        self.isGlobalLinked = isGlobalLinked
        self.placement = placement
        self.propertyKey = propertyKey
        self.propertyValue = propertyValue
        self.assetFilename = assetFilename
        self.assetMediaType = assetMediaType
        self.assetData = assetData
    }

    nonisolated enum Event: String, Codable, Sendable {
        case selectComponent
        case insertComponent
        case insertReusableComponent
        case insertGlobalComponent
        case setGlobalLink
        case moveComponent
        case editComponent
        case importImageAsset
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

        var componentPlacement: ComponentPlacement? {
            switch kind {
            case .before:
                targetID.map(ComponentPlacement.before)
            case .after:
                targetID.map(ComponentPlacement.after)
            case .inside:
                if let targetID, let slotID, !slotID.isEmpty {
                    .insideSlot(targetID, slotID)
                } else {
                    targetID.map(ComponentPlacement.inside)
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
        switch event {
        case .selectComponent:
            componentID != nil && componentType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement == nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .insertComponent:
            componentID == nil && componentType != nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement?.componentPlacement != nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .insertReusableComponent:
            componentID == nil && componentType == nil && reusableDefinitionID != nil &&
                globalDefinitionID == nil && placement?.componentPlacement != nil && propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .insertGlobalComponent:
            componentID == nil && componentType == nil && reusableDefinitionID == nil && globalDefinitionID != nil &&
                placement?.componentPlacement != nil && propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .setGlobalLink:
            componentID != nil && componentType == nil && reusableDefinitionID == nil && globalDefinitionID == nil &&
                isGlobalLinked != nil && placement == nil && propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .moveComponent:
            (componentID != nil || componentIDs?.isEmpty == false) && componentType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement?.componentPlacement != nil &&
                propertyKey == nil && propertyValue == nil && hasNoAssetPayload
        case .editComponent:
            componentID != nil && componentType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement == nil &&
                propertyKey != nil && propertyValue != nil && hasNoAssetPayload
        case .importImageAsset:
            componentID != nil && componentType == nil && reusableDefinitionID == nil && globalDefinitionID == nil && placement == nil &&
                propertyKey == nil && propertyValue == nil && assetFilename != nil && assetMediaType != nil && assetData != nil
        }
    }

    private var hasNoAssetPayload: Bool {
        assetFilename == nil && assetMediaType == nil && assetData == nil
    }
}
