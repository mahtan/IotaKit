//
//  IotaBundleExtension.swift
//  IotaKit
//
//  Created by Pasquale Ambrosini on 15/01/2018.
//

import Foundation

public extension IotaBundle {

	/// Adds an entry to the Iota Bundle.
	///
	/// - Parameters:
	///   - signatureMessageLength: The length of the signature message.
	///   - address: The address.
	///   - value: The value in Iota.
	///   - tag: The tag.
	///   - timestamp: The timestamp.
	mutating func addEntry(signatureMessageLength: Int, address: String, value: Int64, tag: String, timestamp: UInt64) {
		for i in 0..<signatureMessageLength {

			let trx = IotaTransaction(value: i == 0 ? value : 0, address: address, tag: tag, timestamp: timestamp)
			self.transactions.append(trx)
		}
	}

	internal mutating func finalize(customCurl: CurlSource!) {
		//var normalizedBundleValue: [Int]
		var hash: [Int] = Array(repeating: 0, count: Curl.hashLength)
		var obsoleteTagTrits: [Int] = Array(repeating: 0, count: 81)
		var valid = true
		let curl = customCurl == nil ? CurlMode.kerl.create() : customCurl!
		var hashInTrytes: String = ""
		repeat {
			curl.reset()
			for i in 0..<self.transactions.count {
				let valueTrits = IotaConverter.trits(trytes: Int(self.transactions[i].value), length: 81)
				let timestampTrits = IotaConverter.trits(trytes: Int(self.transactions[i].timestamp), length: 27)
				self.transactions[i].currentIndex = UInt(i)
				let currentIndexTrits = IotaConverter.trits(trytes: Int(self.transactions[i].currentIndex), length: 27)
				self.transactions[i].lastIndex = UInt(self.transactions.count-1)
				let lastIndexTrits = IotaConverter.trits(trytes: Int(self.transactions[i].lastIndex), length: 27)
				var body = self.transactions[i].address
				body += IotaConverter.trytes(trits: valueTrits)
				body += self.transactions[i].obsoleteTag
				body += IotaConverter.trytes(trits: timestampTrits)
				body += IotaConverter.trytes(trits: currentIndexTrits)
				body += IotaConverter.trytes(trits: lastIndexTrits)
				let ttTrits = IotaConverter.trits(fromString: body)
				_ = curl.absorb(trits: ttTrits)
			}

			_ = curl.squeeze(trits: &hash)
			hashInTrytes = IotaConverter.trytes(trits: hash)
			let normalizedBundleValue = self.normalizedBundle(bundleHash: hashInTrytes)
			var foundValue = false
			for aNormalizedBundleValue in normalizedBundleValue where aNormalizedBundleValue == 13 {
				foundValue = true
				obsoleteTagTrits = IotaConverter.trits(fromString: self.transactions[0].obsoleteTag)
				IotaConverter.increment(trits: &obsoleteTagTrits, size: 81)
				self.transactions[0].obsoleteTag = IotaConverter.trytes(trits: obsoleteTagTrits)
			}
			valid = !foundValue
		} while !valid

		for i in 0..<self.transactions.count {
			self.transactions[i].bundle = hashInTrytes
		}
	}

	internal mutating func addTrytes(signatureFragments: [String]) {
		var emptySignatureFragment = ""
		let emptyHash = IotaBundle.emptyHash
		let emptyTimestamp: UInt64 = 999999999

		emptySignatureFragment.rightPad(count: 2187, character: "9")

		for i in 0..<self.transactions.count {
			let signatureFragmentCheck = signatureFragments.count <= i || signatureFragments[i].isEmpty
			self.transactions[i].signatureFragments = signatureFragmentCheck ? emptySignatureFragment : signatureFragments[i]
			self.transactions[i].trunkTransaction = emptyHash
			self.transactions[i].branchTransaction = emptyHash
			self.transactions[i].attachmentTimestamp = emptyTimestamp
			self.transactions[i].attachmentTimestampLowerBound = emptyTimestamp
			self.transactions[i].attachmentTimestampUpperBound = emptyTimestamp

			var nonce = ""
			nonce.rightPad(count: 27, character: "9")
			self.transactions[i].nonce = nonce
		}
	}

	internal func normalizedBundle(bundleHash: String) -> [Int] {
		var normalizedBundle: [Int] = Array(repeating: 0, count: 81)

		for i in 0..<3 {
			var sum: Int = 0
			for j in 0..<27 {
				let char = bundleHash.substring(from: i*27 + j, to: i*27 + j + 1)
				normalizedBundle[i*27 + j] = Int(IotaConverter.longValue(IotaConverter.trits(fromString: char)))
				sum += normalizedBundle[i*27 + j]
			}

			if sum >= 0 {
				while sum > 0 {
					for j in 0..<27 where normalizedBundle[i*27+j] > -13 {
						normalizedBundle[i*27+j] -= 1
						break
					}
					sum -= 1
				}
			} else {
				while sum < 0 {
					for j in 0..<27 where normalizedBundle[i*27+j] < 13 {
						normalizedBundle[i*27+j] += 1
						break
					}
					sum += 1
				}
			}
		}
		return normalizedBundle
	}
}
