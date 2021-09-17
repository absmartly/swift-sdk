//
//  EventPublisher.swift
//  absmartly
//
//  Created by Roman Odyshew on 06.09.2021.
//

import Foundation

class EventPublisher {
    private let requestFactory: RequestFactory
    
    init(_ requestFactory: RequestFactory) {
        self.requestFactory = requestFactory
    }
    
    func publish(_ event: PublishEvent, _ complete: ((_:Error?)->())?) {
        guard var request: URLRequest = requestFactory.publishRequest else {
            complete?(ABSmartlyError("Can not create context url"))
            return
        }
        
        let session = URLSession.shared
        request.httpBody = event.serializeValue.data(using: .ascii)
        
        let task = session.dataTask(with: request, completionHandler: { data, response, error in
            guard error == nil else {
                complete?(error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                complete?(NetworkError(httpResponse.statusCode, ""))
                return
            }
            
            complete?(nil)
        })
        task.resume()
    }    
}
