//
//  SceneDelegate.swift
//  example
//
//  Created by Roman Odyshew on 21.09.2021.
//

import UIKit
import absmartly

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var context: Context?
    var window: UIWindow?
    let viewController = ViewController()
    
    private let keyApiKey = "apiKey"
    private let keyApplication = "application"
    private let keyEndpoint = "endpoint"
    private let keyEnvironment = "environment"
    private let keyVersion = "version"
    private let keyExperimentName = "experimentName"
    private let keyGoalName = "goalName"
    
    private func getConfig() -> [String:String]? {
        guard let path = Bundle.main.path(forResource: "ABSmartlyConfig", ofType: "plist") else {
            print("Can't find ABSmartlyConfig.plist in main bundle")
            return nil
        }
        
        guard let config = NSDictionary(contentsOfFile: path) as? Dictionary<String, String> else {
            print("Can't represent content of ABSmartlyConfig.plist as strings dictionary")
            return nil
        }
        
        for key in [keyApiKey, keyApplication, keyEndpoint, keyEnvironment, keyVersion, keyExperimentName, keyGoalName] {
            guard let _ = config[key] else {
                print("Can't find the key: \"\(key)\" in ABSmartlyConfig.plist")
                return nil
            }
        }
        
        return config
    }
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        self.window = window
        
        guard let config = getConfig() else {
            return
        }
        
        let options = ClientOptions(apiKey: config[keyApiKey]!,
                                    application: config[keyApplication]!,
                                    endpoint: config[keyEndpoint]!,
                                    environment: config[keyEnvironment]!,
                                    version: config[keyVersion]!)
        
        let sdk = absmartly.ABSmartlySDK(options)
        
        let contextConfig: ContextConfig = ContextConfig()
        contextConfig.setUnit(unitType: "device_id", uid: UIDevice.current.identifierForVendor?.uuidString ?? "123456789")
        
        let context = sdk.createContext(config: contextConfig)
        context.waitUntilReadyAsync { [weak self] context in
            guard let `self` = self else { return }
            guard let context = context else { return }
            
            do {
                let treatment = try context.getTreatment(config[self.keyExperimentName]!)
                
                DispatchQueue.main.async {
                    if treatment == 0 {
                        self.viewController.buttonColor = .blue
                    } else {
                        self.viewController.buttonColor = .orange
                    }
                }
   
            } catch {
                print("Error" + error.localizedDescription)
            }
            
            self.viewController.buttonClickAction = { [weak self] in
                guard let `self` = self else { return }
                do {
                   try context.track(config[self.keyGoalName]!, properties: [:])
                } catch {
                    print("Error" + error.localizedDescription)
                }
                
            }
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }


}

