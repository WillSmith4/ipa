import Foundation
import CoreData

@main
struct GestureSettingsMigrationTests {
    static func main() throws {
        let models = URL(fileURLWithPath: CommandLine.arguments[1])
        let stores = URL(fileURLWithPath: CommandLine.arguments[2])
        for source in ["1.1", "1.2", "1.3", "1.4", "1.5", "1.6"] {
            for (index, bindings) in [("Q", "E"), ("CTRL+MOUSE_MIDDLE", "CTRL+MOUSE_MIDDLE"), ("NONE", "NONE")].enumerated() {
                try checkMigration(from: source, caseID: index, left: bindings.0, right: bindings.1, models: models, stores: stores)
            }
        }
        print("Gesture settings: rotation, viewport, long-press and double-tap drag migration passed")
    }

    static func checkMigration(from source: String, caseID: Int, left: String, right: String,
                               models: URL, stores: URL) throws {
        let old = NSManagedObjectModel(contentsOf: models.appendingPathComponent("VoidLink v\(source).mom"))!
        let current = NSManagedObjectModel(contentsOf: models.appendingPathComponent("VoidLink v1.7.mom"))!
        let longPressAttribute = current.entitiesByName["Settings"]!.attributesByName["singlePointLongPressRightClick"]!
        precondition(longPressAttribute.renamingIdentifier == "singlePointDoubleTapRightClick",
                     "The compiled model must retain the previous switch name as its renaming identifier")
        for model in [old, current] {
            for entity in model.entities { entity.managedObjectClassName = "NSManagedObject" }
        }
        let storeURL = stores.appendingPathComponent("settings-\(source)-\(caseID).sqlite")
        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: old)
        let oldStore = try oldCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = oldCoordinator
        let settings = NSEntityDescription.insertNewObject(forEntityName: "Settings", into: context)
        settings.setValue("gesture-migration-test", forKey: "uniqueId")
        settings.setValue("CTRL+Q", forKey: "pinchInAction")
        settings.setValue(left, forKey: "rotateLeftAction")
        settings.setValue(right, forKey: "rotateRightAction")
        settings.setValue(false, forKey: "enablePinch")
        if source != "1.1" {
            settings.setValue("MOUSE_MIDDLE", forKey: "swipeAction")
            settings.setValue(true, forKey: "swipeMovesCursor")
            settings.setValue(caseID != 2, forKey: "rotateRightMovesCursor")
        }
        if ["1.3", "1.4", "1.5", "1.6"].contains(source) { settings.setValue(false, forKey: "localStreamPanEnabled") }
        if source == "1.4" || source == "1.5" || source == "1.6" {
            settings.setValue("ALT+MOUSE_MIDDLE", forKey: "rotationAction")
            settings.setValue(false, forKey: "rotationMovesCursor")
            settings.setValue(caseID != 2, forKey: source == "1.4" ? "singlePointDoubleTapRightClick" : "singlePointLongPressRightClick")
        }
        let oldLongPress = ["ALT+MOUSE_RIGHT", "NONE", "CTRL++"][caseID]
        if source == "1.6" { settings.setValue(oldLongPress, forKey: "longPressAction") }
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
        if source != "1.4" && source != "1.5" && source != "1.6" {
            precondition(result.value(forKey: "rotationAction") == nil, "Nil marks a store requiring binding migration")
        }
        // Execute the same initializer as DataManager, not a copy of its logic.
        InitializeUnifiedRotationSettings(result)
        InitializeLongPressSettings(result)
        let expectedRotation = (source == "1.4" || source == "1.5" || source == "1.6") ? "ALT+MOUSE_MIDDLE" : (left == right ? left : "MOUSE_MIDDLE")
        precondition(result.value(forKey: "rotationAction") as? String == expectedRotation)
        precondition(result.value(forKey: "rotationMovesCursor") as? Bool == (source != "1.1" && source != "1.4" && source != "1.5" && source != "1.6" && caseID != 2))
        let expectedLongPress = (source != "1.4" && source != "1.5" && source != "1.6") || caseID != 2
        precondition(result.value(forKey: "longPressAction") as? String == (source == "1.6" ? oldLongPress : (expectedLongPress ? "MOUSE_RIGHT" : "NONE")))
        precondition(result.value(forKey: "doubleTapDragAction") as? String == "MOUSE_LEFT", "Upgrades must retain the original default left-button drag")
        let actualLongPress = result.value(forKey: "singlePointLongPressRightClick") as? Bool
        precondition(actualLongPress == expectedLongPress,
                     "Long-press switch migration from v\(source), case \(caseID): expected \(expectedLongPress), got \(String(describing: actualLongPress))")
        precondition(result.value(forKey: "uniqueId") as? String == "gesture-migration-test")
        precondition(result.value(forKey: "pinchInAction") as? String == "CTRL+Q")
        precondition(result.value(forKey: "rotateLeftAction") as? String == left)
        precondition(result.value(forKey: "rotateRightAction") as? String == right)
        precondition(result.value(forKey: "enablePinch") as? Bool == false)
        precondition(result.value(forKey: "swipeAction") as? String == (source != "1.1" ? "MOUSE_MIDDLE" : "NONE"))
        precondition(result.value(forKey: "swipeMovesCursor") as? Bool == (source != "1.1"))
        precondition(result.value(forKey: "localStreamPanEnabled") as? Bool == (source != "1.3" && source != "1.4" && source != "1.5" && source != "1.6"))
        precondition(result.value(forKey: "localStreamZoomEnabled") as? Bool == true)

        // Later edits to the binding, including Off, must survive initialization
        // and reopening independently of the retired switch and other bindings.
        let panEnabled = source == "1.2"
        result.setValue(panEnabled, forKey: "localStreamPanEnabled")
        result.setValue(!panEnabled, forKey: "localStreamZoomEnabled")
        let longPressAction = ["NONE", "CTRL++", "MOUSE_MIDDLE"][caseID]
        result.setValue(longPressAction, forKey: "longPressAction")
        let dragAction = ["NONE", "CTRL+MOUSE_LEFT", "MOUSE_RIGHT"][caseID]
        result.setValue(dragAction, forKey: "doubleTapDragAction")
        result.setValue(!expectedLongPress, forKey: "singlePointLongPressRightClick")
        result.setValue("W+D", forKey: "rotationAction")
        result.setValue(false, forKey: "rotationMovesCursor")
        InitializeUnifiedRotationSettings(result)
        InitializeLongPressSettings(result)
        try migrated.save()
        try coordinator.remove(store)
        let reopened = NSPersistentStoreCoordinator(managedObjectModel: current)
        _ = try reopened.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
        let reopenedContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reopenedContext.persistentStoreCoordinator = reopened
        let saved = try reopenedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Settings"))[0]
        InitializeUnifiedRotationSettings(saved)
        InitializeLongPressSettings(saved)
        precondition(saved.value(forKey: "rotationAction") as? String == "W+D")
        precondition(saved.value(forKey: "rotationMovesCursor") as? Bool == false)
        precondition(saved.value(forKey: "localStreamPanEnabled") as? Bool == panEnabled)
        precondition(saved.value(forKey: "localStreamZoomEnabled") as? Bool == !panEnabled)
        precondition(saved.value(forKey: "longPressAction") as? String == longPressAction)

        precondition(saved.value(forKey: "doubleTapDragAction") as? String == dragAction,
                     "Drag binding/Off must survive reopening without changing any other input")

        let fresh = NSEntityDescription.insertNewObject(forEntityName: "Settings", into: reopenedContext)
        InitializeUnifiedRotationSettings(fresh)
        InitializeLongPressSettings(fresh)
        precondition(fresh.value(forKey: "rotationAction") as? String == "MOUSE_MIDDLE")
        precondition(fresh.value(forKey: "longPressAction") as? String == "MOUSE_RIGHT")
        precondition(fresh.value(forKey: "doubleTapDragAction") as? String == "MOUSE_LEFT")
    }
}
