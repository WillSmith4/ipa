import Foundation
import CoreData

@main
struct GestureSettingsMigrationTests {
    static func main() throws {
        let modelDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
        let storeDirectory = URL(fileURLWithPath: CommandLine.arguments[2])
        for source in ["1.1", "1.2"] {
            try checkMigration(from: source, models: modelDirectory, stores: storeDirectory)
        }
        print("Gesture settings: migration preserves bindings and viewport switches persist independently")
    }

    static func checkMigration(from source: String, models modelDirectory: URL, stores storeDirectory: URL) throws {
        let old = NSManagedObjectModel(contentsOf: modelDirectory.appendingPathComponent("VoidLink v\(source).mom"))!
        let current = NSManagedObjectModel(contentsOf: modelDirectory.appendingPathComponent("VoidLink v1.3.mom"))!
        for model in [old, current] {
            for entity in model.entities { entity.managedObjectClassName = "NSManagedObject" }
        }
        let storeURL = storeDirectory.appendingPathComponent("settings-\(source).sqlite")
        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: old)
        let oldStore = try oldCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = oldCoordinator
        let settings = NSEntityDescription.insertNewObject(forEntityName: "Settings", into: context)
        settings.setValue("gesture-migration-test", forKey: "uniqueId")
        settings.setValue("CTRL+Q", forKey: "pinchInAction")
        settings.setValue("NONE", forKey: "rotateRightAction")
        settings.setValue(false, forKey: "enablePinch")
        if source == "1.2" {
            settings.setValue("MOUSE_MIDDLE", forKey: "swipeAction")
            settings.setValue(true, forKey: "swipeMovesCursor")
        }
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
        precondition(result.value(forKey: "uniqueId") as? String == "gesture-migration-test")
        precondition(result.value(forKey: "pinchInAction") as? String == "CTRL+Q")
        precondition(result.value(forKey: "rotateRightAction") as? String == "NONE")
        precondition(result.value(forKey: "enablePinch") as? Bool == false)
        precondition(result.value(forKey: "swipeAction") as? String == (source == "1.2" ? "MOUSE_MIDDLE" : "NONE"))
        let flags = ["pinchInMovesCursor", "pinchOutMovesCursor", "rotateLeftMovesCursor", "rotateRightMovesCursor", "swipeMovesCursor"]
        for flag in flags { precondition(result.value(forKey: flag) as? Bool == (source == "1.2" && flag == "swipeMovesCursor")) }
        precondition(result.value(forKey: "localStreamPanEnabled") as? Bool == true)
        precondition(result.value(forKey: "localStreamZoomEnabled") as? Bool == true)
        // Exercise both independent switch combinations across a store reopen.
        let panEnabled = source == "1.2"
        result.setValue(panEnabled, forKey: "localStreamPanEnabled")
        result.setValue(!panEnabled, forKey: "localStreamZoomEnabled")
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
        precondition(saved.value(forKey: "localStreamPanEnabled") as? Bool == panEnabled)
        precondition(saved.value(forKey: "localStreamZoomEnabled") as? Bool == !panEnabled)
    }
}
