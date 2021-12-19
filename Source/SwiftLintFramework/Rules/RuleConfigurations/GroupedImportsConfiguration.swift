public struct GroupedImportsConfiguration: RuleConfiguration, Equatable {
    public struct ModulesGroup: Equatable {
        let name: String
        let modules: Set<String>
    }
    
    private(set) var severityConfiguration = SeverityConfiguration(.warning)
    
    public var consoleDescription: String {
        return severityConfiguration.consoleDescription +
            ", imports groups: \(String(describing: moduleGroups))"
    }
    
    private(set) var moduleGroups: [ModulesGroup] = [
        ModulesGroup(name: "system modules", modules: Self.systemModules)
    ]
    
    private(set) var allGroupsLargerThan: Int = 2

    public mutating func apply(configuration: Any) throws {
        guard let configuration = configuration as? [String: Any] else {
            throw ConfigurationError.unknownConfiguration
        }
        
        if let groupingConditions = configuration["grouping_conditions"] as? [String: Any],
           let allGroupsLargerThan = groupingConditions["all_groups_larger_than"] as? Int
        {
            self.allGroupsLargerThan = allGroupsLargerThan
        }
        
        guard let groups = configuration["groups"] as? [[String: Any]] else {
            return
        }

        var moduleGroups: [ModulesGroup] = groups.compactMap { dictionary in
            guard let groupName = dictionary.keys.first, let modules = dictionary[groupName] as? [String] else {
                return nil
            }
            return ModulesGroup(name: groupName, modules: Set(modules))
        }
        
        if moduleGroups.isNotEmpty {
            var otherSystemModules = Self.systemModules
            moduleGroups.forEach { userConfigurationModuleGroups in
                otherSystemModules.subtract(userConfigurationModuleGroups.modules)
            }
            if otherSystemModules.isNotEmpty {
                let otherSystemModulesGroup = ModulesGroup(name: "other system modules", modules: otherSystemModules)
                moduleGroups.insert(otherSystemModulesGroup, at: 0)
            }
            self.moduleGroups = moduleGroups
        }
    }
}

private extension GroupedImportsConfiguration {
    // Modules declared in /System/Library/Frameworks
    static var systemModules: Set<String> {
        return Set([
            "AGL",
            "AVFAudio",
            "AVFoundation",
            "AVKit",
            "Accelerate",
            "Accessibility",
            "Accounts",
            "AdServices",
            "AdSupport",
            "AddressBook",
            "AppKit",
            "AppTrackingTransparency",
            "AppleScriptKit",
            "AppleScriptObjC",
            "ApplicationServices",
            "AudioToolbox",
            "AudioUnit",
            "AudioVideoBridging",
            "AuthenticationServices",
            "AutomaticAssessmentConfiguration",
            "Automator",
            "BackgroundTasks",
            "BusinessChat",
            "CFNetwork",
            "CalendarStore",
            "CallKit",
            "Carbon",
            "ClassKit",
            "CloudKit",
            "Cocoa",
            "Collaboration",
            "ColorSync",
            "Combine",
            "Contacts",
            "ContactsUI",
            "CoreAudio",
            "CoreAudioKit",
            "CoreAudioTypes",
            "CoreBluetooth",
            "CoreData",
            "CoreDisplay",
            "CoreFoundation",
            "CoreGraphics",
            "CoreHaptics",
            "CoreImage",
            "CoreLocation",
            "CoreMIDI",
            "CoreMIDIServer",
            "CoreML",
            "CoreMedia",
            "CoreMediaIO",
            "CoreMotion",
            "CoreServices",
            "CoreSpotlight",
            "CoreTelephony",
            "CoreText",
            "CoreVideo",
            "CoreWLAN",
            "CryptoKit",
            "CryptoTokenKit",
            "DVDPlayback",
            "DeveloperToolsSupport",
            "DeviceCheck",
            "DirectoryService",
            "DiscRecording",
            "DiscRecordingUI",
            "DiskArbitration",
            "DriverKit",
            "EventKit",
            "ExceptionHandling",
            "ExecutionPolicy",
            "ExternalAccessory",
            "FWAUserLib",
            "FileProvider",
            "FileProviderUI",
            "FinderSync",
            "ForceFeedback",
            "Foundation",
            "GLKit",
            "GLUT",
            "GSS",
            "GameController",
            "GameKit",
            "GameplayKit",
            "HIDDriverKit",
            "Hypervisor",
            "ICADevices",
            "IMServicePlugIn",
            "IOBluetooth",
            "IOBluetoothUI",
            "IOKit",
            "IOSurface",
            "IOUSBHost",
            "IdentityLookup",
            "ImageCaptureCore",
            "ImageIO",
            "InputMethodKit",
            "InstallerPlugins",
            "InstantMessage",
            "Intents",
            "JavaNativeFoundation",
            "JavaRuntimeSupport",
            "JavaScriptCore",
            "JavaVM",
            "Kerberos",
            "Kernel",
            "KernelManagement",
            "LDAP",
            "LatentSemanticMapping",
            "LinkPresentation",
            "LocalAuthentication",
            "MLCompute",
            "MapKit",
            "MediaAccessibility",
            "MediaLibrary",
            "MediaPlayer",
            "MediaToolbox",
            "Message",
            "Metal",
            "MetalKit",
            "MetalPerformanceShaders",
            "MetalPerformanceShadersGraph",
            "MetricKit",
            "ModelIO",
            "MultipeerConnectivity",
            "NaturalLanguage",
            "NearbyInteraction",
            "NetFS",
            "Network",
            "NetworkExtension",
            "NetworkingDriverKit",
            "NotificationCenter",
            "OSAKit",
            "OSLog",
            "OpenAL",
            "OpenCL",
            "OpenDirectory",
            "OpenGL",
            "PCIDriverKit",
            "PCSC",
            "PDFKit",
            "ParavirtualizedGraphics",
            "PassKit",
            "PencilKit",
            "Photos",
            "PhotosUI",
            "PreferencePanes",
            "PushKit",
            "Python",
            "QTKit",
            "Quartz",
            "QuartzCore",
            "QuickLook",
            "QuickLookThumbnailing",
            "RealityKit",
            "ReplayKit",
            "Ruby",
            "SafariServices",
            "SceneKit",
            "ScreenSaver",
            "ScreenTime",
            "ScriptingBridge",
            "Security",
            "SecurityFoundation",
            "SecurityInterface",
            "SensorKit",
            "ServiceManagement",
            "Social",
            "SoundAnalysis",
            "Speech",
            "SpriteKit",
            "StoreKit",
            "SwiftUI",
            "SyncServices",
            "System",
            "SystemConfiguration",
            "SystemExtensions",
            "TWAIN",
            "Tcl",
            "Tk",
            "UIKit",
            "USBDriverKit",
            "UniformTypeIdentifiers",
            "UserNotifications",
            "UserNotificationsUI",
            "VideoDecodeAcceleration",
            "VideoSubscriberAccount",
            "VideoToolbox",
            "Virtualization",
            "Vision",
            "WebKit",
            "WidgetKit",
            "iTunesLibrary",
            "vecLib"
        ])
    }
}
