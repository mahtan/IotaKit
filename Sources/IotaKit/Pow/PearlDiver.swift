//
//  PearlDiver.swift
//  IotaKitPackageDescription
//
//  Created by Pasquale Ambrosini on 17/01/2018.
//	See https://github.com/iotaledger/iri/blob/dev/src/main/java/com/iota/iri/hash/PearlDiver.java

import Foundation
import Dispatch

enum PearlDiverState {
	case idle
	case running
	case canceled
	case completed
}

private let transactionLength = 8019
private let curlHashLength = Curl.hashLength
private let curlStateLength = curlHashLength*3

private let highBits: UInt64 = 0b11111111_11111111_11111111_11111111_11111111_11111111_11111111_11111111
private let lowBits: UInt64 = 0b00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000

let testBits1: UInt64 = 0b1101101101101101101101101101101101101101101101101101101101101101
let testBits2: UInt64 = 0b1011011011011011011011011011011011011011011011011011011011011011
let testBits3: UInt64 = 0b1111000111111000111111000111111000111111000111111000111111000111
let testBits4: UInt64 = 0b1000111111000111111000111111000111111000111111000111111000111111
let testBits5: UInt64 = 0b0111111111111111111000000000111111111111111111000000000111111111
let testBits6: UInt64 = 0b1111111111000000000111111111111111111000000000111111111111111111
let testBits7: UInt64 = 0b1111111111000000000000000000000000000111111111111111111111111111
let testBits8: UInt64 = 0b0000000000111111111111111111111111111111111111111111111111111111

class PearlDiver {
	fileprivate var state: PearlDiverState = .idle
	fileprivate var transactionTrits: [Int] = []
	private let queue = DispatchQueue(label: "iota-pow", qos: .userInteractive, attributes: .concurrent)

	func cancel() {
		queue.sync(flags: .barrier) {
			self.state = .canceled
		}
	}

	func search(transactionTrits: [Int], minWeightMagnitude: Int, numberOfThreads: Int) -> [Int] {

		self.transactionTrits = transactionTrits.map { $0 }
		queue.sync(flags: .barrier) {
			self.state = .running
		}

		var midCurlStateLow: [UInt64] = Array(repeating: 0, count: curlStateLength)
		var midCurlStateHigh: [UInt64] = Array(repeating: 0, count: curlStateLength)

		do {
			for iIndex in curlHashLength..<curlStateLength {
				midCurlStateLow[iIndex] = highBits
				midCurlStateHigh[iIndex] = highBits
			}

			var offset = 0
			var curlScratchpadLow: [UInt64] = Array(repeating: 0, count: curlStateLength)
			var curlScratchpadHigh: [UInt64] = Array(repeating: 0, count: curlStateLength)
			for _ in stride(from: (transactionLength-curlHashLength)/curlHashLength, to: 0, by: -1) {
				for jIndex in 0..<curlHashLength {
					evaluateState(state: transactionTrits[offset], jIndex: jIndex, midCurlStateLow: &midCurlStateLow, midCurlStateHigh: &midCurlStateHigh)
					offset += 1
				}
				PearlDiver.transform(&midCurlStateLow, &midCurlStateHigh, &curlScratchpadLow, &curlScratchpadHigh)
			}

			for jIndex in 0..<162 {
				evaluateState(state: transactionTrits[offset], jIndex: jIndex, midCurlStateLow: &midCurlStateLow, midCurlStateHigh: &midCurlStateHigh)
				offset += 1
			}

			midCurlStateLow[162 + 0] = testBits1
			midCurlStateHigh[162 + 0] = testBits2
			midCurlStateLow[162 + 1] = testBits3
			midCurlStateHigh[162 + 1] = testBits4
			midCurlStateLow[162 + 2] = testBits5
			midCurlStateHigh[162 + 2] = testBits6
			midCurlStateLow[162 + 3] = testBits7
			midCurlStateHigh[162 + 3] = testBits8
		}

		var numOfThreads = numberOfThreads
		while numOfThreads > 0 {
			numOfThreads -= 1
			DispatchQueue.global(qos: .userInitiated).async {
				self.powThread(threadIndex: numOfThreads,
							   minWeightMagnitude: minWeightMagnitude,
							   midCurlStateLow: midCurlStateLow,
							   midCurlStateHigh: midCurlStateHigh)
			}
		}

		while self.state != .completed {
			Thread.sleep(forTimeInterval: 0.1)
		}
		return self.transactionTrits
	}

	fileprivate func evaluateState(state: Int, jIndex: Int, midCurlStateLow: inout [UInt64], midCurlStateHigh: inout [UInt64]) {
		switch state {
		case 0:
			midCurlStateLow[jIndex] = highBits
			midCurlStateHigh[jIndex] = highBits
		case 1:
			midCurlStateLow[jIndex] = lowBits
			midCurlStateHigh[jIndex] = highBits
		default:
			midCurlStateLow[jIndex] = highBits
			midCurlStateHigh[jIndex] = lowBits
		}
	}

	fileprivate func powThread(threadIndex: Int, minWeightMagnitude: Int, midCurlStateLow: [UInt64], midCurlStateHigh: [UInt64]) {
		var midCurlStateCopyLow: [UInt64] = Array(repeating: 0, count: curlStateLength)
		var midCurlStateCopyHigh: [UInt64] = Array(repeating: 0, count: curlStateLength)

		midCurlStateCopyLow = midCurlStateLow
		midCurlStateCopyHigh = midCurlStateHigh

		for _ in stride(from: threadIndex, to: 0, by: -1) {
			PearlDiver.increment(midCurlStateCopyLow: &midCurlStateCopyLow,
								 midCurlStateCopyHigh: &midCurlStateCopyHigh,
								 fromIndex: 162+curlHashLength/9, toIndex: 162 + (curlHashLength / 9) * 2)
		}

		var curlStateLow: [UInt64] = Array(repeating: 0, count: curlStateLength)
		var curlStateHigh: [UInt64] = Array(repeating: 0, count: curlStateLength)
		var curlScratchpadLow: [UInt64] = Array(repeating: 0, count: curlStateLength)
		var curlScratchpadHigh: [UInt64] = Array(repeating: 0, count: curlStateLength)

		var mask: UInt64 = 1
		var outMask: UInt64 = 1
		//var index = 0
		while self.state == .running {
			PearlDiver.increment(midCurlStateCopyLow: &midCurlStateCopyLow,
								 midCurlStateCopyHigh: &midCurlStateCopyHigh,
								 fromIndex: 162 + (curlHashLength / 9) * 2,
								 toIndex: curlHashLength)
			curlStateLow = midCurlStateCopyLow
			curlStateHigh = midCurlStateCopyHigh

			PearlDiver.transform(&curlStateLow, &curlStateHigh, &curlScratchpadLow, &curlScratchpadHigh)
			mask = highBits
			for iIndex in stride(from: minWeightMagnitude-1, to: -1, by: -1) {
				mask &= ~(curlStateLow[curlHashLength - 1 - iIndex] ^ curlStateHigh[
					curlHashLength - 1 - iIndex])
				if mask == 0 { break }
			}
			if self.state == .completed { return }
			if mask == 0 { continue }
			if self.state == .running {
				self.state = .completed
				while (outMask & mask) == 0 {
					outMask <<= 1
				}
				for iIndex in 0..<curlHashLength {
					self.transactionTrits[transactionLength - curlHashLength + iIndex] =
						(midCurlStateCopyLow[iIndex] & outMask) == 0 ? 1
						: (midCurlStateCopyHigh[iIndex] & outMask) == 0 ? -1 : 0
				}
			}
			break
		}
	}

	fileprivate static func transform(
		_ curlStateLow: inout [UInt64],
		_ curlStateHigh: inout [UInt64],
		_ curlScratchpadLow: inout [UInt64],
		_ curlScratchpadHigh: inout [UInt64]) {

		var curlScratchpadIndex = 0
		for _ in 0..<Curl.numOfRoundsP81 {
			curlScratchpadLow = curlStateLow
			curlScratchpadHigh = curlStateHigh

			for curlStateIndex in 0..<curlStateLength {
				let alpha = curlScratchpadLow[curlScratchpadIndex]
				let beta = curlScratchpadHigh[curlScratchpadIndex]

				if curlScratchpadIndex < 365 {
					curlScratchpadIndex += 364
				} else {
					curlScratchpadIndex += -365
				}
				let gamma = curlScratchpadHigh[curlScratchpadIndex]
				let delta = (alpha | (~gamma)) & (curlScratchpadLow[curlScratchpadIndex] ^ beta)
				curlStateLow[curlStateIndex] = ~delta
				curlStateHigh[curlStateIndex] = (alpha ^ gamma) | delta
			}
		}
	}

	fileprivate static func increment( midCurlStateCopyLow: inout [UInt64], midCurlStateCopyHigh: inout [UInt64], fromIndex: Int, toIndex: Int) {

		for index in fromIndex..<toIndex {
			if midCurlStateCopyLow[index] == lowBits {
				midCurlStateCopyLow[index] = highBits
				midCurlStateCopyHigh[index] = lowBits
			} else {
				if midCurlStateCopyHigh[index] == lowBits {
					midCurlStateCopyHigh[index] = highBits
				} else {
					midCurlStateCopyLow[index] = lowBits
				}
				break
			}
		}
	}

	//	fileprivate func arrayString(_ array: [UInt64]) -> String{
	//		let val =  array.reduce("", { (result, val) -> String in
	//			let v = String(val, radix: 16)
	//			return result+v+" "
	//		}).utf8.md5
	//		return "\(val.description)"
	//	}
}
