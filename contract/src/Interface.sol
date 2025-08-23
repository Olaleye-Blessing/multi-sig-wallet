// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

/**
 * @title IMultiSig
 * @notice Interface for a multi-signature wallet contract
 * @dev Defines the structure, events, and errors for multi-signature wallet functionality
 */
interface IMultiSig {
    /**
     * @notice Structure representing a multi-sig transaction
     * @param id Unique identifier for the transaction
     * @param value Amount of ETH to be sent with the transaction
     * @param confirmations Current number of confirmations received
     * @param cancellations Current number of cancellation requests received
     * @param timestamp Block timestamp when transaction was submitted
     * @param executed Whether the transaction has been executed
     * @param cancelled Whether the transaction has been cancelled
     * @param sender Address that submitted the transaction
     * @param to Target address for the transaction
     * @param data Encoded function call data
     */
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

    /**
     * @notice Emitted when a transaction is successfully executed
     * @param sender Original submitter of the transaction
     * @param transactionId Unique identifier of the executed transaction
     * @param target Target address that received the transaction
     * @param value Amount of ETH sent with the transaction
     */
    event TransactionExecuted(
        address indexed sender, 
        uint256 indexed transactionId, 
        address indexed target,
        uint256 value
    );
    
    /**
     * @notice Emitted when a new transaction is submitted to the multi-sig
     * @param submitter Address that submitted the transaction
     * @param transactionId Unique identifier assigned to the transaction
     * @param target Target address for the transaction
     * @param value Amount of ETH to be sent
     * @param data Encoded function call data
     */
    event TransactionSubmitted(
        address indexed submitter, 
        uint256 indexed transactionId, 
        address indexed target,
        uint256 value,
        bytes data
    );
    
    /**
     * @notice Emitted when an owner confirms a transaction
     * @param confirmer Address of the owner who confirmed
     * @param transactionId Transaction that was confirmed
     * @param confirmationsCount Total confirmations after this confirmation
     */
    event TransactionConfirmed(
        address indexed confirmer, 
        uint256 indexed transactionId,
        uint256 confirmationsCount
    );
    
    /**
     * @notice Emitted when an owner revokes their confirmation
     * @param revoker Address of the owner who revoked confirmation
     * @param transactionId Transaction for which confirmation was revoked
     * @param confirmationsCount Total confirmations after revocation
     */
    event ConfirmationRevoked(
        address indexed revoker, 
        uint256 indexed transactionId,
        uint256 confirmationsCount
    );
    
    /**
     * @notice Emitted when an owner requests cancellation of a transaction
     * @param requester Address requesting cancellation
     * @param transactionId Transaction for which cancellation was requested
     * @param cancellationsCount Total cancellation requests after this request
     */
    event CancellationRequested(
        address indexed requester, 
        uint256 indexed transactionId,
        uint256 cancellationsCount
    );
    
    /**
     * @notice Emitted when an owner revokes their cancellation request
     * @param revoker Address revoking the cancellation request
     * @param transactionId Transaction for which cancellation request was revoked
     * @param cancellationsCount Total cancellation requests after revocation
     */
    event CancellationRequestRevoked(
        address indexed revoker, 
        uint256 indexed transactionId,
        uint256 cancellationsCount
    );
    
    /**
     * @notice Emitted when a transaction is cancelled due to sufficient cancellation requests
     * @param transactionId Transaction that was cancelled
     * @param cancellationsReceived Number of cancellation requests received
     */
    event TransactionCancelled(
        uint256 indexed transactionId,
        uint256 cancellationsReceived
    );

    /**
    * @notice Emitted when the minimum confirmations is updated.
    * @param oldMinConfirmations The old min confirmations needed to execute a transaction
    * @param newMinConfirmations The new min confirmations needed to execute a transaction
    */
    event MinConfirmationsUpdated(
        uint256 oldMinConfirmations,
        uint256 newMinConfirmations
    );
    
    /**
     * @notice Emitted when a new owner is added to the multi-sig
     * @param newOwner Address of the newly added owner
     * @param newMinConfirmations Updated minimum confirmations requirement
     * @param totalOwners New total number of owners
     */
    event OwnerAdded(
        address indexed newOwner, 
        uint256 newMinConfirmations,
        uint256 totalOwners
    );

    /**
     * @notice Emitted when an owner is removed from the multi-sig
     * @param oldOwner Address of the owner to remove
     * @param newMinConfirmations Updated minimum confirmations requirement
     * @param totalOwners New total number of owners
     */
    event OwnerRemoved(
        address indexed oldOwner, 
        uint256 newMinConfirmations,
        uint256 totalOwners
    );
    
    /**
     * @notice Thrown when a non-owner attempts to call an owner-only function
     * @param caller Address that attempted the call
     */
    error MultiSig__NotAnOwner(address caller);
    
    /**
     * @notice Thrown when an invalid transaction operation is attempted
     * @param transactionId ID of the transaction
     * @param reason Specific reason for the invalid operation
     */
    error MultiSig__InvalidTransactionOperation(uint256 transactionId, string reason);
    
    /**
     * @notice Thrown when trying to access a non-existent transaction
     * @param transactionId ID that was requested
     * @param maxValidId Maximum valid transaction ID
     */
    error MultiSig__TransactionDoesNotExist(uint256 transactionId, uint256 maxValidId);
    
    /**
     * @notice Thrown when a transaction has already been cancelled
     * @param transactionId ID of the already cancelled transaction
     */
    error MultiSig__TransactionAlreadyCancelled(uint256 transactionId);
    
    /**
     * @notice Thrown when trying to revoke a confirmation that doesn't exist
     * @param transactionId Transaction ID
     * @param owner Address that hasn't confirmed
     */
    error MultiSig__ConfirmationDoesNotExist(uint256 transactionId, address owner);
    
    /**
     * @notice Thrown when trying to revoke a cancellation request that doesn't exist
     * @param transactionId Transaction ID
     * @param owner Address that hasn't requested cancellation
     */
    error MultiSig__CancellationRequestDoesNotExist(uint256 transactionId, address owner);
    
    /**
     * @notice Thrown when the zero address is provided where not allowed
     */
    error MultiSig__ZeroAddressNotAllowed();
    
    /**
     * @notice Thrown when trying to add an address that's already an owner
     * @param duplicateAddress Address that's already an owner
     */
    error MultiSig__AddressAlreadyOwner(address duplicateAddress);

    /**
     * @notice Thrown when trying to get/remove an address that is not an owner
     * @param unknownAddress The unknown address
     */
    error MultiSig__AddressNotAnOwner(address unknownAddress);
    
    /**
     * @notice Thrown when minimum confirmations is set to zero
     */
    error MultiSig__MinConfirmationsMustBeAtLeastOne();
    
    /**
     * @notice Thrown when minimum confirmations exceeds the number of owners
     * @param requested Requested minimum confirmations
     * @param maxAllowed Maximum allowed (number of owners)
     */
    error MultiSig__MinConfirmationsExceedsOwnerCount(uint256 requested, uint256 maxAllowed);
    
    /**
     * @notice Thrown when a function can only be called by the contract itself
     * @param caller Address that attempted the call
     */
    error MultiSig__OnlyCallableByContract(address caller);
    
    /**
     * @notice Thrown when a transaction execution fails
     * @param transactionId ID of the failed transaction
     * @param target Target address of the failed call
     */
    error MultiSig__TransactionExecutionFailed(uint256 transactionId, address target);
    
    /**
     * @notice Thrown when trying to confirm an already confirmed transaction
     * @param transactionId Transaction ID
     * @param owner Address that already confirmed
     */
    error MultiSig__TransactionAlreadyConfirmed(uint256 transactionId, address owner);
    
    /**
     * @notice Thrown when trying to request cancellation for an already executed transaction
     * @param transactionId ID of the executed transaction
     */
    error MultiSig__TransactionAlreadyExecuted(uint256 transactionId);
    
    /**
     * @notice Thrown when trying to make a cancellation request that already exists
     * @param transactionId Transaction ID
     * @param owner Address that already requested cancellation
     */
    error MultiSig__CancellationAlreadyRequested(uint256 transactionId, address owner);
}
