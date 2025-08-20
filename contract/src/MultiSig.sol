// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

error NotOwner();
error InvalidTransaction(string reason);
error TransactionAlreadyCancelled();
error TransactionNotConfirmedYet();
error AddressZeroNotAllowed();
error DuplicateOwner();
error MinimumOfOneConfirmations();
error MinConfirmationsGreaterThanOwners();
error CanOnlyBeCalledByContract();

event TransactionExecuted(address indexed sender, uint256 indexed id, address to);
event TransactionSubmitted(address indexed sender, uint256 indexed id, address to);
event TransactionConfirmed(address indexed sender, uint256 indexed id);
event TransactionRevoked(address indexed revoker, uint256 indexed id);
event TransactionRevocationCancelled(address indexed revoker, uint256 indexed id);
event TransactionCancelled(uint256 indexed id);
event NewOwnerAdded(address newOwner, uint256 newMinConfirmations);

contract MultiSig {
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

  mapping (address owner => bool) private isOwners;
  address[] private owners;
  Transaction[] private transactions;
  uint256 minConfirmations;
  mapping (uint256 transactionId => mapping (address owner => bool confirmed)) private transactionConfirmations;
  mapping (uint256 transactionId => mapping (address owner => bool cancelled)) private transactionCancellations;

  constructor (address[] memory _owners, uint256 _minConfirmations) {
    if (_minConfirmations == 0) revert MinimumOfOneConfirmations();
    if (_minConfirmations > _owners.length) revert MinConfirmationsGreaterThanOwners();

    uint256 ownerIndex = 0;
    uint256 totalOnwers = _owners.length;
    for (ownerIndex; ownerIndex < totalOnwers;) {
      if (_owners[ownerIndex] == address(0)) revert AddressZeroNotAllowed();
      if (isOwners[_owners[ownerIndex]]) revert DuplicateOwner();

      owners.push(_owners[ownerIndex]);
      isOwners[_owners[ownerIndex]] = true;

      unchecked {
        ownerIndex++;
      }
    }

    minConfirmations = _minConfirmations;
  }

  modifier onlyOwners() {
    if (!isOwners[msg.sender]) revert NotOwner();

    _;
  }

  modifier transactionExist (uint256 id) {
    if (id >= transactions.length) {
      revert InvalidTransaction("Transaction does not exist.");
    } else {
      _;
    }
  }

  function submitTransaction(address _to, bytes memory _data) public payable onlyOwners returns (uint256 transactionId) {
    if (_to == address(0)) revert InvalidTransaction("Zero address not allowed");
    transactionId = transactions.length;

    Transaction storage transaction = transactions.push();

    transaction.id = transactionId;
    transaction.value = msg.value;
    transaction.executed = false;
    transaction.confirmations = 0;
    transaction.sender = msg.sender;
    transaction.to = _to;
    transaction.timestamp = block.timestamp;
    transaction.data = _data;

    emit TransactionSubmitted(msg.sender, transactionId, _to);
  }

  function confirmTransaction(uint256 _id) external onlyOwners() transactionExist(_id) {
    if (transactionConfirmations[_id][msg.sender]) {
      revert InvalidTransaction("Transaction has been confirmed");
    }

    if (transactions[_id].executed) {
      revert InvalidTransaction("Transaction has been executed");
    }

    if (transactions[_id].cancelled) {
      revert InvalidTransaction("Transaction has been cancelled");
    }

    transactionConfirmations[_id][msg.sender] = true;
    transactions[_id].confirmations += 1;

    emit TransactionConfirmed(msg.sender, _id);

    if (!transactions[_id].executed && transactions[_id].confirmations >= minConfirmations) {
      _executeTransaction(transactions[_id], _id);
    }
  }

  function revokeConfirmation(uint256 _id) external onlyOwners transactionExist(_id) {
    if (!transactionConfirmations[_id][msg.sender]) {
      revert InvalidTransaction("Transaction has not been confirmed");
    }

    Transaction storage transaction = transactions[_id];

    if (transaction.executed) {
      revert InvalidTransaction("Transaction has been executed");
    }

    if (transactions[_id].cancelled) {
      revert InvalidTransaction("Transaction has been cancelled");
    }

    transaction.confirmations -= 1;
    transactionConfirmations[_id][msg.sender] = false;

    emit TransactionRevoked(msg.sender, _id);
  }

  function executeTransaction(uint256 _transactionId) external transactionExist(_transactionId) onlyOwners {
    _executeTransaction(transactions[_transactionId], _transactionId);
  }

  function requestCancellation (uint256 _id) external onlyOwners {
    Transaction storage transaction = transactions[_id];

    if (transaction.executed) revert InvalidTransaction("Transaction has been executed");

    if (transactionCancellations[_id][msg.sender]) revert TransactionAlreadyCancelled();

    transactionCancellations[_id][msg.sender] = true;
    transaction.cancellations += 1;

    if (transaction.cancellations >= minConfirmations) {
      _cancelTransaction(_id);
    }
  }

  function revokeCancellation (uint256 _id) external onlyOwners {
    Transaction storage transaction = transactions[_id];

    if (!transactionCancellations[_id][msg.sender]) revert TransactionNotConfirmedYet();

    if (transaction.executed) revert InvalidTransaction("Transaction has been executed");

    if (transaction.cancelled) revert InvalidTransaction("Transaction has been cancelled");

    transactions[_id].cancellations -= 1;
    transactionCancellations[_id][msg.sender] = false;

    emit TransactionRevocationCancelled(msg.sender, _id);
  }

  function addNewOwner (address _owner, uint256 _minConfirmations) external {
    if (_owner == address(0)) revert AddressZeroNotAllowed();
    if (isOwners[_owner]) revert DuplicateOwner();

    if (_minConfirmations == 0) revert MinimumOfOneConfirmations();

    submitTransaction(address(this), abi.encodeWithSignature("executeAddOwner(address,uint256)", _owner, _minConfirmations));
  }

  function executeAddOwner (address _owner, uint256 _minConfirmations) external {
    if (msg.sender != address(this)) revert CanOnlyBeCalledByContract();

    if (_owner == address(0)) revert AddressZeroNotAllowed();
    if (isOwners[_owner]) revert DuplicateOwner();

    if (_minConfirmations == 0) revert MinimumOfOneConfirmations();

    address[] memory _owners = owners;
    if (_minConfirmations > _owners.length + 1) revert MinConfirmationsGreaterThanOwners();

    isOwners[_owner] = true;
    owners.push(_owner);
    minConfirmations = _minConfirmations;

    emit NewOwnerAdded(_owner, _minConfirmations);
  }

  function getOwnersCount() external view returns (uint256) {
    return owners.length;
  }

  function _executeTransaction(Transaction storage transaction, uint256 transactionId) private {
    if (transaction.cancelled) revert InvalidTransaction("Transaction has been cancelled");
    if (transaction.executed) revert InvalidTransaction("Transaction has been executed");
    if (transaction.confirmations < minConfirmations) revert InvalidTransaction("Minimum confirmation not met");

    transaction.executed = true;

    (bool success, ) = transaction.to.call{value: transaction.value}(transaction.data);

    if (!success) revert();

    emit TransactionExecuted(transaction.sender, transactionId, transaction.to);
  }

  function _cancelTransaction(uint256 _id) internal {
    transactions[_id].cancelled = true;

    emit TransactionCancelled(_id);
  }

  receive() external payable {}

  fallback() external payable {}
}
