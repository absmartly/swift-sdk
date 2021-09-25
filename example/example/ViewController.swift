//
//  ViewController.swift
//  example
//
//  Created by Roman Odyshew on 21.09.2021.
//

import UIKit
import absmartly

class ViewController: UIViewController {
    private let button = UIButton()
    private var context: Context?

    var buttonClickAction: (()->())?

    var buttonColor: UIColor = .clear {
        didSet {
            button.backgroundColor = buttonColor
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        view.backgroundColor = .gray
        button.setTitle("Start", for: .normal)
        button.layer.cornerRadius = 40
        
        view.addSubview(button)
        
        button.translatesAutoresizingMaskIntoConstraints = false
        let horizontalConstraint = (NSLayoutConstraint(item: button, attribute: .centerX, relatedBy: .equal, toItem: view, attribute: .centerX, multiplier: 1, constant: 0))
        let verticalConstraint = (NSLayoutConstraint(item: button, attribute: .centerY, relatedBy: .equal, toItem: view, attribute: .centerY, multiplier: 1, constant: 0))
        let widthConstraint = (NSLayoutConstraint(item: button, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 300))
        let heightConstraint = (NSLayoutConstraint(item: button, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 80))
        view.addConstraints([horizontalConstraint, verticalConstraint, widthConstraint, heightConstraint])
        
        button.addTarget(self, action: #selector(click), for: .touchUpInside)
    }
    
    @objc private func click() {
        buttonClickAction?()
    }
}
