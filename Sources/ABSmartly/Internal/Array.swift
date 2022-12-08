//
// Created by Márcio Martins on 08/12/2022.
//

import Foundation

extension Array {
	mutating func insertUniqueSorted(_ element: Element, isSorted: (Element, Element) -> Bool) {
		var left = 0
		var right = count - 1
		while left <= right {
			let mid = left + (right - left) / 2
			if isSorted(self[mid], element) {
				left = mid + 1
			} else if isSorted(element, self[mid]) {
				right = mid - 1
			} else {
				return
			}
		}

		self.insert(element, at: left)
	}
}
