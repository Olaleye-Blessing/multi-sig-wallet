// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {MultiSig, IMultiSig} from "./../src/MultiSig.sol";
import {DeployMultiSig} from "./../script/DeployMultiSig.s.sol";
import {ContractOne, ContractTwo} from "./mocks/contracts.sol";

contract MultiSigTest is Test {
    MultiSig private multisig;
    ContractOne private contractOne;
    ContractTwo private contractTwo;

    address DEPLOYER = makeAddr("DEPLOYER");
    address OWNER_1 = address(1);
    address OWNER_2 = address(2);
    address OWNER_3 = address(3);
    address UNKNOWN = makeAddr("UNKNOWN");
    address RECIPIENT = makeAddr("RECIPIENT");

    function setUp() external {
        vm.deal(DEPLOYER, 100 ether);

        vm.prank(DEPLOYER);
        (multisig) = new DeployMultiSig().run();

        vm.startPrank(DEPLOYER);
        contractOne = new ContractOne();
        contractTwo = new ContractTwo();
        vm.stopPrank();

        vm.deal(OWNER_1, 100 ether);
        vm.deal(OWNER_2, 100 ether);
        vm.deal(OWNER_3, 100 ether);
        vm.deal(address(multisig), 50 ether);
        vm.deal(RECIPIENT, 1 ether);
    }

    // ============ Constructor Tests ============

    function test_constructorRevertsWithZeroMinConfirmations() public {
        address[] memory owners = new address[](3);
        owners[0] = OWNER_1;
        owners[1] = OWNER_2;
        owners[2] = OWNER_3;

        vm.expectRevert(IMultiSig.MultiSig__MinConfirmationsMustBeAtLeastOne.selector);
        new MultiSig(owners, 0);
    }

    function test_constructorRevertsWhenMinConfirmationsExceedsOwnerCount() public {
        address[] memory owners = new address[](2);
        owners[0] = OWNER_1;
        owners[1] = OWNER_2;

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__MinConfirmationsExceedsOwnerCount.selector, 5, 2));
        new MultiSig(owners, 5);
    }

    function test_constructorRevertsWithZeroAddressOwner() public {
        address[] memory owners = new address[](3);
        owners[0] = OWNER_1;
        owners[1] = address(0);
        owners[2] = OWNER_3;

        vm.expectRevert(IMultiSig.MultiSig__ZeroAddressNotAllowed.selector);
        new MultiSig(owners, 2);
    }

    function test_constructorRevertsWithDuplicateOwners() public {
        address[] memory owners = new address[](3);
        owners[0] = OWNER_1;
        owners[1] = OWNER_2;
        owners[2] = OWNER_1; // Duplicate

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__AddressAlreadyOwner.selector, OWNER_1));
        new MultiSig(owners, 2);
    }

    // ============ Submit Transaction Tests ============

    function test_submitTransactionRevertsWithZeroAddress() public {
        bytes memory data = abi.encodeWithSignature("increaseCount(uint256)", 4);

        vm.expectRevert(IMultiSig.MultiSig__ZeroAddressNotAllowed.selector);
        vm.prank(OWNER_1);
        multisig.submitTransaction(address(0), data);
    }

    function test_submitTransactionWithEther() public {
        uint256 sendValue = 5 ether;
        bytes memory data = "";

        vm.expectEmit(true, true, true, true, address(multisig));
        emit IMultiSig.TransactionSubmitted(OWNER_1, 0, RECIPIENT, sendValue, data);

        vm.prank(OWNER_1);
        multisig.submitTransaction{value: sendValue}(RECIPIENT, data);

        MultiSig.Transaction memory transaction = multisig.getTransaction(0);
        assertEq(transaction.value, sendValue);
        assertEq(transaction.to, RECIPIENT);
        assertEq(transaction.sender, OWNER_1);
    }

    // ============ Confirmation Tests ============

    function test_confirmTransactionRevertsIfTransactionDoesNotExist() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__TransactionDoesNotExist.selector, 0, 0));
        vm.prank(OWNER_1);
        multisig.confirmTransaction(0);
    }

    function test_confirmTransactionRevertsIfAlreadyExecuted() public {
        _submitAndExecuteTransaction();

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__TransactionAlreadyExecuted.selector, 0));
        vm.prank(OWNER_1);
        multisig.confirmTransaction(0);
    }

    function test_confirmTransactionRevertsIfAlreadyCancelled() public {
        _submitContractOneCountTransaction(10);
        _cancelTransaction(0);

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__TransactionAlreadyCancelled.selector, 0));
        vm.prank(OWNER_1);
        multisig.confirmTransaction(0);
    }

    // ============ Revoke Confirmation Tests ============

    function test_revokeConfirmationSuccessfully() public {
        _submitContractOneCountTransaction(10);

        // Confirm transaction
        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);

        assertTrue(multisig.hasConfirmed(0, OWNER_2));
        assertEq(multisig.getTransaction(0).confirmations, 1);

        // Revoke confirmation
        vm.expectEmit(true, true, true, true, address(multisig));
        emit IMultiSig.ConfirmationRevoked(OWNER_2, 0, 0);

        vm.prank(OWNER_2);
        multisig.revokeConfirmation(0);

        assertFalse(multisig.hasConfirmed(0, OWNER_2));
        assertEq(multisig.getTransaction(0).confirmations, 0);
    }

    function test_revokeConfirmationRevertsIfNotConfirmed() public {
        _submitContractOneCountTransaction(10);

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__ConfirmationDoesNotExist.selector, 0, OWNER_2));
        vm.prank(OWNER_2);
        multisig.revokeConfirmation(0);
    }

    function test_revokeConfirmationRevertsIfTransactionExecuted() public {
        _submitAndExecuteTransaction();

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__TransactionAlreadyExecuted.selector, 0));
        vm.prank(OWNER_2);
        multisig.revokeConfirmation(0);
    }

    // ============ Manual Execute Transaction Tests ============

    function test_executeTransactionManually() public {
        _submitContractOneCountTransaction(15);

        // Get enough confirmations but don't auto-execute
        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);
        vm.prank(OWNER_3);
        multisig.confirmTransaction(0);

        assertEq(contractOne.count(), 15); // Should already be executed
        assertTrue(multisig.getTransaction(0).executed);
    }

    function test_executeTransactionRevertsIfInsufficientConfirmations() public {
        _submitContractOneCountTransaction(15);

        vm.prank(OWNER_2);
        multisig.confirmTransaction(0); // Only 1 confirmation, need 2

        vm.expectRevert(
            abi.encodeWithSelector(
                IMultiSig.MultiSig__InvalidTransactionOperation.selector, 0, "Insufficient confirmations"
            )
        );
        vm.prank(OWNER_1);
        multisig.executeTransaction(0);
    }

    // ============ Cancellation Tests ============

    function test_requestCancellationSuccessfully() public {
        _submitContractOneCountTransaction(10);

        vm.expectEmit(true, true, true, true, address(multisig));
        emit IMultiSig.CancellationRequested(OWNER_2, 0, 1);

        vm.prank(OWNER_2);
        multisig.requestCancellation(0);

        assertTrue(multisig.hasRequestedCancellation(0, OWNER_2));
        assertEq(multisig.getTransaction(0).cancellations, 1);
    }

    function test_requestCancellationAutoCancelsWithSufficientRequests() public {
        _submitContractOneCountTransaction(10);

        vm.prank(OWNER_2);
        multisig.requestCancellation(0);

        vm.expectEmit(true, true, false, true, address(multisig));
        emit IMultiSig.TransactionCancelled(0, 2);

        vm.prank(OWNER_3);
        multisig.requestCancellation(0);

        assertTrue(multisig.getTransaction(0).cancelled);
    }

    function test_requestCancellationRevertsIfAlreadyExecuted() public {
        _submitAndExecuteTransaction();

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__TransactionAlreadyExecuted.selector, 0));
        vm.prank(OWNER_2);
        multisig.requestCancellation(0);
    }

    function test_requestCancellationRevertsIfAlreadyRequested() public {
        _submitContractOneCountTransaction(10);

        vm.prank(OWNER_2);
        multisig.requestCancellation(0);

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__CancellationAlreadyRequested.selector, 0, OWNER_2));
        vm.prank(OWNER_2);
        multisig.requestCancellation(0);
    }

    // ============ Revoke Cancellation Request Tests ============

    function test_revokeCancellationRequestSuccessfully() public {
        _submitContractOneCountTransaction(10);

        vm.prank(OWNER_2);
        multisig.requestCancellation(0);

        vm.expectEmit(true, true, true, true, address(multisig));
        emit IMultiSig.CancellationRequestRevoked(OWNER_2, 0, 0);

        vm.prank(OWNER_2);
        multisig.revokeCancellationRequest(0);

        assertFalse(multisig.hasRequestedCancellation(0, OWNER_2));
        assertEq(multisig.getTransaction(0).cancellations, 0);
    }

    function test_revokeCancellationRequestRevertsIfNotRequested() public {
        _submitContractOneCountTransaction(10);

        vm.expectRevert(
            abi.encodeWithSelector(IMultiSig.MultiSig__CancellationRequestDoesNotExist.selector, 0, OWNER_2)
        );
        vm.prank(OWNER_2);
        multisig.revokeCancellationRequest(0);
    }

    // ============ Add Owner Tests ============

    function test_addNewOwnerInitiatesTransaction() public {
        address newOwner = makeAddr("NEW_OWNER");
        uint256 newMinConfirmations = 3;

        vm.expectEmit(true, true, true, false, address(multisig));
        emit IMultiSig.TransactionSubmitted(
            OWNER_1,
            0,
            address(multisig),
            0,
            abi.encodeWithSignature("executeAddOwner(address,uint256)", newOwner, newMinConfirmations)
        );

        vm.prank(OWNER_1);
        multisig.addNewOwner(newOwner, newMinConfirmations);

        assertEq(multisig.getTransactionCount(), 1);
    }

    function test_addNewOwnerRevertsWithZeroAddress() public {
        vm.expectRevert(IMultiSig.MultiSig__ZeroAddressNotAllowed.selector);
        vm.prank(OWNER_1);
        multisig.addNewOwner(address(0), 2);
    }

    function test_addNewOwnerRevertsIfAlreadyOwner() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__AddressAlreadyOwner.selector, OWNER_2));
        vm.prank(OWNER_1);
        multisig.addNewOwner(OWNER_2, 2);
    }

    function test_addNewOwnerRevertsWithZeroMinConfirmations() public {
        address newOwner = makeAddr("NEW_OWNER");

        vm.expectRevert(IMultiSig.MultiSig__MinConfirmationsMustBeAtLeastOne.selector);
        vm.prank(OWNER_1);
        multisig.addNewOwner(newOwner, 0);
    }

    function test_executeAddOwnerSuccessfully() public {
        address newOwner = makeAddr("NEW_OWNER");
        uint256 newMinConfirmations = 3;

        // Submit add owner transaction
        vm.prank(OWNER_1);
        multisig.addNewOwner(newOwner, newMinConfirmations);

        // Confirm the transaction
        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);

        vm.expectEmit(true, false, false, true, address(multisig));
        emit IMultiSig.OwnerAdded(newOwner, newMinConfirmations, 4);

        vm.prank(OWNER_3);
        multisig.confirmTransaction(0);

        assertEq(multisig.getOwnersCount(), 4);
        assertEq(multisig.getMinConfirmations(), newMinConfirmations);

        address[] memory owners = multisig.getOwners();
        assertEq(owners[3], newOwner);
    }

    function test_executeAddOwnerRevertsIfNotCalledByContract() public {
        address newOwner = makeAddr("NEW_OWNER");

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__OnlyCallableByContract.selector, OWNER_1));
        vm.prank(OWNER_1);
        multisig.executeAddOwner(newOwner, 2);
    }

    // ============ ETH Transfer Tests ============

    function test_transferEtherSuccessfully() public {
        uint256 transferAmount = 10 ether;
        uint256 initialBalance = RECIPIENT.balance;

        // Submit ETH transfer transaction
        vm.prank(OWNER_1);
        multisig.submitTransaction{value: transferAmount}(RECIPIENT, "");

        // Confirm and execute
        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);
        vm.prank(OWNER_3);
        multisig.confirmTransaction(0);

        assertEq(RECIPIENT.balance, initialBalance + transferAmount);
    }

    function test_payableContractFunctionCall() public {
        uint256 sendValue = 2 ether;
        uint256 multiplier = 5;

        // Set initial count
        vm.prank(address(multisig));
        contractOne.increaseCount(10);

        bytes memory data = abi.encodeWithSignature("multiplyCount(uint256)", multiplier);

        vm.prank(OWNER_1);
        multisig.submitTransaction{value: sendValue}(address(contractOne), data);

        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);
        vm.prank(OWNER_3);
        multisig.confirmTransaction(0);

        assertEq(contractOne.count(), 50); // 10 * 5
    }

    // ============ Transaction Execution Failure Tests ============

    // function test_transactionExecutionFailsWithInvalidCall() public {
    //     // Submit transaction with invalid function signature
    //     bytes memory invalidData = abi.encodeWithSignature("nonExistentFunction()");

    //     vm.prank(OWNER_1);
    //     multisig.submitTransaction(address(contractOne), invalidData);

    //     vm.prank(OWNER_2);
    //     multisig.confirmTransaction(0);

    //     // This should fail during execution
    //     // vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__TransactionExecutionFailed.selector, 0, address(contractOne)));
    //     vm.prank(OWNER_3);
    //     multisig.confirmTransaction(0);
    // }

    // ============ Receive and Fallback Tests ============

    function test_contractReceivesEtherDirectly() public {
        uint256 sendAmount = 5 ether;
        uint256 initialBalance = address(multisig).balance;

        vm.prank(OWNER_1);
        (bool success,) = address(multisig).call{value: sendAmount}("");

        assertTrue(success);
        assertEq(address(multisig).balance, initialBalance + sendAmount);
    }

    function test_contractFallbackFunction() public {
        uint256 sendAmount = 3 ether;
        uint256 initialBalance = address(multisig).balance;

        vm.prank(OWNER_1);
        (bool success,) = address(multisig).call{value: sendAmount}("randomData");

        assertTrue(success);
        assertEq(address(multisig).balance, initialBalance + sendAmount);
    }

    // ============ View Function Tests ============

    function test_getTransactionCount() public {
        assertEq(multisig.getTransactionCount(), 0);

        _submitContractOneCountTransaction(5);
        assertEq(multisig.getTransactionCount(), 1);

        _submitContractOneCountTransaction(10);
        assertEq(multisig.getTransactionCount(), 2);
    }

    function test_getMinConfirmations() public {
        assertEq(multisig.getMinConfirmations(), 2);
    }

    function test_getOwners() public {
        address[] memory owners = multisig.getOwners();
        assertEq(owners.length, 3);
        assertEq(owners[0], OWNER_1);
        assertEq(owners[1], OWNER_2);
        assertEq(owners[2], OWNER_3);
    }

    function test_hasConfirmed() public {
        _submitContractOneCountTransaction(5);

        assertFalse(multisig.hasConfirmed(0, OWNER_2));

        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);

        assertTrue(multisig.hasConfirmed(0, OWNER_2));
    }

    function test_hasRequestedCancellation() public {
        _submitContractOneCountTransaction(5);

        assertFalse(multisig.hasRequestedCancellation(0, OWNER_2));

        vm.prank(OWNER_2);
        multisig.requestCancellation(0);

        assertTrue(multisig.hasRequestedCancellation(0, OWNER_2));
    }

    // ============ Edge Case Tests ============

    function test_multipleTransactionsIndependentConfirmations() public {
        // Submit two transactions
        _submitContractOneCountTransaction(5);
        vm.prank(OWNER_2);
        multisig.submitTransaction(address(contractTwo), abi.encodeWithSignature("changeName(string)", "Test"));

        // Confirm first transaction with OWNER_2 and OWNER_3
        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);
        vm.prank(OWNER_3);
        multisig.confirmTransaction(0);

        // Confirm second transaction with OWNER_1 and OWNER_3
        vm.prank(OWNER_1);
        multisig.confirmTransaction(1);
        vm.prank(OWNER_3);
        multisig.confirmTransaction(1);

        // Verify both transactions executed independently
        assertEq(contractOne.count(), 5);
        assertEq(contractTwo.name(), "Test");
    }

    function test_cancelAfterPartialConfirmations() public {
        _submitContractOneCountTransaction(10);

        // Partial confirmation
        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);

        // Cancel the transaction
        vm.prank(OWNER_2);
        multisig.requestCancellation(0);
        vm.prank(OWNER_3);
        multisig.requestCancellation(0);

        // Try to confirm after cancellation should fail
        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__TransactionAlreadyCancelled.selector, 0));
        vm.prank(OWNER_1);
        multisig.confirmTransaction(0);
    }

    // ============ Helper Functions ============

    function _submitContractOneCountTransaction(uint256 _count) private {
        address to = address(contractOne);
        bytes memory data = abi.encodeWithSignature("increaseCount(uint256)", _count);

        vm.prank(OWNER_1);
        multisig.submitTransaction(to, data);
    }

    function _submitAndExecuteTransaction() private {
        _submitContractOneCountTransaction(25);

        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);
        vm.prank(OWNER_3);
        multisig.confirmTransaction(0);
    }

    function _cancelTransaction(uint256 _id) private {
        vm.prank(OWNER_2);
        multisig.requestCancellation(_id);
        vm.prank(OWNER_3);
        multisig.requestCancellation(_id);
    }
}
