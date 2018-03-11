//
//  IotaMultisig.swift
//  IotaKit
//
//  Created by Pasquale Ambrosini on 07/03/18.
//

import Foundation

public class IotaMultisig: IotaDebuggable {
	fileprivate let curl: CurlSource = CurlMode.kerl.create()
	fileprivate var signing: IotaSigning = IotaSigning(curl: CurlMode.kerl.create())
	fileprivate var iota: Iota
	
	public var debug = false {
		didSet {
			self.iota.debug = self.debug
		}
	}
	
	public init(node: String, port: UInt) {
		self.iota = Iota(node: node, port: port)
	}
	
	public init(node: String) {
		self.iota = Iota(node: node)
	}
	
	public func digest(seed: String, security: Int, index: Int) -> String {
		let key = self.signing.key(inSeed: IotaConverter.trits(trytes: seed, length: Curl.hashLength), index: index, security: security)
		return IotaConverter.trytes(trits: self.signing.digest(key: key))
	}
	
	public func address(fromDigests digests: [String]) -> String {
		self.curl.reset()
		for d in digests {
			let digestTrits = IotaConverter.trits(fromString: d)
			_ = self.curl.absorb(trits: digestTrits)
		}
		
		var addressTrits: [Int] = Array(repeating: 0, count: Curl.hashLength)
		_ = self.curl.squeeze(trits: &addressTrits, offset: 0, length: Curl.hashLength)
		return IotaConverter.trytes(trits: addressTrits)
	}
	
	public func key(seed: String, security: Int, index: Int) -> String {
		let tritsSeed = IotaConverter.trits(trytes: seed, length: Curl.hashLength)
		let key = self.signing.key(inSeed: tritsSeed, index: index, security: security)
		return IotaConverter.trytes(trits: key)
	}
	
	public func validate(address: String, digests: [String]) -> Bool {
		let digestsTrits = digests.map { IotaConverter.trits(fromString: $0) }
		return self.validate(address: address, digests: digestsTrits)
	}
	
	public func validate(address: String, digests: [[Int]]) -> Bool {
		self.curl.reset()
		
		for keyDigest in digests {
			_ = self.curl.absorb(trits: keyDigest)
		}
		
		var addressTrits: [Int] = Array(repeating: 0, count: Curl.hashLength)
		_ = self.curl.squeeze(trits: &addressTrits)
		
		return IotaConverter.trytes(trits: addressTrits) == address
	}
	
	public func validateSignature(signedBundle: IotaBundle, inputAddress: String) -> Bool {
		return self.signing.validateSignature(signedBundle: signedBundle, inputAddress: inputAddress)
	}
	
	public func prepareTransfers(securitySum: Int, inputAddress: String, remainderAddress: String, transfers: [IotaTransfer], keys: [String], skipChecks: Bool = false, _ success: @escaping (_ bundle: IotaBundle) -> Void, error: @escaping (Error) -> Void) {
		
		self.initiateTransfers(securitySum: securitySum, inputAddress: inputAddress, remainderAddress: remainderAddress, transfers: transfers, skipChecks: skipChecks, { (bundle) in
			step1(bundle: bundle)
		}, error: error)
		
		func step1(bundle: IotaBundle) {
			var theBundle = bundle
			for k in keys {
				self.addSignature(bundle: &theBundle, inputAddress: inputAddress, keyTrytes: k)
			}
		
			success(theBundle)
		}
	}
	
	public func attachToTangle(securitySum: Int, address: String, keys: [String], _ success: @escaping (_ transactions: [IotaTransaction]) -> Void, error: @escaping (Error) -> Void) {
		
		let transfers = [IotaTransfer(address: address, value: 0, timestamp: nil, hash: nil, persistence: false)]
		
		self.prepareTransfers(securitySum: securitySum, inputAddress: address, remainderAddress: "".rightPadded(count: 81, character: "9"), transfers: transfers, keys: keys, skipChecks: true, { (bundle) in
			continueWithBundle(bundle: bundle)
		}, error: error)
		
		func continueWithBundle(bundle: IotaBundle) {
			let trxb = bundle.transactions
			var bundleTrytes: [String] = []
			
			for trx in trxb {
				bundleTrytes.append(trx.trytes)
			}
			bundleTrytes.reverse()
			self.iota.sendTrytes(trytes: bundleTrytes, success, error: error)
		}
	}
	
	public func sendTransfers(securitySum: Int, inputAddress: String, remainderAddress: String, transfers: [IotaTransfer], keys: [String], skipChecks: Bool = false, _ success: @escaping (_ transactions: [IotaTransaction]) -> Void, error: @escaping (Error) -> Void) {
		
		self.prepareTransfers(securitySum: securitySum, inputAddress: inputAddress, remainderAddress: remainderAddress, transfers: transfers, keys: keys, skipChecks: skipChecks, { (bundle) in
			continueWithBundle(bundle: bundle)
		}, error: error)
		
		func continueWithBundle(bundle: IotaBundle) {
			let trxb = bundle.transactions
			var bundleTrytes: [String] = []
			
			for trx in trxb {
				bundleTrytes.append(trx.trytes)
			}
			bundleTrytes.reverse()
			self.iota.sendTrytes(trytes: bundleTrytes, success, error: error)
		}
	}
	
	public func addSignature( bundle: inout IotaBundle, inputAddress: String, keyTrytes: String) {
		let security = keyTrytes.count / IotaConstants.messageLength
		let key = IotaConverter.trits(fromString: keyTrytes)
		
		var numSignedTxs = 0
		
		for i in 0..<bundle.transactions.count {
			guard bundle.transactions[i].address == inputAddress else { continue }
			guard IotaInputValidator.isNinesTrytes(trytes: bundle.transactions[i].signatureFragments) else { numSignedTxs += 1; continue }
			let bundleHash = bundle.transactions[i].bundle
			
			let firstFragment = key.slice(from: 0, to: 6561)
			
			var normalizedBundleFragments: [[Int]] = Array(repeating: [0, 0, 0], count: 27)
			let normalizedBundleHash = bundle.normalizedBundle(bundleHash: bundleHash)
			
			for k in 0..<3 {
				normalizedBundleFragments[k] = normalizedBundleHash.slice(from: k*27, to: (k+1)*27)
			}
			
			let firstBundleFragment = normalizedBundleFragments[numSignedTxs % 3]
			
			let firstSignedFragment = self.signing.signatureFragment(normalizedBundleFragment: firstBundleFragment, keyFragment: firstFragment)
			
			bundle.transactions[i].signatureFragments = IotaConverter.trytes(trits: firstSignedFragment)
			
			for j in 1..<security {
				let nextFragment = key.slice(from: 6561*j, to: (j+1)*6561)
				let nextBundleFragment = normalizedBundleFragments[(numSignedTxs+j) % 3]
				let nextSignedFragment = self.signing.signatureFragment(normalizedBundleFragment: nextBundleFragment, keyFragment: nextFragment)
				if (i+j) >= bundle.transactions.count { continue }
				bundle.transactions[i+j].signatureFragments = IotaConverter.trytes(trits: nextSignedFragment)
			}
			break
		}
	}
}










extension IotaMultisig {
	
	internal func initiateTransfers(securitySum: Int, inputAddress: String, remainderAddress: String, transfers: [IotaTransfer], skipChecks: Bool = false, _ success: @escaping (_ bundle: IotaBundle) -> Void, error: @escaping (Error) -> Void) {
		var bundle = IotaBundle()
		var signatureFragments: [String] = []
		var totalValue: UInt64 = 0
		var tag = ""
		
		IotaDebug("Preparing transfers")
		for var transfer in transfers {
			if IotaChecksum.isValidChecksum(address: transfer.address) {
				transfer.address = IotaChecksum.removeChecksum(address: transfer.address)!
			}
			
			var signatureMessageLength = 1
			
			if transfer.message.count > IotaConstants.messageLength {
				signatureMessageLength += transfer.message.count / IotaConstants.messageLength
				
				var msgCopy = transfer.message
				
				while !msgCopy.isEmpty {
					var fragment = msgCopy.substring(from: 0, to: IotaConstants.messageLength)
					msgCopy = msgCopy.substring(from: IotaConstants.messageLength, to: msgCopy.count)
					fragment.rightPad(count: IotaConstants.messageLength, character: "9")
					signatureFragments.append(fragment)
				}
			}else {
				var fragment = transfer.message
				fragment.rightPad(count: IotaConstants.messageLength, character: "9")
				signatureFragments.append(fragment)
			}
			
			tag = transfer.tag
			tag.rightPad(count: IotaConstants.tagLength, character: "9")
			
			let timestamp = floor(Date().timeIntervalSince1970)
			bundle.addEntry(signatureMessageLength: signatureMessageLength, address: transfer.address, value: Int64(transfer.value), tag: tag, timestamp: UInt64(timestamp))
			totalValue += transfer.value
		}
		guard totalValue != 0 else {
			bundle.finalize(customCurl: self.curl.clone())
			bundle.addTrytes(signatureFragments: signatureFragments)
			success(bundle)
			return
		}
		
		self.iota.balances(addresses: [inputAddress], { (result) in
			var totalBalance = result.values.reduce(0, +)
			if skipChecks && totalBalance == 0 {
				totalBalance = Int64(totalValue)+1
			}
			if totalValue > totalBalance {
				error(IotaAPIError("Not enough balance"))
				return
			}
			continueWithBalance(totalBalance: UInt64(totalBalance))
		}, error: error)
		
		func continueWithBalance(totalBalance: UInt64) {
			IotaDebug("Continue with balance \(totalBalance)")
			let timestamp = floor(Date().timeIntervalSince1970)
			
			if totalBalance > 0 {
				let toSubtract = 0 - Int64(totalBalance)
				bundle.addEntry(signatureMessageLength: securitySum, address: inputAddress, value: toSubtract, tag: tag, timestamp: UInt64(timestamp))
			}
			
			if totalBalance > totalValue {
				let remainder = totalBalance - totalValue
				IotaDebug("Remainder to send back \(remainder)")
				bundle.addEntry(signatureMessageLength: 1, address: remainderAddress, value: Int64(remainder), tag: tag, timestamp: UInt64(timestamp))
			}
			bundle.finalize(customCurl: self.curl.clone())
			bundle.addTrytes(signatureFragments: signatureFragments)
			success(bundle)
		}
	}
}
