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
    }

    function test_getTotalOwners() public view {
        uint256 totalOwners = multisig.getOwnersCount();

        assertEq(totalOwners, 3);
    }

    function test_onlyOnwersCanSubmitATransaction() public {
        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__NotAnOwner.selector, UNKNOWN));
        vm.prank(UNKNOWN);
        multisig.submitTransaction(address(contractOne), bytes(""));
    }

    function test_ownersCanSubmitATransaction() public {
        assertEq(multisig.getTransactionCount(), 0);

        address to = address(contractOne);
        bytes memory data = abi.encodeWithSignature("increaseCount(uint256)", 4);
        vm.expectEmit(true, true, true, true, address(multisig));
        emit IMultiSig.TransactionSubmitted(OWNER_1, 0, to, 0, data);
        vm.prank(OWNER_1);
        multisig.submitTransaction(to, data);

        assertEq(multisig.getTransactionCount(), 1);
    }

    function test_onlyOwnersCanConfirmTransaction() public {
        _submitContractOneCountTransaction(10);

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__NotAnOwner.selector, UNKNOWN));
        vm.prank(UNKNOWN);
        multisig.confirmTransaction(0);

        MultiSig.Transaction memory transaction = multisig.getTransaction(0);

        assertEq(transaction.confirmations, 0);

        vm.expectEmit(true, true, true, true, address(multisig));
        emit IMultiSig.TransactionConfirmed(OWNER_2, 0, 1);
        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);

        transaction = multisig.getTransaction(0);

        assertEq(transaction.confirmations, 1);
    }

    function test_ownersCannotConfirmMoreThanOnce() public {
        _submitContractOneCountTransaction(10);

        vm.startPrank(OWNER_2);
        multisig.confirmTransaction(0);

        vm.expectRevert(abi.encodeWithSelector(IMultiSig.MultiSig__TransactionAlreadyConfirmed.selector, 0, OWNER_2));
        multisig.confirmTransaction(0);
    }

    function test_executeTransactionAfterMinConfirmationIsComplete() public {
        assertEq(contractOne.count(), 0);

        uint256 newCount = 10;

        _submitContractOneCountTransaction(newCount);

        MultiSig.Transaction memory transaction = multisig.getTransaction(0);

        vm.expectEmit(true, true, true, true, address(multisig));
        emit IMultiSig.TransactionConfirmed(OWNER_2, 0, 1);
        vm.prank(OWNER_2);
        multisig.confirmTransaction(0);

        vm.expectEmit(true, true, true, true, address(multisig));
        emit IMultiSig.TransactionConfirmed(OWNER_3, 0, 2);
        vm.expectEmit(true, true, true, true, address(multisig));
        emit IMultiSig.TransactionExecuted(OWNER_1, 0, address(contractOne), 0);

        vm.prank(OWNER_3);
        multisig.confirmTransaction(0);

        // verifiy contract one increase count
        assertEq(contractOne.count(), newCount);
    }

    function _submitContractOneCountTransaction(uint256 _count) private {
        address to = address(contractOne);
        bytes memory data = abi.encodeWithSignature("increaseCount(uint256)", _count);

        vm.expectEmit(true, true, true, false, address(multisig));
        emit IMultiSig.TransactionSubmitted(OWNER_1, 0, to, 0, data);

        vm.prank(OWNER_1);
        multisig.submitTransaction(to, data);
    }
}
