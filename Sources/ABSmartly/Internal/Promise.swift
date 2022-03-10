import Foundation

class Promise<T> {
    private var state: State = .Ready
    
    private let lock = NSLock()
    
    var isDone: Bool {
        switch state {
        case .Error(_), .Success(_):
            return successCallbacks.count == 0 && errorCallbacks.count == 0 && finalCallbacks.count == 0
        default:
            return false
        }
    }
    
    private var successCallbacks: Queue<(T) -> Void> = Queue()
    private var errorCallbacks: Queue<(Error) -> Void> = Queue()
    private var finalCallbacks: Queue<()->()> = Queue()
    
    init(_ action: (@escaping(_:T)->(), @escaping(_:Error)->())->() ) {
        action(setSuccess, setError)
    }
    
    
    func onSuccess(_ action: @escaping (T)->()) {
        switch state {
        case .Ready, .SuccessProcess:
            successCallbacks.addElement(action)
        case .Success(let value):
            action(value)
        default:
            return
        }
    }
    
    func onError(_ action: @escaping (Error)->()) {
        switch state {
        case .Ready, .ErrorProcess:
            errorCallbacks.addElement(action)
        case .Error(let error):
            action(error)
        default:
            return
        }
    }
    
    func onFinal(_ action: (()->())?) {
        guard let action = action else {
            let _ = finalCallbacks.dequeue()
            return
        }
        
        switch state {
        case .Error(_), .Success(_):
            action()
        default:
            finalCallbacks.addElement(action)
        }
    }
    
    private func setSuccess(_ result: T) {
        lock.lock()
        guard case .Ready = state else {
            lock.unlock()
            return
        }
        
        state = .SuccessProcess
        lock.unlock()
        
        while successCallbacks.count > 0 {
            successCallbacks.dequeue()?(result)
        }
        
        state = .Success(result)
        
        while finalCallbacks.count > 0 {
            finalCallbacks.dequeue()?()
        }
    }
    
    private func setError(_ error: Error) {
        lock.lock()
        guard case .Ready = state else {
            lock.unlock()
            return
        }
        
        state = .ErrorProcess
        lock.unlock()
        
        while errorCallbacks.count > 0 {
            errorCallbacks.dequeue()?(error)
        }
        
        state = .Error(error)
        
        while finalCallbacks.count > 0 {
            finalCallbacks.dequeue()?()
        }
    }
}

extension Promise {
    enum State {
        case Ready
        case SuccessProcess
        case Success(T)
        case ErrorProcess
        case Error(Error)
    }
}
