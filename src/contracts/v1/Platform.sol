// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {INatillera} from "../../interfaces/v1/INatillera.sol";
import {ITokenizacion} from "../../interfaces/v1/ITokenizacion.sol";

/**
 * @title Platform
 * @notice Factory for deploying Natillera and Tokenizacion projects
 * @dev MVP V1: Simple factory with fixed fee, no token registry, no user management
 */
contract Platform is Ownable, ReentrancyGuard {
    using Clones for address;

    /*///////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fixed deployment fee (0.01 ETH)
    uint256 public feeAmount = 0.01 ether;

    /*///////////////////////////////////////////////////////////////
                                STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Next available project ID (starts at 1)
    uint256 private _nextProjectId = 1;

    /// @notice Natillera implementation contract address
    address public natilleraImplementation;

    /// @notice Tokenizacion implementation contract address
    address public tokenizacionImplementation;

    /// @notice Mapping from project ID to deployed contract address
    mapping(uint256 => address) public getProjectById;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Event emitted when a new Natillera pool is deployed
     * @param natillera Address of the deployed Natillera contract
     * @param projectId Unique project identifier
     * @param creator Address of the project creator
     * @dev Emitted from `deployNatillera()` function
     */
    event NatilleraDeployed(
        address indexed natillera,
        uint256 indexed projectId,
        address creator
    );

    /**
     * @notice Event emitted when a new Tokenizacion sale is deployed
     * @param tokenizacion Address of the deployed Tokenizacion contract
     * @param projectId Unique project identifier
     * @param creator Address of the project creator
     * @dev Emitted from `deployTokenizacion()` function
     */
    event TokenizacionDeployed(
        address indexed tokenizacion,
        uint256 indexed projectId,
        address creator
    );

    /**
     * @notice Event emitted when the deployment fee is updated
     * @param newFee New fee amount in wei
     * @dev Emitted from `updateFee()` function
     */
    event FeeUpdated(uint256 newFee);

    /**
     * @notice Event emitted when collected fees are withdrawn
     * @param recipient Address that received the fees
     * @param amount Amount withdrawn in wei
     * @dev Emitted from `withdrawFees()` function
     */
    event FeesWithdrawn(address recipient, uint256 amount);

    /**
     * @notice Event emitted when an implementation address is updated
     * @param contractType Type of contract ("NATILLERA" or "TOKENIZACION")
     * @param implementation New implementation contract address
     * @dev Emitted from `updateImplementation()` function
     */
    event ImplementationUpdated(string contractType, address implementation);

    /**
     * @notice Event emitted when a fee is paid for deployment
     * @param user Address paying the fee
     * @param amount Fee amount paid in wei
     * @param projectType Type of project ("NATILLERA" or "TOKENIZACION")
     * @dev Emitted from deployment functions for debugging purposes
     */
    event FeePaid(
        address indexed user,
        uint256 amount,
        string indexed projectType
    );

    /*///////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error emitted when insufficient fee is provided for deployment
    error InsufficientFee();
    /// @notice Error emitted when an invalid implementation address is provided
    error InvalidImplementation();
    /// @notice Error emitted when an ETH transfer fails
    error TransferFailed();

    /*///////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the Platform factory with implementations
     * @param natilleraImpl Address of the Natillera implementation contract
     * @param tokenizacionImpl Address of the Tokenizacion implementation contract
     * @dev Both implementation addresses must be non-zero
     */
    constructor(
        address natilleraImpl,
        address tokenizacionImpl
    ) Ownable(msg.sender) {
        if (natilleraImpl == address(0) || tokenizacionImpl == address(0)) {
            revert InvalidImplementation();
        }

        natilleraImplementation = natilleraImpl;
        tokenizacionImplementation = tokenizacionImpl;
    }

    /*///////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy a new Natillera savings pool
     * @param startTime Timestamp when contributions start
     * @param config Pool configuration parameters
     * @return Address of the deployed Natillera contract
     * @dev Requires fee payment in ETH
     * @dev Uses Clone pattern for gas-efficient deployment
     */
    function deployNatillera(
        uint256 startTime,
        INatillera.Config calldata config
    ) external payable nonReentrant returns (address) {
        // Validate fee payment
        if (msg.value < feeAmount) revert InsufficientFee();

        // Emit fee event for debugging
        emit FeePaid(msg.sender, feeAmount, "NATILLERA");

        // Refund excess ETH if any
        if (msg.value > feeAmount) {
            _safeTransferEth(msg.sender, msg.value - feeAmount);
        }

        // Get and increment project ID
        uint256 projectId = _nextProjectId++;

        // Clone the implementation using EIP-1167 minimal proxy
        address clone = natilleraImplementation.clone();

        // Prepare project information
        INatillera.ProjectInfo memory info = INatillera.ProjectInfo({
            platform: address(this),
            projectId: projectId,
            creator: msg.sender
        });

        // Initialize the cloned Natillera contract
        INatillera(clone).initialize(startTime, config, info);

        // Store reference for lookup
        getProjectById[projectId] = clone;

        emit NatilleraDeployed(clone, projectId, msg.sender);
        return clone;
    }

    /**
     * @notice Deploy a new Tokenizacion sale contract
     * @param config Sale configuration parameters
     * @return Address of the deployed Tokenizacion contract
     * @dev Requires fee payment in ETH
     * @dev Uses Clone pattern for gas-efficient deployment
     */
    function deployTokenizacion(
        ITokenizacion.Config calldata config
    ) external payable nonReentrant returns (address) {
        // Validate fee payment
        if (msg.value < feeAmount) revert InsufficientFee();

        // Emit fee event for debugging
        emit FeePaid(msg.sender, feeAmount, "TOKENIZACION");

        // Refund excess ETH if any
        if (msg.value > feeAmount) {
            _safeTransferEth(msg.sender, msg.value - feeAmount);
        }

        // Get and increment project ID
        uint256 projectId = _nextProjectId++;

        // Clone the implementation using EIP-1167 minimal proxy
        address clone = tokenizacionImplementation.clone();

        // Prepare project information
        ITokenizacion.ProjectInfo memory info = ITokenizacion.ProjectInfo({
            platform: address(this),
            projectId: projectId,
            creator: msg.sender
        });

        // Initialize the cloned Tokenizacion contract
        ITokenizacion(clone).initialize(config, info);

        // Store reference for lookup
        getProjectById[projectId] = clone;

        emit TokenizacionDeployed(clone, projectId, msg.sender);
        return clone;
    }

    /*///////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the deployment fee amount
     * @param newFee New fee amount in wei
     * @dev Can only be called by contract owner
     */
    function updateFee(uint256 newFee) external onlyOwner {
        feeAmount = newFee;
        emit FeeUpdated(newFee);
    }

    /**
     * @notice Withdraw all collected deployment fees
     * @param recipient Address to receive the collected fees
     * @dev Can only be called by contract owner
     * @dev Requires non-zero balance in contract
     */
    function withdrawFees(
        address payable recipient
    ) external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert InsufficientFee();

        _safeTransferEth(recipient, balance);
        emit FeesWithdrawn(recipient, balance);
    }

    /**
     * @notice Update implementation contract address
     * @param contractType Type of contract ("NATILLERA" or "TOKENIZACION")
     * @param implementation New implementation contract address
     * @dev Can only be called by contract owner
     * @dev Implementation address must be non-zero
     */
    function updateImplementation(
        string calldata contractType,
        address implementation
    ) external onlyOwner {
        if (implementation == address(0)) revert InvalidImplementation();

        bytes32 typeHash = keccak256(bytes(contractType));

        if (typeHash == keccak256("NATILLERA")) {
            natilleraImplementation = implementation;
        } else if (typeHash == keccak256("TOKENIZACION")) {
            tokenizacionImplementation = implementation;
        } else {
            revert InvalidImplementation();
        }

        emit ImplementationUpdated(contractType, implementation);
    }

    /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get total number of deployed projects
     * @return uint256 Total count of deployed projects
     */
    function totalProjects() external view returns (uint256) {
        return _nextProjectId - 1;
    }

    /*///////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Safely transfer ETH to a recipient address
     * @param to Recipient address
     * @param amount Amount to transfer in wei
     * @notice Reverts if transfer fails
     */
    function _safeTransferEth(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /*///////////////////////////////////////////////////////////////
                            FALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allow contract to receive ETH payments
     * @dev Required for fee collection
     */
    receive() external payable {}
}
