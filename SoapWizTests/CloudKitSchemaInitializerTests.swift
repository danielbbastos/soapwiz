import CoreData
import SwiftData
import Testing
@testable import SoapWiz

@Suite
struct CloudKitSchemaInitializerTests {

    @Test func managedObjectModel_FromModelTypes_CoversEverySchemaEntity() throws {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: ModelContainerFactory.modelTypes))

        let modelEntities = Set(model.entities.compactMap(\.name))
        let schemaEntities = Set(ModelContainerFactory.schema.entities.map(\.name))

        #expect(!schemaEntities.isEmpty)
        #expect(modelEntities == schemaEntities)
    }

    @Test func modelTypes_HaveNoDuplicates() {
        let names = ModelContainerFactory.modelTypes.map { String(describing: $0) }

        #expect(Set(names).count == names.count)
    }

    @Test func isRequested_WithoutLaunchArgument_IsFalse() {
        #expect(!ProcessInfo.processInfo.arguments.contains(CloudKitSchemaInitializer.launchArgument))
        #expect(!CloudKitSchemaInitializer.isRequested)
    }

    @Test func cloudKitContainerIdentifier_MatchesBundlePrefix() {
        #expect(ModelContainerFactory.cloudKitContainerIdentifier == "iCloud.pt.tachyon.SoapWiz")
    }
}
