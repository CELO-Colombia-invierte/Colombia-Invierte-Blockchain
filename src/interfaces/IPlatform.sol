// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {INatillera} from "interfaces/INatillera.sol";
import {ITokenizacion} from "interfaces/ITokenizacion.sol";
import {ITracking} from "interfaces/ITracking.sol";

/**
 * @title IPlatform
 * @author K-Labs
 * @notice Factory and management contract for Natillera and Tokenization projects
 * @dev Factory pattern with fee collection and user management
 * @dev All fee percentages are expressed in basis points (1/100th of 1%)
 * @dev Project IDs start from 1 (0 is reserved/invalid)
 */
interface IPlatform is ITracking {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Platform configuration parameters
     * @param natilleraFee Flat fee for natillera deployment (in native currency)
     * @param tokenizationFee Percentage fee for tokenization deployment (in basis points)
     * @param withdrawalFee Percentage fee for withdrawals (in basis points)
     * @param minDelay Minimum governance execution delay (in seconds)
     * @param minQuorum Minimum governance quorum (in basis points)
     */
    struct PlatformParams {
        uint256 natilleraFee;
        uint256 tokenizationFee;
        uint256 withdrawalFee;
        uint256 minDelay;
        uint256 minQuorum;
    }

    /**
     * @notice Governance configuration for projects
     * @param governanceDelay Delay for governance execution (in seconds)
     * @param minQuorum Minimum quorum for governance proposals (in basis points)
     */
    struct GovernanceConfig {
        uint256 governanceDelay;
        uint256 minQuorum;
    }

    /**
     * @notice Project configuration passed to deployed contracts
     * @param projectId Unique identifier for the project
     * @param creator Address of the project creator
     * @param platform Address of the platform contract
     */
    struct ProjectConfig {
        uint256 projectId;
        address creator;
        address platform;
    }

    /**
     * @notice User information structure
     * @param emailHash keccak256 hash of user's email (for privacy)
     * @param projectIds Array of project IDs the user participates in
     */
    struct UserInfo {
        bytes32 emailHash;
        uint256[] projectIds;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new natillera is deployed
     * @param natillera Address of the deployed natillera contract
     * @param projectId Unique ID of the project
     * @param creator Address of the project creator
     */
    event NatilleraDeployed(
        address indexed natillera,
        uint256 indexed projectId,
        address creator
    );

    /**
     * @notice Emitted when a new tokenization project is deployed
     * @param tokenization Address of the deployed tokenization contract
     * @param projectId Unique ID of the project
     * @param creator Address of the project creator
     */
    event TokenizacionDeployed(
        address indexed tokenization,
        uint256 indexed projectId,
        address creator
    );

    /**
     * @notice Emitted when a user registers on the platform
     * @param user Address of the registered user
     * @param emailHash Hash of the user's email
     */
    event UserRegistered(address indexed user, bytes32 emailHash);

    /**
     * @notice Emitted when a user is added to a project
     * @param projectId ID of the project
     * @param user Address of the user added
     * @param addedBy Address that performed the addition (project contract)
     */
    event UserAddedToProject(
        uint256 indexed projectId,
        address indexed user,
        address indexed addedBy
    );

    /**
     * @notice Emitted when a token's status is updated
     * @param token Address of the ERC20 token
     * @param allowed Whether the token is now allowed (true) or disallowed (false)
     */
    event TokenStatusUpdated(address indexed token, bool allowed);

    /**
     * @notice Emitted when platform parameters are updated
     * @param parameter Identifier of the parameter changed
     * @param value New value of the parameter
     */
    event ParameterUpdated(bytes32 indexed parameter, uint256 value);

    /**
     * @notice Emitted when an implementation contract is updated
     * @param implementationType Type of implementation ("NATILLERA" or "TOKENIZACION")
     * @param implementation Address of the new implementation
     * @param version New version number
     */
    event ImplementationUpdated(
        bytes32 indexed implementationType,
        address implementation,
        uint256 version
    );

    /**
     * @notice Emitted when native currency fees are withdrawn
     * @param recipient Address that received the fees (owner)
     * @param amount Amount withdrawn
     */
    event NativeFeesWithdrawn(address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when ERC20 fees are withdrawn
     * @param token Address of the ERC20 token
     * @param recipient Address that received the fees (owner)
     * @param amount Amount withdrawn
     */
    event ERC20FeesWithdrawn(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    /**
     * @notice Emitted when excess ETH is refunded
     * @param recipient Address that received the refund
     * @param amount Amount refunded
     */
    event ExcessEthRefunded(address indexed recipient, uint256 amount);

    /**
     * @notice Emitted when tokens are rescued in emergency
     * @param token Address of the rescued token
     * @param recipient Address that received the tokens (owner)
     * @param amount Amount rescued
     */
    event TokensRescued(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    /**
     * @notice Emitted when the Platform contract is initialized
     * @param natilleraImplementation Initial Natillera implementation address
     * @param tokenizacionImplementation Initial Tokenization implementation address
     * @param platformParams Initial platform parameters
     */
    event PlatformInitialized(
        address natilleraImplementation,
        address tokenizacionImplementation,
        PlatformParams platformParams
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Invalid parameter provided
    error InvalidParameter();

    /// @notice Invalid token address or not a proper ERC20
    error InvalidToken();

    /// @notice Attempted to withdraw with zero balance
    error BalanceZero();

    /// @notice Insufficient balance for the operation
    error InsufficientBalance();

    /// @notice Insufficient fee paid for operation
    error InsufficientFee();

    /// @notice Caller is not authorized for the operation
    error InvalidCaller();

    /// @notice Transfer of funds failed
    error TransferFailed();

    /// @notice Wallet is already registered
    error UserAlreadyRegistered();

    /// @notice Wallet is not registered
    error UserNotRegistered();

    /// @notice Token is already registered
    error TokenAlreadyRegistered();

    /// @notice Token is not registered
    error TokenNotRegistered();

    /// @notice Maximum number of tokens reached
    error MaxTokensReached();

    /// @notice ETH refund failed
    error RefundFailed();

    /// @notice Cannot rescue registered tokens
    error CannotRescueRegisteredToken();

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the Platform contract
     * @dev Can only be called once per instance
     * @dev Sets up implementations and platform parameters
     * @param _natilleraImplementation Address of the Natillera implementation
     * @param _tokenizacionImplementation Address of the Tokenization implementation
     * @param platformParams Platform configuration parameters
     */
    function initialize(
        address _natilleraImplementation,
        address _tokenizacionImplementation,
        PlatformParams calldata platformParams
    ) external;

    /*//////////////////////////////////////////////////////////////
                            PROJECT DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys a new Natillera contract
     * @dev Requires payment of native currency fee, excess is refunded
     * @dev Validates start time is within reasonable future bounds (max 1 year)
     * @param startTimestamp When the natillera should start accepting contributions
     * @param natilleraConfig Configuration specific to the natillera
     * @param governanceConfig Governance parameters for the natillera
     */
    function deployNatillera(
        uint256 startTimestamp,
        INatillera.NatilleraConfig calldata natilleraConfig,
        GovernanceConfig calldata governanceConfig
    ) external payable;

    /**
     * @notice Deploys a new Tokenization contract
     * @dev Fee can be paid in native currency or registered ERC20 token
     * @dev Fee is calculated as percentage of total token value (price * quantity)
     * @param tokenizationParams Tokenization project parameters
     * @param governanceConfig Governance parameters for the tokenization
     */
    function deployTokenizacion(
        ITokenizacion.TokenizacionParams calldata tokenizationParams,
        GovernanceConfig calldata governanceConfig
    ) external payable;

    /*//////////////////////////////////////////////////////////////
                            USER MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Registers a new user with their email hash
     * @param emailHash keccak256 hash of user's email for privacy
     */
    function registerUser(bytes32 emailHash) external;

    /**
     * @notice Adds a user to a specific project
     * @dev Only callable by the project contract itself
     * @dev User must be registered on the platform
     * @param projectId ID of the project
     * @param user Address of the user to add
     */
    function addUserToProject(uint256 projectId, address user) external;

    /*//////////////////////////////////////////////////////////////
                            FEE MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraws accumulated native currency fees to owner
     * @dev Uses call() instead of transfer() for forward compatibility
     * @dev Can be called even when contract is paused
     */
    function withdrawNativeFees() external;

    /**
     * @notice Withdraws all registered ERC20 token fees to owner
     * @dev Iterates through all registered tokens
     * @dev Can be called even when contract is paused
     */
    function withdrawERC20Fees() external;

    /**
     * @notice Withdraws specific ERC20 token fees to owner
     * @dev Can be called even when contract is paused
     * @param token Address of the ERC20 token to withdraw
     */
    function withdrawERC20FeesByToken(address token) external;

    /*//////////////////////////////////////////////////////////////
                            ADMINISTRATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new ERC20 token to the allowed list
     * @dev Validates token is a proper ERC20 with non-zero total supply
     * @dev Maximum 100 tokens can be registered
     * @param token Address of the ERC20 token to register
     */
    function registerToken(address token) external;

    /**
     * @notice Removes an ERC20 token from the allowed list
     * @param token Address of the ERC20 token to deregister
     */
    function deregisterToken(address token) external;

    /**
     * @notice Updates platform parameters
     * @dev Only owner can call this function
     * @dev Fee parameters cannot exceed 100% (10,000 basis points)
     * @param parameter Identifier of the parameter to update
     * @param value New value for the parameter
     */
    function updateParameter(bytes32 parameter, uint256 value) external;

    /**
     * @notice Updates implementation contracts
     * @dev Only owner can call this function
     * @dev Implementation version is incremented automatically
     * @param implementation New implementation address
     * @param implementationType Type of implementation ("NATILLERA" or "TOKENIZACION")
     */
    function updateImplementation(
        address implementation,
        bytes32 implementationType
    ) external;

    /**
     * @notice Emergency function to rescue accidentally sent tokens
     * @dev Only for tokens not registered in the platform
     * @dev Only owner can rescue tokens
     * @dev Can be called even when contract is paused
     * @param token Address of the token to rescue
     * @param amount Amount to rescue
     */
    function rescueToken(address token, uint256 amount) external;

    /**
     * @notice Pauses the contract, stopping critical operations
     * @dev Only owner can pause the contract
     * @dev Prevents new project deployments and user registrations
     */
    function pause() external;

    /**
     * @notice Unpauses the contract, resuming normal operations
     * @dev Only owner can unpause the contract
     */
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the current Natillera implementation address
     * @return implementation Address of the Natillera implementation
     */
    function natilleraImplementation()
        external
        view
        returns (address implementation);

    /**
     * @notice Returns the current Natillera implementation version
     * @return version Current version number
     */
    function natilleraVersion() external view returns (uint256 version);

    /**
     * @notice Returns the current Tokenization implementation address
     * @return implementation Address of the Tokenization implementation
     */
    function tokenizacionImplementation()
        external
        view
        returns (address implementation);

    /**
     * @notice Returns the current Tokenization implementation version
     * @return version Current version number
     */
    function tokenizacionVersion() external view returns (uint256 version);

    /**
     * @notice Returns current platform parameters
     * @return params Current platform parameters
     */
    function getPlatformParameters()
        external
        view
        returns (PlatformParams memory params);

    /**
     * @notice Returns list of all registered ERC20 tokens
     * @return tokens Array of registered token addresses
     */
    function getRegisteredTokens()
        external
        view
        returns (address[] memory tokens);

    /**
     * @notice Returns user information for a specific address
     * @param user Address of the user
     * @return info User information including email hash and project IDs
     */
    function getUserInfo(
        address user
    ) external view returns (UserInfo memory info);

    /**
     * @notice Returns balance of specific token held by platform
     * @param token Address of the ERC20 token
     * @return balance Current balance of the token
     */
    function getTokenBalance(
        address token
    ) external view returns (uint256 balance);

    /**
     * @notice Checks if an address is registered as a user
     * @param user Address to check
     * @return registered True if registered, false otherwise
     */
    function isUserRegistered(
        address user
    ) external view returns (bool registered);

    /**
     * @notice Returns the total number of projects created
     * @return total Number of projects (project IDs start from 1)
     */
    function totalProjects() external view returns (uint256 total);

    /**
     * @notice Returns project address by ID
     * @param projectId ID of the project
     * @return project Address of the project contract
     */
    function getProjectById(
        uint256 projectId
    ) external view returns (address project);

    /**
     * @notice Checks if a token is registered and allowed
     * @param token Address of the token to check
     * @return registered True if registered, false otherwise
     */
    function isTokenRegistered(
        address token
    ) external view returns (bool registered);
}
