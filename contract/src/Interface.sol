// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

interface IMultiSig {
  struct Transaction {
    uint256 id;
    uint256 value;
    uint256 confirmations;
    uint256 cancellations;
    uint256 timestamp;
    bool executed;
    bool cancelled;
    address sender;
    address to;
    bytes data;
  }

  event TransactionExecuted(address indexed sender, uint256 indexed id, address to);
  event TransactionSubmitted(address indexed sender, uint256 indexed id, address to);
  event TransactionConfirmed(address indexed sender, uint256 indexed id);
  event TransactionRevoked(address indexed revoker, uint256 indexed id);
  event TransactionRevocationCancelled(address indexed revoker, uint256 indexed id);
  event TransactionCancelled(uint256 indexed id);
  event NewOwnerAdded(address newOwner, uint256 newMinConfirmations);

  error MultiSig__NotOwner();
  error MultiSig__InvalidTransaction(string reason);
  error MultiSig__TransactionAlreadyCancelled();
  error MultiSig__TransactionNotConfirmedYet();
  error MultiSig__AddressZeroNotAllowed();
  error MultiSig__DuplicateOwner();
  error MultiSig__MinimumOfOneConfirmations();
  error MultiSig__MinConfirmationsGreaterThanOwners();
  error MultiSig__CanOnlyBeCalledByContract();
  error MultiSig__ExecutionFailed();
}
