import Foundation

class ContextDataProvider {
    private let requestFactory: RequestFactory
    private let clientOptions: ClientOptions
    
    init(_ requestFactory: RequestFactory, _ clientOptions: ClientOptions) {
        self.requestFactory = requestFactory
        self.clientOptions = clientOptions
    }
    
    func getContextData() -> Promise<ContextData> {
        guard let request = requestFactory.contextRequest else {
            return Promise {
                $1(ABSmartlyError("Build context URL error"))
            }
        }
        
        let promise: Promise<ContextData> = Promise { [weak self] successCallback, errorCallback in
            guard let `self` = self else {
                errorCallback(ABSmartlyError("ContextDataProvider arc error"))
                return
            }
            
            self.requestCompletionHandler(request, self.clientOptions.retries, self.clientOptions.timeout) { (contextData: ContextData?, error: Error?) in
                if let contextData = contextData {
                    successCallback(contextData)
                    return
                }
                
                if let error = error {
                    errorCallback(error)
                }
            }
        }
        return promise
    }

    func getContextData(_ callBack: @escaping ((_:ContextData?, _:Error?)->())) {
        guard let request = requestFactory.contextRequest else {
            callBack(nil, ABSmartlyError("Build context URL error"))
            return
        }
        
        let session = URLSession.shared
        
        let task = session.dataTask(with: request, completionHandler: { data, response, error in
            if let error = error {
                Logger.error("Context data getting error: " + error.localizedDescription)
                callBack(nil, error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                Logger.error("Context data getting network error, status code: \(httpResponse.statusCode)")
                callBack(nil, NetworkError(httpResponse.statusCode, ""))
                return
            }
            
            guard let data = data else {
                Logger.error("Context data getting error, no data")
                callBack(nil, ABSmartlyError("No data"))
                return
            }
            
            do {
                let result = try JSONDecoder().decode(ContextData.self, from: data)
                Logger.notice("The context data was successfully received")
                callBack(result, nil)
                return
            } catch {
                Logger.error("Contet data deserealization error: " + error.localizedDescription)
                callBack(nil, ABSmartlyError("Contet data deserealization error: " + error.localizedDescription))
            }
        })
        
        task.resume()
    }
    
    private func requestCompletionHandler(_ request: URLRequest, _ retryCount: Int, _ timeout: TimeInterval, _ callback: @escaping((_:ContextData?, _:Error?)->())) {
        let session = URLSession.shared

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.error("Context data getting error: " + error.localizedDescription)
                callback(nil, error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                Logger.error("Context data getting network error, status code: \(httpResponse.statusCode)")
                if retryCount > 0 {
                    
                    Thread.sleep(forTimeInterval: timeout)
                    Logger.notice("Retry Context Data request: \(retryCount) attempts left")
                    self.requestCompletionHandler(request, retryCount - 1, timeout, callback)
                    return
                }
                callback(nil, NetworkError(httpResponse.statusCode, ""))
                return
            }
            
            guard let data = data else {
                Logger.error("Context data getting error, no data")
                callback(nil, ABSmartlyError("No data"))
                return
            }
            
            do {
                let result = try JSONDecoder().decode(ContextData.self, from: data)
                Logger.notice("The context data was successfully received")
                callback(result, nil)
                return
            } catch {
                Logger.error("Contet data deserealization error: " + error.localizedDescription)
                callback(nil, ABSmartlyError("Contet data deserealization error: " + error.localizedDescription))
            }
        }
        task.resume()
    }
}
