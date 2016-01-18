//
//  OperationTests.swift
//  OperationTests
//
//  Created by Daniel Thorpe on 26/06/2015.
//  Copyright (c) 2015 Daniel Thorpe. All rights reserved.
//

import XCTest
@testable import Operations

class TestOperation: Operation, ResultOperationType {

    enum Error: ErrorType {
        case SimulatedError
    }

    let numberOfSeconds: Double
    let simulatedError: ErrorType?
    let producedOperation: NSOperation?
    var didExecute: Bool = false
    var result: String? = "Hello World"

    init(delay: Double = 0.0001, error: ErrorType? = .None, produced: NSOperation? = .None) {
        numberOfSeconds = delay
        simulatedError = error
        producedOperation = produced
        super.init()
        name = "Test Operation"
    }

    override func execute() {

        if let producedOperation = self.producedOperation {
            let after = dispatch_time(DISPATCH_TIME_NOW, Int64(numberOfSeconds * Double(0.001) * Double(NSEC_PER_SEC)))
            dispatch_after(after, Queue.Main.queue) {
                self.produceOperation(producedOperation)
            }
        }

        let after = dispatch_time(DISPATCH_TIME_NOW, Int64(numberOfSeconds * Double(NSEC_PER_SEC)))
        dispatch_after(after, Queue.Main.queue) {
            self.didExecute = true
            self.finish(self.simulatedError)
        }
    }
}

struct TestCondition: OperationCondition {

    let name = "Test Condition"
    var isMutuallyExclusive = false
    let dependency: NSOperation?
    let condition: () -> Bool

    func dependencyForOperation(operation: Operation) -> NSOperation? {
        return dependency
    }

    func evaluateForOperation(operation: Operation, completion: OperationConditionResult -> Void) {
        completion(condition() ? .Satisfied : .Failed(BlockCondition.Error.BlockConditionFailed))
    }
}

class TestQueueDelegate: OperationQueueDelegate {

    typealias DidFinishOperation = (NSOperation, [ErrorType]) -> Void

    let didFinishOperation: DidFinishOperation?

    var did_willAddOperation: Bool = false
    var did_operationDidFinish: Bool = false
    var did_numberOfErrorThatOperationDidFinish: Int = 0

    init(didFinishOperation: DidFinishOperation? = .None) {
        self.didFinishOperation = didFinishOperation
    }

    func operationQueue(queue: OperationQueue, willAddOperation operation: NSOperation) {
        did_willAddOperation = true
    }

    func operationQueue(queue: OperationQueue, operationDidFinish operation: NSOperation, withErrors errors: [ErrorType]) {
        did_operationDidFinish = true
        did_numberOfErrorThatOperationDidFinish = errors.count
        didFinishOperation?(operation, errors)
    }
}

class OperationTests: XCTestCase {
    
    var queue: OperationQueue!
    var delegate: TestQueueDelegate!

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        delegate = TestQueueDelegate()
    }

    override func tearDown() {
        queue = nil
        delegate = nil
        ExclusivityManager.sharedInstance.__tearDownForUnitTesting()
        super.tearDown()
    }

    func runOperation(operation: NSOperation) {
        queue.delegate = delegate
        queue.addOperation(operation)
    }

    func runOperations(operations: [NSOperation]) {
        queue.delegate = delegate
        queue.addOperations(operations, waitUntilFinished: false)
    }

    func runOperations(operations: NSOperation...) {
        queue.delegate = delegate
        queue.addOperations(operations, waitUntilFinished: false)
    }

    func waitForOperation(operation: Operation, withExpectationDescription text: String = __FUNCTION__) {
        addCompletionBlockToTestOperation(operation, withExpectationDescription: text)
        queue.delegate = delegate
        queue.addOperation(operation)
        waitForExpectationsWithTimeout(3, handler: nil)
    }

    func waitForOperations(operations: Operation..., withExpectationDescription text: String = __FUNCTION__) {
        for (i, op) in operations.enumerate() {
            addCompletionBlockToTestOperation(op, withExpectationDescription: "\(i), \(text)")
        }
        queue.delegate = delegate
        queue.addOperations(operations, waitUntilFinished: false)
        waitForExpectationsWithTimeout(3, handler: nil)
    }

    func addCompletionBlockToTestOperation(operation: Operation, withExpectation expectation: XCTestExpectation) {
        weak var weakExpectation = expectation
        operation.addObserver(FinishedObserver { (_, _) in
            weakExpectation?.fulfill()
        })
    }

    func addCompletionBlockToTestOperation(operation: Operation, withExpectationDescription text: String = __FUNCTION__) -> XCTestExpectation {
        let expectation = expectationWithDescription("Test: \(text), \(NSUUID().UUIDString)")
        operation.addObserver(FinishedObserver { _, _ in
            expectation.fulfill()
        })
        return expectation
    }

}

class BasicTests: OperationTests {

    func test__queue_delegate_is_notified_when_operation_starts() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")

        let operation = TestOperation()
        addCompletionBlockToTestOperation(operation, withExpectation: expectation)

        runOperation(operation)
        waitForExpectationsWithTimeout(3, handler: nil)
        XCTAssertTrue(operation.didExecute)
        XCTAssertTrue(delegate.did_willAddOperation)
        XCTAssertTrue(delegate.did_operationDidFinish)
    }

    func test__executing_basic_operation() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")

        let operation = TestOperation()

        addCompletionBlockToTestOperation(operation, withExpectation: expectation)
        runOperation(operation)
        waitForExpectationsWithTimeout(3, handler: nil)

        XCTAssertTrue(operation.didExecute)
    }

    func test__operation_error_is_equatable() {
        XCTAssertEqual(OperationError.ConditionFailed, OperationError.ConditionFailed)
        XCTAssertEqual(OperationError.OperationTimedOut(1.0), OperationError.OperationTimedOut(1.0))
        XCTAssertNotEqual(OperationError.ConditionFailed, OperationError.OperationTimedOut(1.0))
        XCTAssertNotEqual(OperationError.OperationTimedOut(2.0), OperationError.OperationTimedOut(1.0))
    }

    func test__add_multiple_completion_blocks() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")
        let operation = TestOperation()

        var completionBlockOneDidRun = 0
        operation.addCompletionBlock {
            completionBlockOneDidRun += 1
        }

        var completionBlockTwoDidRun = 0
        operation.addCompletionBlock {
            completionBlockTwoDidRun += 1
        }

        var finalCompletionBlockDidRun = 0
        operation.addCompletionBlock {
            finalCompletionBlockDidRun += 1
            expectation.fulfill()
        }

        runOperation(operation)
        waitForExpectationsWithTimeout(3, handler: nil)

        XCTAssertEqual(completionBlockOneDidRun, 1)
        XCTAssertEqual(completionBlockTwoDidRun, 1)
        XCTAssertEqual(finalCompletionBlockDidRun, 1)
    }

    func test__add_multiple_dependencies() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")

        let dep1 = TestOperation()
        let dep2 = TestOperation()

        let operation = TestOperation()
        operation.addDependencies([dep1, dep2])

        addCompletionBlockToTestOperation(operation, withExpectation: expectation)
        runOperations(dep1, dep2, operation)
        waitForExpectationsWithTimeout(3, handler: nil)

        XCTAssertTrue(dep1.didExecute)
        XCTAssertTrue(dep2.didExecute)
    }

    func test__getting_user_initiated_default_false() {
        let operation = TestOperation()
        XCTAssertFalse(operation.userInitiated)
    }

    func test__setting_user_initiated() {
        let operation = TestOperation()
        operation.userInitiated = true
        XCTAssertTrue(operation.userInitiated)
    }

    func test__cancel_with_nil_error() {
        let operation = TestOperation()
        operation.cancelWithError(.None)
        XCTAssertTrue(operation.cancelled)
        XCTAssertEqual(operation.errors.count, 0)
    }

    func test__cancel_with_error() {
        let operation = TestOperation()
        operation.cancelWithError(OperationError.OperationTimedOut(1.0))
        XCTAssertTrue(operation.cancelled)
        XCTAssertTrue(operation.failed)
    }
}

class BlockOperationTests: OperationTests {

    func test__that_block_in_block_operation_executes() {

        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")
        var didExecuteBlock: Bool = false
        let operation = BlockOperation {
            didExecuteBlock = true
            expectation.fulfill()
        }
        runOperation(operation)
        waitForExpectationsWithTimeout(3, handler: nil)
        XCTAssertTrue(didExecuteBlock)
    }

    func test__that_block_operation_with_no_block_finishes_immediately() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")
        let operation = BlockOperation()
        addCompletionBlockToTestOperation(operation, withExpectation: expectation)
        runOperation(operation)
        waitForExpectationsWithTimeout(3, handler: nil)
        XCTAssertTrue(operation.finished)
    }

    func test__that_block_operation_does_not_execute_if_cancelled_before_ready() {
        var blockDidRun = 0

        let delay = DelayOperation(interval: 2)

        let block = BlockOperation { (continuation: BlockOperation.ContinuationBlockType) in
            blockDidRun += 2
            continuation(error: nil)
        }

        let blockToCancel = BlockOperation { (continuation: BlockOperation.ContinuationBlockType) in
            blockDidRun += 1
            continuation(error: nil)
        }

        addCompletionBlockToTestOperation(block, withExpectation: expectationWithDescription("Test: \(__FUNCTION__)"))

        block.addDependency(delay)
        blockToCancel.addDependency(delay)

        runOperations(delay, block, blockToCancel)
        blockToCancel.cancel()
        waitForExpectationsWithTimeout(3, handler: nil)

        XCTAssertEqual(blockDidRun, 2)
    }
}

private var completionBlockObservationContext = 0

class CompletionBlockOperationTests: OperationTests {

    func test__block_operation_with_default_block_runs_completion_block_once() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")
        var numberOfTimesCompletionBlockIsRun = 0

//        let operation = BlockOperation { (continuation: BlockOperation.ContinuationBlockType) in
//            print("** This is the task block on \(String.fromCString(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)))")
//            continuation(error: nil)
//        }

//        let operation = BlockOperation {
//            print("** This is the task block on \(String.fromCString(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)))")
//        }

        let operation = BlockOperation()

        operation.completionBlock = {
            numberOfTimesCompletionBlockIsRun += 1
            print("** This is a completion block on \(String.fromCString(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL)))")
        }

        let delay = DelayOperation(interval: 0.1)
        delay.addObserver(BlockObserver { op, errors in
            expectation.fulfill()
        })
        delay.addDependency(operation)

        runOperations(delay, operation)
        waitForExpectationsWithTimeout(3, handler: nil)

        XCTAssertEqual(numberOfTimesCompletionBlockIsRun, 1)
    }

    func test__nsblockoperation_runs_completion_block_once() {
        let _queue = NSOperationQueue()
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")
        let operation = NSBlockOperation()

        operation.completionBlock = {
            expectation.fulfill()
        }

        _queue.addOperation(operation)
        waitForExpectationsWithTimeout(3, handler: nil)
    }
}

class OperationDependencyTests: OperationTests {

    func test__dependent_operations_always_run() {
        queue.maxConcurrentOperationCount = 1
        let count = 2_000
        var counter1: Int = 0
        var counter2: Int = 0
        var counter3: Int = 0

        for i in 0..<count {

            let op1name = "Operation 1, iteration: \(i)"
            let op1Expectation = expectationWithDescription(op1name)
            let op1 = BlockOperation { (continuation: BlockOperation.ContinuationBlockType) in
                counter1 += 1
                op1Expectation.fulfill()
                continuation(error: nil)
            }

            let op2name = "Operation 2, iteration: \(i)"
            let op2Expectation = expectationWithDescription(op2name)
            let op2 = BlockOperation { (continuation: BlockOperation.ContinuationBlockType) in
                counter2 += 1
                op2Expectation.fulfill()
                continuation(error: nil)
            }

            let op3name = "Operation 3, iteration: \(i)"
            let op3Expectation = expectationWithDescription(op3name)
            let op3 = BlockOperation { (continuation: BlockOperation.ContinuationBlockType) in
                counter3 += 1
                op3Expectation.fulfill()
                continuation(error: nil)
            }

            op2.addDependency(op1)
            runOperations(op1, op2, op3)
        }

        waitForExpectationsWithTimeout(3, handler: nil)

        XCTAssertEqual(counter1, count)
        XCTAssertEqual(counter2, count)
        XCTAssertEqual(counter3, count)
    }

    func test__dependencies_execute_before_condition_dependencies() {

        let dependency1 = TestOperation()
        let dependency2 = TestOperation()

        let condition1 = TestCondition(isMutuallyExclusive: false, dependency: BlockOperation {
            XCTAssertTrue(dependency1.finished)
            XCTAssertTrue(dependency2.finished)
        }) { true }

        let condition2 = TestCondition(isMutuallyExclusive: false, dependency: BlockOperation {
            XCTAssertTrue(dependency1.finished)
            XCTAssertTrue(dependency2.finished)
        }) { true }


        let operation = TestOperation()
        operation.addDependency(dependency1)
        operation.addDependency(dependency2)
        operation.addCondition(condition1)
        operation.addCondition(condition2)

        addCompletionBlockToTestOperation(operation, withExpectation: expectationWithDescription("Test: \(__FUNCTION__)"))
        runOperations(dependency1, dependency2, operation)
        waitForExpectationsWithTimeout(3, handler: nil)

        XCTAssertTrue(dependency1.didExecute)
        XCTAssertTrue(dependency1.finished)
        XCTAssertTrue(dependency2.didExecute)
        XCTAssertTrue(dependency2.finished)
        XCTAssertTrue(operation.didExecute)
        XCTAssertTrue(operation.finished)
    }

    func test__dependencies_property_does_not_contain_dependency_waiter() {

        let dependency1 = TestOperation()
        let dependency2 = TestOperation()
        let condition1 = TestCondition(isMutuallyExclusive: false, dependency: TestOperation()) { true }
        let condition2 = TestCondition(isMutuallyExclusive: false, dependency: TestOperation()) { true }


        let operation = TestOperation()
        operation.addDependency(dependency1)
        operation.addDependency(dependency2)
        operation.addCondition(condition1)
        operation.addCondition(condition2)

        addCompletionBlockToTestOperation(operation, withExpectation: expectationWithDescription("Test: \(__FUNCTION__)"))
        runOperations(dependency1, dependency2, operation)
        waitForExpectationsWithTimeout(3, handler: nil)

        XCTAssertEqual(operation.dependencies.count, 4)
        XCTAssertNotNil(operation.waitForDependenciesOperation)
        XCTAssertFalse(operation.dependencies.contains(operation.waitForDependenciesOperation!))
    }

    func test__remove_last_dependency_destroys_dependency_waiter() {

        let dependency = TestOperation()
        let operation = TestOperation()
        operation.removeDependency(dependency) // Has no impact
        operation.addDependency(dependency)

        XCTAssertNotNil(operation.waitForDependenciesOperation)
        XCTAssertEqual(operation.dependencies.count, 1)

        operation.removeDependency(dependency)
        XCTAssertNil(operation.waitForDependenciesOperation)
        XCTAssertEqual(operation.dependencies.count, 0)
    }
}

class DelayOperationTests: OperationTests {

    func test__delay_operation_with_interval_name() {
        let delay = DelayOperation(interval: 1)
        XCTAssertEqual(delay.name, "Delay for 1.0 seconds")
    }

    func test__delay_operation_with_date_name() {
        let date = NSDate()
        let delay = DelayOperation(date: date)
        XCTAssertEqual(delay.name, "Delay until \(NSDateFormatter().stringFromDate(date))")
    }

    func test__delay_operation_with_negative_time_interval_finishes_immediately() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")
        let operation = DelayOperation(interval: -9_000_000)
        runOperation(operation)
        let after = dispatch_time(DISPATCH_TIME_NOW, Int64(0.05 * Double(NSEC_PER_SEC)))
        dispatch_after(after, Queue.Main.queue) {
            expectation.fulfill()
        }
        waitForExpectationsWithTimeout(1, handler: nil)
        XCTAssertTrue(operation.finished)
    }

    func test__delay_operation_with_distant_past_finishes_immediately() {
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")
        let operation = DelayOperation(date: NSDate.distantPast())
        runOperation(operation)
        let after = dispatch_time(DISPATCH_TIME_NOW, Int64(0.05 * Double(NSEC_PER_SEC)))
        dispatch_after(after, Queue.Main.queue) {
            expectation.fulfill()
        }
        waitForExpectationsWithTimeout(1, handler: nil)
        XCTAssertTrue(operation.finished)
    }

    func test__delay_operation_completes_after_interval() {
        var started: NSDate!
        var ended: NSDate!
        let expectation = expectationWithDescription("Test: \(__FUNCTION__)")
        let interval: NSTimeInterval = 0.5
        let operation = DelayOperation(interval: interval)
        operation.addCompletionBlock {
            ended = NSDate()
            expectation.fulfill()
        }
        started = NSDate()
        runOperation(operation)
        waitForExpectationsWithTimeout(1, handler: nil)
        XCTAssertTrue(operation.finished)
        let timeTaken = ended.timeIntervalSinceDate(started)
        XCTAssertGreaterThanOrEqual(timeTaken, interval)
        XCTAssertLessThanOrEqual(timeTaken - interval, 1.0)
    }
}

class CancellationOperationTests: OperationTests {

    func test__operation_with_dependency_cancelled_before_adding_still_executes() {

        let delay = DelayOperation(interval: 2)
        let operation = TestOperation()
        operation.addDependency(delay)

        addCompletionBlockToTestOperation(operation, withExpectation: expectationWithDescription("Test: \(__FUNCTION__)"))

        delay.cancel()

        runOperations(delay, operation)
        waitForExpectationsWithTimeout(5, handler: nil)

        XCTAssertTrue(operation.didExecute)
    }


    func test__operation_with_dependency_cancelled_after_adding_does_not_execute() {

        let delay = DelayOperation(interval: 2)
        let operation = TestOperation()
        operation.addDependency(delay)

        runOperations(delay, operation)
        delay.cancel()

        XCTAssertFalse(operation.didExecute)
    }

    func test__operation_with_dependency_whole_queue_cancelled() {
        let delay = DelayOperation(interval: 2)
        let operation = TestOperation()
        operation.addDependency(delay)

        runOperations(delay, operation)
        queue.cancelAllOperations()

        XCTAssertFalse(operation.didExecute)
    }
}






