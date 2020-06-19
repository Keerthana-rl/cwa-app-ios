//
// Corona-Warn-App
//
// SAP SE and all other contributors
// copyright owners license this file to you under the Apache
// License, Version 2.0 (the "License"); you may not use this
// file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.
//

@testable import ENA
import ExposureNotification
import Foundation
import XCTest

final class ExposureDetectionExecutorTests: XCTestCase {
	private let downloadedPackageStore = DownloadedPackagesSQLLiteStore.inMemory()

	override func setUp() {
		downloadedPackageStore.open()
	}

	override func tearDown() {
		downloadedPackageStore.reset()
	}

	// MARK: - Determine Available Data Tests

	func testDetermineAvailableData_Success() throws {
		let testDaysAndHours = (days: ["Hello"], hours: [23])
		let detectionDelegate = MockExposureDetectionDelegate()
		let sut = ExposureDetectionExecutor(
			client: ClientMock(availableDaysAndHours: testDaysAndHours),
			downloadedPackagesStore: downloadedPackageStore,
			store: MockTestStore(),
			exposureDetector: MockExposureDetector()
		)
		let successExpectation = expectation(description: "Expect that the completion handler is called!")

		sut.exposureDetection(ExposureDetection(delegate: detectionDelegate), determineAvailableData: { daysAndHours in
			defer { successExpectation.fulfill() }

			XCTAssertEqual(daysAndHours?.days, testDaysAndHours.days)
			// Hours are explicitly returned as empty
			XCTAssertEqual(daysAndHours?.hours, [])
		})

		waitForExpectations(timeout: 2.0)
	}

	func testDetermineAvailableData_Failure() throws {
		let detectionDelegate = MockExposureDetectionDelegate()
		let sut = ExposureDetectionExecutor(
			client: ClientMock(urlRequestFailure: .serverError(500)),
			downloadedPackagesStore: downloadedPackageStore,
			store: MockTestStore(),
			exposureDetector: MockExposureDetector()
		)
		let successExpectation = expectation(description: "Expect that the completion handler is called!")

		sut.exposureDetection(ExposureDetection(delegate: detectionDelegate), determineAvailableData: { daysAndHours in
			defer { successExpectation.fulfill() }

			XCTAssertNil(daysAndHours)
		})

		waitForExpectations(timeout: 2.0)
	}

	// MARK: - Download Delta Tests

	func testDownloadDelta_GetDeltaSuccess() throws {
		let cal = Calendar(identifier: .gregorian)
		let today = cal.startOfDay(for: Date()).formatted
		let yesterday = try XCTUnwrap(cal.date(byAdding: DateComponents(day: -1), to: Date())?.formatted)

		let remoteDaysAndHours: DaysAndHours = ([yesterday, today], [])
		let localDaysAndHours: DaysAndHours = ([yesterday], [])

		downloadedPackageStore.set(day: localDaysAndHours.days[0], package: try .makePackage())

		let detectionDelegate = MockExposureDetectionDelegate()
		let sut = ExposureDetectionExecutor(
			client: ClientMock(),
			downloadedPackagesStore: downloadedPackageStore,
			store: MockTestStore(),
			exposureDetector: MockExposureDetector()
		)

		let missingDaysAndHours = sut.exposureDetection(ExposureDetection(delegate: detectionDelegate), downloadDeltaFor: remoteDaysAndHours)

		XCTAssertEqual(missingDaysAndHours.days, [today])
	}

	func testDownloadDelta_TestStoreIsPruned() throws {
		downloadedPackageStore.set(day: Date.distantPast.formatted, package: try SAPDownloadedPackage.makePackage())

		let detectionDelegate = MockExposureDetectionDelegate()
		let sut = ExposureDetectionExecutor(
			client: ClientMock(),
			downloadedPackagesStore: downloadedPackageStore,
			store: MockTestStore(),
			exposureDetector: MockExposureDetector()
		)

		_ = sut.exposureDetection(ExposureDetection(delegate: detectionDelegate), downloadDeltaFor: (["Hello"], []))

		XCTAssert(downloadedPackageStore.allDays().isEmpty, "The store should be empty after being pruned!")
	}

	// MARK: - Store Delta Tests

	func testStoreDelta_Success() throws {
		let testDaysAndHours: DaysAndHours = (days: ["2020-01-01"], hours: [])
		let testPackage = try SAPDownloadedPackage.makePackage()
		let completionExpectation = expectation(description: "Expect that the completion handler is called.")

		let detectionDelegate = MockExposureDetectionDelegate()
		let sut = ExposureDetectionExecutor(
			client: ClientMock(availableDaysAndHours: testDaysAndHours, downloadedPackage: testPackage),
			downloadedPackagesStore: downloadedPackageStore,
			store: MockTestStore(),
			exposureDetector: MockExposureDetector()
		)

		sut.exposureDetection(ExposureDetection(delegate: detectionDelegate), downloadAndStore: testDaysAndHours) { error in
			defer { completionExpectation.fulfill() }
			XCTAssertNil(error)

			guard let storedPackage = self.downloadedPackageStore.package(for: "2020-01-01") else {
				// We can't XCUnwrap here as completion handler closure cannot throw
				XCTFail("Package store did not contain downloaded delta package!")
				return
			}
			XCTAssertEqual(storedPackage.bin, testPackage.bin)
			XCTAssertEqual(storedPackage.signature, testPackage.signature)
		}

		waitForExpectations(timeout: 2.0)
	}
}

// TODO: Move below to somewhere else, probably helpers section

class MockExposureDetector: ExposureDetector {
	func detectExposures(configuration: ENExposureConfiguration, diagnosisKeyURLs: [URL], completionHandler: @escaping ENDetectExposuresHandler) -> Progress {
		Progress(totalUnitCount: 1)
	}
}

class MockExposureDetectionDelegate: ExposureDetectionDelegate {
	func exposureDetection(_ detection: ExposureDetection, determineAvailableData completion: @escaping (DaysAndHours?) -> Void) {
		completion(nil)
	}

	func exposureDetection(_ detection: ExposureDetection, downloadDeltaFor remote: DaysAndHours) -> DaysAndHours {
		([], [])
	}

	func exposureDetection(_ detection: ExposureDetection, downloadAndStore delta: DaysAndHours, completion: @escaping (Error?) -> Void) {
		completion(nil)
	}

	func exposureDetection(_ detection: ExposureDetection, downloadConfiguration completion: @escaping (ENExposureConfiguration?) -> Void) {
		completion(nil)
	}

	func exposureDetectionWriteDownloadedPackages(_ detection: ExposureDetection) -> WrittenPackages? {
		nil
	}

	func exposureDetection(_ detection: ExposureDetection, detectSummaryWithConfiguration configuration: ENExposureConfiguration, writtenPackages: WrittenPackages, completion: @escaping DetectionHandler) {
		completion(.failure(ENError(ENError.notAuthorized)))
	}
}

private extension Date {
	var formatted: String {
		DateFormatter.packagesDateFormatter.string(from: self)
	}
}

private extension DateFormatter {
	static var packagesDateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "yyyy-MM-dd"
		formatter.timeZone = TimeZone(abbreviation: "UTC")
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.calendar = Calendar(identifier: .gregorian)

		return formatter
	}()
}
