// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import {IMultiSig} from "./Interface.sol";

/**
 * @title MultiSig
 * @notice A multi-signature wallet contract that requires multiple owner confirmations for transaction execution
 * @dev Implements multi-signature functionality with configurable confirmation requirements and cancellation mechanisms
 * @author Blessing Olaleye
 */
contract MultiSig is IMultiSig {
    // State variables

    /// @dev Mapping to track if an address is an owner
    mapping(address owner => bool) private isOwners;

    /// @dev Array of all owner addresses
    address[] private owners;

    /// @dev Array of all submitted transactions
    Transaction[] private transactions;

    /// @dev Minimum number of confirmations required to execute a transaction
    uint256 private minConfirmations;

    /// @dev Mapping to track transaction confirmations by owners
    mapping(uint256 transactionId => mapping(address owner => bool confirmed)) private transactionConfirmations;

    /// @dev Mapping to track transaction cancellation requests by owners
    mapping(uint256 transactionId => mapping(address owner => bool cancelled)) private transactionCancellations;

    /**
     * @notice Initializes the multi-sig wallet with specified owners and confirmation requirement
     * @dev Sets up the initial owners and validates the minimum confirmations requirement
     * @param _owners Array of addresses that will be owners of the multi-sig wallet
     * @param _minConfirmations Minimum number of confirmations required to execute transactions
     * @custom:requirements
     * - `_minConfirmations` must be at least 1
     * - `_minConfirmations` must not exceed the number of owners
     * - No owner can be the zero address
     * - No duplicate owners allowed
     */
    constructor(address[] memory _owners, uint256 _minConfirmations) {
        if (_minConfirmations == 0) revert MultiSig__MinConfirmationsMustBeAtLeastOne();
        if (_minConfirmations > _owners.length) {
            revert MultiSig__MinConfirmationsExceedsOwnerCount(_minConfirmations, _owners.length);
        }

        uint256 ownerIndex = 0;
        uint256 totalOwners = _owners.length;
        for (ownerIndex; ownerIndex < totalOwners;) {
            if (_owners[ownerIndex] == address(0)) revert MultiSig__ZeroAddressNotAllowed();
            if (isOwners[_owners[ownerIndex]]) {
                revert MultiSig__AddressAlreadyOwner(_owners[ownerIndex]);
            }

            owners.push(_owners[ownerIndex]);
            isOwners[_owners[ownerIndex]] = true;

            unchecked {
                ownerIndex++;
            }
        }

        minConfirmations = _minConfirmations;
    }

    /**
     * @notice Restricts function access to wallet owners only
     * @dev Reverts with NotAnOwner if caller is not an owner
     */
    modifier onlyOwners() {
        if (!isOwners[msg.sender]) revert MultiSig__NotAnOwner(msg.sender);
        _;
    }

    /**
     * @notice Restricts function access to this contract only
     * @dev Reverts with MultiSig__OnlyCallableByContract if caller is not this contract
     */
    modifier onlyCallableByContract() {
        if (msg.sender != address(this)) revert MultiSig__OnlyCallableByContract(msg.sender);

        _;
    }

    /**
     * @notice Validates that a transaction exists
     * @dev Reverts with TransactionDoesNotExist if transaction ID is invalid
     * @param id Transaction ID to validate
     */
    modifier transactionExists(uint256 id) {
        if (id >= transactions.length) {
            revert MultiSig__TransactionDoesNotExist(id, transactions.length > 0 ? transactions.length - 1 : 0);
        }
        _;
    }

    /**
     * @notice Submits a new transaction to the multi-sig wallet
     * @dev Creates a new transaction and stores it in the transactions array
     * @param _to Target address for the transaction
     * @param _data Encoded function call data to execute
     * @return transactionId The unique identifier assigned to the submitted transaction
     * @custom:requirements
     * - Caller must be an owner
     * - Target address cannot be zero address
     * - Emits TransactionSubmitted event
     */
    function submitTransaction(address _to, bytes memory _data)
        public
        payable
        onlyOwners
        returns (uint256 transactionId)
    {
        if (_to == address(0)) revert MultiSig__ZeroAddressNotAllowed();
        transactionId = transactions.length;

        Transaction storage transaction = transactions.push();

        transaction.id = transactionId;
        transaction.value = msg.value;
        transaction.executed = false;
        transaction.cancelled = false;
        transaction.confirmations = 0;
        transaction.cancellations = 0;
        transaction.sender = msg.sender;
        transaction.to = _to;
        transaction.timestamp = block.timestamp;
        transaction.data = _data;

        emit TransactionSubmitted(msg.sender, transactionId, _to, msg.value, _data);
    }

    /**
     * @notice Confirms a pending transaction
     * @dev Adds the caller's confirmation to the specified transaction and executes if threshold is met
     * @param _id Transaction ID to confirm
     * @custom:requirements
     * - Caller must be an owner
     * - Transaction must exist
     * - Transaction must not already be confirmed by caller
     * - Transaction must not be executed or cancelled
     * - Automatically executes transaction if confirmation threshold is reached
     */
    function confirmTransaction(uint256 _id) external onlyOwners transactionExists(_id) {
        if (transactionConfirmations[_id][msg.sender]) {
            revert MultiSig__TransactionAlreadyConfirmed(_id, msg.sender);
        }

        if (transactions[_id].executed) {
            revert MultiSig__TransactionAlreadyExecuted(_id);
        }

        if (transactions[_id].cancelled) {
            revert MultiSig__TransactionAlreadyCancelled(_id);
        }

        transactionConfirmations[_id][msg.sender] = true;
        transactions[_id].confirmations += 1;

        emit TransactionConfirmed(msg.sender, _id, transactions[_id].confirmations);

        if (!transactions[_id].executed && transactions[_id].confirmations >= minConfirmations) {
            _executeTransaction(transactions[_id], _id);
        }
    }

    /**
     * @notice Revokes a previously given confirmation
     * @dev Removes the caller's confirmation from the specified transaction
     * @param _id Transaction ID to revoke confirmation for
     * @custom:requirements
     * - Caller must be an owner
     * - Transaction must exist
     * - Caller must have previously confirmed the transaction
     * - Transaction must not be executed or cancelled
     */
    function revokeConfirmation(uint256 _id) external onlyOwners transactionExists(_id) {
        if (!transactionConfirmations[_id][msg.sender]) {
            revert MultiSig__ConfirmationDoesNotExist(_id, msg.sender);
        }

        Transaction storage transaction = transactions[_id];

        if (transaction.executed) {
            revert MultiSig__TransactionAlreadyExecuted(_id);
        }

        if (transaction.cancelled) {
            revert MultiSig__TransactionAlreadyCancelled(_id);
        }

        transaction.confirmations -= 1;
        transactionConfirmations[_id][msg.sender] = false;

        emit ConfirmationRevoked(msg.sender, _id, transaction.confirmations);
    }

    /**
     * @notice Manually executes a transaction that has sufficient confirmations
     * @dev Executes the specified transaction if all requirements are met
     * @param _transactionId Transaction ID to execute
     * @custom:requirements
     * - Caller must be an owner
     * - Transaction must exist
     * - Transaction must have sufficient confirmations
     * - Transaction must not be executed or cancelled
     */
    function executeTransaction(uint256 _transactionId) external transactionExists(_transactionId) onlyOwners {
        _executeTransaction(transactions[_transactionId], _transactionId);
    }

    /**
     * @notice Requests cancellation of a pending transaction
     * @dev Adds the caller's cancellation request and cancels transaction if threshold is met
     * @param _id Transaction ID to request cancellation for
     * @custom:requirements
     * - Caller must be an owner
     * - Transaction must not be executed
     * - Caller must not have already requested cancellation
     * - Automatically cancels transaction if cancellation threshold is reached
     */
    function requestCancellation(uint256 _id) external onlyOwners transactionExists(_id) {
        Transaction storage transaction = transactions[_id];

        if (transaction.executed) revert MultiSig__TransactionAlreadyExecuted(_id);

        if (transactionCancellations[_id][msg.sender]) {
            revert MultiSig__CancellationAlreadyRequested(_id, msg.sender);
        }

        transactionCancellations[_id][msg.sender] = true;
        transaction.cancellations += 1;

        emit CancellationRequested(msg.sender, _id, transaction.cancellations);

        if (transaction.cancellations >= minConfirmations) {
            _cancelTransaction(_id);
        }
    }

    /**
     * @notice Revokes a previously made cancellation request
     * @dev Removes the caller's cancellation request from the specified transaction
     * @param _id Transaction ID to revoke cancellation request for
     * @custom:requirements
     * - Caller must be an owner
     * - Transaction must exist
     * - Caller must have previously requested cancellation
     * - Transaction must not be executed or cancelled
     */
    function revokeCancellationRequest(uint256 _id) external onlyOwners transactionExists(_id) {
        Transaction storage transaction = transactions[_id];

        if (!transactionCancellations[_id][msg.sender]) {
            revert MultiSig__CancellationRequestDoesNotExist(_id, msg.sender);
        }

        if (transaction.executed) revert MultiSig__TransactionAlreadyExecuted(_id);

        if (transaction.cancelled) revert MultiSig__TransactionAlreadyCancelled(_id);

        transaction.cancellations -= 1;
        transactionCancellations[_id][msg.sender] = false;

        emit CancellationRequestRevoked(msg.sender, _id, transaction.cancellations);
    }

    function updateMinConfirmations(uint256 _confirmations) external onlyOwners {
        if (_confirmations == 0) revert MultiSig__MinConfirmationsMustBeAtLeastOne();

        uint256 totalOwners = owners.length;
        if (_confirmations > totalOwners) revert MultiSig__MinConfirmationsExceedsOwnerCount(_confirmations, totalOwners);

        submitTransaction(address(this), abi.encodeWithSignature("executeUpdateMinConfirmations(uint256)", _confirmations));
    }

    function executeUpdateMinConfirmations(uint256 _confirmations) external onlyCallableByContract {
        if (_confirmations == 0) revert MultiSig__MinConfirmationsMustBeAtLeastOne();
        
        uint256 totalOwners = owners.length;
        if (_confirmations > totalOwners) revert MultiSig__MinConfirmationsExceedsOwnerCount(_confirmations, totalOwners);

        uint256 oldMinConfirmations = minConfirmations;
        minConfirmations = _confirmations;

        emit MinConfirmationsUpdated(oldMinConfirmations, _confirmations);
    }

    /**
     * @notice Initiates the process to add a new owner
     * @dev Submits a transaction to call executeAddOwner with the new owner details
     * @param _owner Address of the new owner to add
     * @param _minConfirmations New minimum confirmations requirement
     * @custom:requirements
     * - New owner cannot be zero address
     * - New owner cannot already be an owner
     * - New minimum confirmations must be at least 1
     * - Requires multi-sig approval through transaction confirmation process
     */
    function addNewOwner(address _owner, uint256 _minConfirmations) external onlyOwners {
        if (_owner == address(0)) revert MultiSig__ZeroAddressNotAllowed();
        if (isOwners[_owner]) revert MultiSig__AddressAlreadyOwner(_owner);
        if (_minConfirmations == 0) revert MultiSig__MinConfirmationsMustBeAtLeastOne();

        submitTransaction(
            address(this), abi.encodeWithSignature("executeAddOwner(address,uint256)", _owner, _minConfirmations)
        );
    }

    /**
     * @notice Executes the addition of a new owner (internal multi-sig function)
     * @dev Can only be called by the contract itself through the multi-sig process
     * @param _owner Address of the new owner to add
     * @param _minConfirmations New minimum confirmations requirement
     * @custom:requirements
     * - Can only be called by the contract itself
     * - New owner cannot be zero address
     * - New owner cannot already be an owner
     * - New minimum confirmations must be at least 1
     * - New minimum confirmations must not exceed total owners after addition
     */
    function executeAddOwner(address _owner, uint256 _minConfirmations) external onlyCallableByContract {
        if (_owner == address(0)) revert MultiSig__ZeroAddressNotAllowed();
        if (isOwners[_owner]) revert MultiSig__AddressAlreadyOwner(_owner);
        if (_minConfirmations == 0) revert MultiSig__MinConfirmationsMustBeAtLeastOne();

        uint256 newOwnerCount = owners.length + 1;
        if (_minConfirmations > newOwnerCount) {
            revert MultiSig__MinConfirmationsExceedsOwnerCount(_minConfirmations, newOwnerCount);
        }

        isOwners[_owner] = true;
        owners.push(_owner);
        minConfirmations = _minConfirmations;

        emit OwnerAdded(_owner, _minConfirmations, newOwnerCount);
    }

    /**
     * @notice Returns the total number of owners
     * @dev Public view function to get the current owner count
     * @return The number of owners in the multi-sig wallet
     */
    function getOwnersCount() external view returns (uint256) {
        return owners.length;
    }

    /**
     * @notice Returns the current minimum confirmations requirement
     * @dev Public view function to get the minimum confirmations needed
     * @return The minimum number of confirmations required for transaction execution
     */
    function getMinConfirmations() external view returns (uint256) {
        return minConfirmations;
    }

    /**
     * @notice Returns the list of all owners
     * @dev Public view function to get all owner addresses
     * @return Array of all owner addresses
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @notice Returns details of a specific transaction
     * @dev Public view function to get transaction information
     * @param _transactionId ID of the transaction to query
     * @return Transaction struct containing all transaction details
     */
    function getTransaction(uint256 _transactionId)
        external
        view
        transactionExists(_transactionId)
        returns (Transaction memory)
    {
        return transactions[_transactionId];
    }

    /**
     * @notice Returns the total number of submitted transactions
     * @dev Public view function to get the transaction count
     * @return The total number of transactions ever submitted
     */
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @notice Checks if an owner has confirmed a specific transaction
     * @dev Public view function to check confirmation status
     * @param _transactionId Transaction ID to check
     * @param _owner Owner address to check
     * @return True if the owner has confirmed the transaction, false otherwise
     */
    function hasConfirmed(uint256 _transactionId, address _owner)
        external
        view
        transactionExists(_transactionId)
        returns (bool)
    {
        return transactionConfirmations[_transactionId][_owner];
    }

    /**
     * @notice Checks if an owner has requested cancellation for a specific transaction
     * @dev Public view function to check cancellation request status
     * @param _transactionId Transaction ID to check
     * @param _owner Owner address to check
     * @return True if the owner has requested cancellation, false otherwise
     */
    function hasRequestedCancellation(uint256 _transactionId, address _owner)
        external
        view
        transactionExists(_transactionId)
        returns (bool)
    {
        return transactionCancellations[_transactionId][_owner];
    }

    /**
     * @notice Internal function to execute a confirmed transaction
     * @dev Performs the actual transaction execution with proper validations
     * @param transaction Storage reference to the transaction to execute
     * @param transactionId ID of the transaction being executed
     * @custom:requirements
     * - Transaction must not be cancelled or already executed
     * - Transaction must have sufficient confirmations
     * - External call must succeed
     */
    function _executeTransaction(Transaction storage transaction, uint256 transactionId) private {
        if (transaction.cancelled) revert MultiSig__TransactionAlreadyCancelled(transactionId);
        if (transaction.executed) revert MultiSig__TransactionAlreadyExecuted(transactionId);
        if (transaction.confirmations < minConfirmations) {
            revert MultiSig__InvalidTransactionOperation(transactionId, "Insufficient confirmations");
        }

        transaction.executed = true;

        (bool success,) = transaction.to.call{value: transaction.value}(transaction.data);

        if (!success) revert MultiSig__TransactionExecutionFailed(transactionId, transaction.to);

        emit TransactionExecuted(transaction.sender, transactionId, transaction.to, transaction.value);
    }

    /**
     * @notice Internal function to cancel a transaction
     * @dev Marks a transaction as cancelled and emits the appropriate event
     * @param _id Transaction ID to cancel
     */
    function _cancelTransaction(uint256 _id) private {
        transactions[_id].cancelled = true;
        emit TransactionCancelled(_id, transactions[_id].cancellations);
    }

    /**
     * @notice Allows the contract to receive ETH directly
     * @dev Required for the multi-sig to hold ETH balance
     */
    receive() external payable {}

    /**
     * @notice Fallback function to handle unexpected calls
     * @dev Allows the contract to receive ETH from any source
     */
    fallback() external payable {}
}
