import XCTest

@testable import Core

class HttpClientSpy: HttpClient {
    var requestsCallsCount: Int {
        completions.count
    }

    private(set) var urls: [URL] = []
    private(set) var completions: [(HttpClient.Result) -> Void] = []

    func get(from url: URL, completion: @escaping (HttpClient.Result) -> Void) {
        completions.append(completion)
        urls.append(url)
    }

    func completeWithSuccess(_ data: HttpClient.Response) {
        completions[0](.success(data))
    }

    func completeWithError(_ error: Error) {
        completions[0](.failure(error))
    }
}

class HomeServiceTests: XCTestCase {
    typealias Result = HomeService.Result
    typealias ServiceError = HomeService.Error

    func test_initDoesNotPerformAnyRequest() {
        let (_, httpClient) = makeSUT()

        XCTAssertEqual(httpClient.requestsCallsCount, 0)
    }

    func test_sendsUrlOnRequest() {
        let expectedUrl = URL.anyValue
        let (sut, httpClient) = makeSUT(url: expectedUrl)

        sut.getHome { _ in }

        XCTAssertEqual(httpClient.urls, [expectedUrl])
    }

    func test_failsOnRequestError() {
        let expectedError = NSError.anyValue

        let actualResult = result(when: { httpClient in
            httpClient.completeWithError(expectedError)
        })

        XCTAssertEqual(actualResult?.error as? ServiceError, .connection)
    }

    func test_failsOnHttpCodeDifferentThanOk() {
        let actualResult = result(when: { httpClient in
            httpClient.completeWithSuccess((400, self.jsonData))
        })

        XCTAssertEqual(actualResult?.error as? ServiceError, .notOk)
    }

    func test_parseHomeFromDataOnHttpCodeOk() throws {
        let actualResult = result(when: { httpClient in
            httpClient.completeWithSuccess((200, self.jsonData))
        })

        XCTAssertEqual(try actualResult?.get(), Home(balance: 15459.27, savings: 1000.0, spending: 500.0))
    }

    func test_failsWhenBalanceIsNotNumber() throws {
        expectFail(forJson:
            """
            {
                "balance_price": "ABC$#@",
                "svgs": 1000.0,
                "spending": 500.0
            }
            """
        )
    }

    func test_failsWhenBalanceIsEmpty() throws {
        expectFail(forJson:
            """
            {
                "balance_price": "",
                "svgs": 1000.0,
                "spending": 500.0
            }
            """
        )
    }

    func test_failsWhenThereIsNoBalance() throws {
        expectFail(forJson:
            """
            {
                "svgs": 1000.0,
                "spending": 500.0
            }
            """
        )
    }

    func test_failsWhenThereIsNoSavings() throws {
        expectFail(forJson:
            """
            {
                "balance_price": "15459.27",
                "spending": 500.0
            }
            """
        )
    }

    func test_failsWhenThereIsNoSpending() throws {
        expectFail(forJson:
            """
            {
                "balance_price": "15459.27",
                "svgs": 1000.0
            }
            """
        )
    }

    func test_doesNotCompleteWhenSutHaveBeenDeallocated() {
        let httpClient = HttpClientSpy()
        var sut: HomeService? = HomeService(url: .anyValue, httpClient: httpClient)

        var actualResult: Result?
        sut?.getHome { result in
            actualResult = result
        }

        sut = nil // the sut have been deallocated
        httpClient.completeWithError(ServiceError.notOk) // And the client completes

        XCTAssertNil(actualResult) // Then the getHome closure will never be executed
    }

    // MARK: Helpers

    private let jsonData = Data("""
    {
        "balance_price": "15459.27",
        "svgs": 1000.0,
        "spending": 500.0
    }
    """.utf8)

    private func result(
        when: @escaping (HttpClientSpy) -> Void,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Result? {
        let (sut, httpClient) = makeSUT(file: file, line: line)

        var actualResult: Result?
        sut.getHome { result in
            actualResult = result
        }
        when(httpClient)

        return actualResult
    }

    private func expectFail(
        forJson json: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let invalidJson = Data(json.utf8)

        let actualResult = result(when: { httpClient in
            httpClient.completeWithSuccess((200, invalidJson))
        }, file: file, line: line)

        XCTAssertEqual(actualResult?.error as? ServiceError, .invalidData, file: file, line: line)
    }

    private func makeSUT(
        url: URL = .anyValue,
        file: StaticString = #file,
        line: UInt = #line
    ) -> (HomeService, HttpClientSpy) {
        let httpClient = HttpClientSpy()
        let sut = HomeService(url: url, httpClient: httpClient)

        trackForMemoryLeak(sut, file: file, line: line)

        return (sut, httpClient)
    }

    private func trackForMemoryLeak(_ instance: AnyObject, file: StaticString = #file, line: UInt = #line) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(instance, "Instance should have been deallocated. Potential memory leak.", file: file, line: line)
        }
    }
}

extension URL {
    static var anyValue: URL {
        URL(fileURLWithPath: UUID().uuidString)
    }
}

extension NSError {
    static var anyValue: NSError {
        NSError(domain: UUID().uuidString, code: 0, userInfo: nil)
    }
}

extension Result {
    var error: Error? {
        if case let .failure(error) = self {
            return error
        }
        return nil
    }
}
