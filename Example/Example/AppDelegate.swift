import UIKit


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    /// Tells the delegate that the launch process is almost done and the app is almost ready to run.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        application.applicationIconBadgeNumber = 0
        let window = UIWindow()
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window
        
        return true
    }

    
    /// Tells the delegate that the app is about to become inactive.
    func applicationWillResignActive(_ application: UIApplication) {
    }

    
    /// Tells the delegate that the app is now in the background.
    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    
    /// Tells the delegate that the app is about to enter the foreground.
    func applicationWillEnterForeground(_ application: UIApplication) {
        application.applicationIconBadgeNumber = 0
    }

    
    /// Tells the delegate that the app has become active.
    func applicationDidBecomeActive(_ application: UIApplication) {
        //..
    }

    
    /// Tells the delegate when the app is about to terminate.
    func applicationWillTerminate(_ application: UIApplication) {
        //..
    }
}
	
