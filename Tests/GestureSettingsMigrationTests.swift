import Foundation
import CoreData

@main
struct GestureSettingsMigrationTests {
    static func main() throws {
        let modelDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
        let storeDirectory = URL(fileURLWithPath: CommandLine.arguments[2])
        let old = NSManagedObjectModel(contentsOf: modelDirectory.appendingPathComponent("VoidLink v1.1.mom"))!
        let current = NSManagedObjectModel(contentsOf: modelDirectory.appendingPathComponent("VoidLink v1.2.mom"))!
        for model in [old, current] {
            for entity in model.entities { entity.managedObjectClassName = "NSManagedObject" }
        }
        let storeURL = storeDirectory.appendingPathComponent("settings.sqlite")
        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: old)
        let oldStore = try oldCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = oldCoordinator
        let settings = NSEntityDescription.insertNewObject(forEntityName: "Settings", into: context)
        settings.setValue("CTRL+Q", forKey: "pinchInAction")
        settings.setValue("NONE", forKey: "rotateRightAction")
        settings.setValue(false, forKey: "enablePinch")
        try context.save()
        try oldCoordinator.remove(oldStore)

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: current)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL,
            options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true])
        let migrated = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        migrated.persistentStoreCoordinator = coordinator
        let records = try migrated.fetch(NSFetchRequest<NSManagedObject>(entityName: "Settings"))
        precondition(records.count == 1)
        let result = records[0]
        precondition(result.value(forKey: "pinchInAction") as? String == "CTRL+Q")
        precondition(result.value(forKey: "rotateRightAction") as? String == "NONE")
        precondition(result.value(forKey: "enablePinch") as? Bool == false)
        precondition(result.value(forKey: "swipeAction") as? String == "NONE")
        let flags = ["pinchInMovesCursor", "pinchOutMovesCursor", "rotateLeftMovesCursor", "rotateRightMovesCursor", "swipeMovesCursor"]
        for flag in flags { precondition(result.value(forKey: flag) as? Bool == false) }
        result.setValue("MOUSE_MIDDLE", forKey: "swipeAction")
        for flag in flags { result.setValue(true, forKey: flag) }
        try migrated.save()
        try coordinator.remove(store)
        let reopened = NSPersistentStoreCoordinator(managedObjectModel: current)
        _ = try reopened.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
        let reopenedContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reopenedContext.persistentStoreCoordinator = reopened
        let saved = try reopenedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Settings"))[0]
        precondition(saved.value(forKey: "swipeAction") as? String == "MOUSE_MIDDLE")
        for flag in flags { precondition(saved.value(forKey: flag) as? Bool == true) }
        print("Gesture settings: migration preserves bindings and new settings persist")
    }
}
