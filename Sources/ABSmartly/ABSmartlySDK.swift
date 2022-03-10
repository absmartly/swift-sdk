public final class ABSmartlySDK {   
    private let provider: ContextDataProvider
    private let eventPublisher: EventPublisher
    
    public init(_ options: ClientOptions) {
        let requestFactory = RequestFactory(options)
        self.eventPublisher = EventPublisher(requestFactory)
        self.provider = ContextDataProvider(requestFactory, options)
    }
    
    public func createContextWithData(config: ContextConfig, contextData: ContextData) -> Context {
        let promise: Promise<ContextData> = Promise({ success, error in
            success(contextData)
        })
        
        return Context(eventPublisher, provider, promise, config)
    }
    
    public func createContext(config: ContextConfig) -> Context {
        return Context(eventPublisher, provider, provider.getContextData(), config)
    }
  
    public func contextData(_ complete: @escaping ((_:ContextData?, _:Error?)->())) {
        provider.getContextData(complete)
    }
}
