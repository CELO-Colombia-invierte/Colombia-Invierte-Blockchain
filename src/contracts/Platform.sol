// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

import {INatillera} from "interfaces/INatillera.sol";
import {IPlatform} from "interfaces/IPlatform.sol";
import {ITokenizacion} from "interfaces/ITokenizacion.sol";

/**
 * @title Platform
 * @dev Main contract for managing natilleras and tokenization projects
 * @notice This contract handles project deployment, user registration, fee management,
 *         token administration, and emergency controls for the platform ecosystem
 * @dev All fees are represented in basis points (1/100th of 1%)
 * @dev Contract is pausable for emergency situations
 */
contract Platform is IPlatform, Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Maximum fee percentage (100% in basis points)
    uint256 private constant MAX_FEE_BPS = 10_000;

    /// @dev Maximum number of tokens that can be registered
    uint256 private constant MAX_REGISTERED_TOKENS = 100;

    /// @dev Maximum future start time for natilleras (1 year)
    uint256 private constant MAX_FUTURE_START = 365 days;

    /// @dev Parameter identifiers for updateParameter function
    bytes32 private constant PARAM_FEE_NATILLERA = "FEE_DE_NATILLERA";
    bytes32 private constant PARAM_FEE_TOKENIZACION = "FEE_DE_TOKENIZACION";
    bytes32 private constant PARAM_FEE_WITHDRAWAL = "FEE_DE_WITHDRAWAL";
    bytes32 private constant PARAM_DELAY_MINIMO = "DELAY_MINIMO";
    bytes32 private constant PARAM_QUORUM_MINIMO = "QUORUM_MINIMO";

    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IPlatform
    address public override natilleraImplementation;

    /// @inheritdoc IPlatform
    uint256 public override natilleraVersion;

    /// @inheritdoc IPlatform
    address public override tokenizacionImplementation;

    /// @inheritdoc IPlatform
    uint256 public override tokenizacionVersion;

    /// @inheritdoc IPlatform
    mapping(address => bool) public override tokenStatus;

    /// @inheritdoc IPlatform
    mapping(uint256 => address) public override proyectoPorId;

    /// @dev Internal mapping of user information
    mapping(address => UserInfo) private _userInfo;

    /// @dev Counter for generating unique project IDs
    uint256 private _nextProjectId;

    /// @dev Platform parameters and configuration
    PlatformParams private _platformParams;

    /// @dev List of registered ERC20 tokens
    address[] private _registeredTokens;

    /*///////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Verifies governance configuration meets minimum requirements
     * @param config Governance configuration to validate
     */
    modifier validateGovernanceConfig(GovernanceConfig calldata config) {
        if (config.governanceDelay < _platformParams.minDelay)
            revert Platform_InvalidParameter();
        if (config.minQuorum < _platformParams.minQuorum)
            revert Platform_InvalidParameter();
        _;
    }

    /**
     * @dev Restricts access to specific project only
     * @param projectId ID of the project
     */
    modifier onlyProject(uint256 projectId) {
        if (msg.sender != proyectoPorId[projectId])
            revert Platform_InvalidCaller();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the Platform contract
     * @param initialOwner Address that will become the contract owner
     * @param _natilleraImplementation Address of the Natillera implementation contract
     * @param _tokenizacionImplementation Address of the Tokenizacion implementation contract
     * @param platformParams Initial platform parameters
     * @dev All addresses are validated to be non-zero
     * @dev Platform parameters are validated for correctness
     */
    constructor(
        address initialOwner,
        address _natilleraImplementation,
        address _tokenizacionImplementation,
        PlatformParams memory platformParams
    ) Ownable2Step(initialOwner) {
        if (initialOwner == address(0)) revert Platform_InvalidParameter();
        if (
            _natilleraImplementation == address(0) ||
            _tokenizacionImplementation == address(0)
        ) revert Platform_InvalidParameter();

        // Validate initial platform parameters
        _validatePlatformParams(platformParams);

        _platformParams = platformParams;

        // CORRECCIÓN: Asignación correcta con prefijo underscore
        natilleraImplementation = _natilleraImplementation;
        tokenizacionImplementation = _tokenizacionImplementation;

        natilleraVersion = 1;
        tokenizacionVersion = 1;

        // Start project IDs from 1 (0 is invalid/reserved)
        _nextProjectId = 1;
    }

    /*///////////////////////////////////////////////////////////////
                                PROJECT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
     * @notice Deploys a new Natillera contract
     * @dev Requires payment of NATIVE currency fee, excess is refunded
     * @dev Validates start time is within reasonable future bounds
     * @dev Contract must not be paused
     * @param startTimestamp When the natillera should start accepting contributions
     * @param natilleraConfig Configuration specific to the natillera
     * @param governanceConfig Governance parameters for the natillera
     */
    function deployNatillera(
        uint256 startTimestamp,
        INatillera.NatilleraConfig calldata natilleraConfig,
        GovernanceConfig calldata governanceConfig
    )
        external
        payable
        override
        validateGovernanceConfig(governanceConfig)
        nonReentrant
        whenNotPaused
    {
        uint256 requiredFee = _platformParams.natilleraFee;

        // Validate fee payment
        if (msg.value < requiredFee) revert Platform_InsufficientFee();

        // Validate start timestamp
        if (
            startTimestamp < block.timestamp ||
            startTimestamp > block.timestamp + MAX_FUTURE_START
        ) revert Platform_InvalidParameter();

        // Refund excess ETH
        _refundExcessEth(requiredFee);

        // Generate project configuration
        ProjectConfig memory projectConfig = _generateNextProjectConfig(
            msg.sender
        );

        // Clone and initialize natillera
        address natilleraClone = Clones.clone(natilleraImplementation);
        INatillera(natilleraClone).initialize(
            startTimestamp,
            natilleraConfig,
            governanceConfig,
            projectConfig
        );

        // Store project reference
        proyectoPorId[projectConfig.projectId] = natilleraClone;

        emit NatilleraDeployed(
            natilleraClone,
            projectConfig.projectId,
            msg.sender
        );
    }

    /**
     * @inheritdoc IPlatform
     * @notice Deploys a new Tokenizacion contract
     * @dev Calculates fee based on total token value (price * quantity)
     * @dev Accepts fee payment in either native currency or registered ERC20
     * @dev Contract must not be paused
     * @param tokenizationParams Tokenization project parameters
     * @param governanceConfig Governance parameters for the tokenization
     */
    function deployTokenizacion(
        ITokenizacion.TokenizacionParams calldata tokenizationParams,
        GovernanceConfig calldata governanceConfig
    )
        external
        payable
        override
        validateGovernanceConfig(governanceConfig)
        nonReentrant
        whenNotPaused
    {
        // Validate tokenization parameters
        if (
            tokenizationParams.totalTokens == 0 ||
            tokenizationParams.pricePerToken == 0
        ) revert Platform_InvalidParameter();

        // Calculate total value and fee
        uint256 totalValue = tokenizationParams.totalTokens *
            tokenizationParams.pricePerToken;
        uint256 feeAmount = (totalValue * _platformParams.tokenizationFee) /
            MAX_FEE_BPS;

        // Validate fee is not excessive (max 50% of total value)
        if (feeAmount > totalValue / 2) {
            revert Platform_InvalidParameter();
        }

        // Process fee payment
        if (tokenizationParams.paymentToken == address(0)) {
            // Native currency payment
            if (msg.value < feeAmount) revert Platform_InsufficientFee();
            _refundExcessEth(feeAmount);
        } else {
            // ERC20 payment
            if (!tokenStatus[tokenizationParams.paymentToken])
                revert Platform_TokenNotRegistered();

            IERC20(tokenizationParams.paymentToken).safeTransferFrom(
                msg.sender,
                address(this),
                feeAmount
            );
        }

        // Generate project configuration
        ProjectConfig memory projectConfig = _generateNextProjectConfig(
            msg.sender
        );

        // Clone and initialize tokenization
        address tokenizationClone = Clones.clone(tokenizacionImplementation);
        ITokenizacion(tokenizationClone).initialize(
            tokenizationParams,
            governanceConfig,
            projectConfig
        );

        // Store project reference
        proyectoPorId[projectConfig.projectId] = tokenizationClone;

        emit TokenizacionDeployed(
            tokenizationClone,
            projectConfig.projectId,
            msg.sender
        );
    }

    /*///////////////////////////////////////////////////////////////
                                USER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
     * @notice Registers a new user with their email hash
     * @dev Contract must not be paused
     * @param emailHash keccak256 hash of user's email for privacy
     */
    function registerUser(bytes32 emailHash) external override whenNotPaused {
        if (_isUserRegistered(msg.sender))
            revert Platform_UserAlreadyRegistered();

        _userInfo[msg.sender] = UserInfo({
            emailHash: emailHash,
            projectIds: new uint256[](0)
        });

        emit UserRegistered(msg.sender, emailHash);
    }

    /**
     * @inheritdoc IPlatform
     * @notice Adds a user to a specific project
     * @dev Only callable by the project contract itself
     * @dev User must be registered on the platform
     * @param projectId ID of the project
     * @param user Address of the user to add
     */
    function addUserToProject(
        uint256 projectId,
        address user
    ) external override onlyProject(projectId) {
        if (!_isUserRegistered(user)) revert Platform_UserNotRegistered();

        _userInfo[user].projectIds.push(projectId);

        emit UserAddedToProject(projectId, user, msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                                FEE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
     * @notice Withdraws accumulated native currency fees to owner
     * @dev Uses call instead of transfer for forward compatibility
     * @dev Contract can be paused or unpaused for withdrawals
     */
    function withdrawNativeFees() external override onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert Platform_BalanceZero();

        (bool success, ) = payable(owner()).call{value: balance}("");
        if (!success) revert Platform_TransferFailed();

        emit NativeFeesWithdrawn(owner(), balance);
    }

    /**
     * @inheritdoc IPlatform
     * @notice Withdraws all registered ERC20 token fees to owner
     * @dev Iterates through all registered tokens
     * @dev Contract can be paused or unpaused for withdrawals
     */
    function withdrawERC20Fees() external override onlyOwner nonReentrant {
        uint256 tokenCount = _registeredTokens.length;

        for (uint256 i = 0; i < tokenCount; ++i) {
            address token = _registeredTokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));

            if (balance > 0) {
                IERC20(token).safeTransfer(owner(), balance);
                emit ERC20FeesWithdrawn(token, owner(), balance);
            }
        }
    }

    /**
     * @inheritdoc IPlatform
     * @notice Withdraws specific ERC20 token fees to owner
     * @dev Contract can be paused or unpaused for withdrawals
     * @param token Address of the ERC20 token to withdraw
     */
    function withdrawERC20FeesByToken(
        address token
    ) external override onlyOwner nonReentrant {
        if (!tokenStatus[token]) revert Platform_TokenNotRegistered();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert Platform_BalanceZero();

        IERC20(token).safeTransfer(owner(), balance);

        emit ERC20FeesWithdrawn(token, owner(), balance);
    }

    /*///////////////////////////////////////////////////////////////
                                ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
     * @notice Adds a new ERC20 token to the allowed list
     * @dev Only owner can register tokens
     * @dev Validates token is a proper ERC20 with non-zero total supply
     * @param token Address of the ERC20 token to register
     */
    function registerToken(address token) external override onlyOwner {
        if (token == address(0) || token == address(this))
            revert Platform_InvalidToken();
        if (tokenStatus[token]) revert Platform_TokenAlreadyRegistered();
        if (_registeredTokens.length >= MAX_REGISTERED_TOKENS)
            revert Platform_MaxTokensReached();

        // Validate it's a proper ERC20
        try IERC20(token).totalSupply() returns (uint256 totalSupply) {
            if (totalSupply == 0) revert Platform_InvalidToken();
        } catch {
            revert Platform_InvalidToken();
        }

        // Additional ERC20 validation
        try IERC20(token).balanceOf(address(this)) returns (uint256) {
            // Token supports balanceOf - good
        } catch {
            revert Platform_InvalidToken();
        }

        tokenStatus[token] = true;
        _registeredTokens.push(token);

        emit TokenStatusUpdated(token, true);
    }

    /**
     * @inheritdoc IPlatform
     * @notice Removes an ERC20 token from the allowed list
     * @dev Only owner can deregister tokens
     * @param token Address of the ERC20 token to deregister
     */
    function deregisterToken(address token) external override onlyOwner {
        if (!tokenStatus[token]) revert Platform_TokenNotRegistered();

        tokenStatus[token] = false;
        _removeTokenFromRegistry(token);

        emit TokenStatusUpdated(token, false);
    }

    /**
     * @inheritdoc IPlatform
     * @notice Updates platform parameters
     * @dev Only owner can update parameters
     * @dev Fee parameters cannot exceed 100% (10,000 basis points)
     * @param parameter Identifier of the parameter to update
     * @param value New value for the parameter
     */
    function updateParameter(
        bytes32 parameter,
        uint256 value
    ) external override onlyOwner {
        if (parameter == PARAM_FEE_NATILLERA) {
            _platformParams.natilleraFee = value;
        } else if (parameter == PARAM_FEE_TOKENIZACION) {
            if (value > MAX_FEE_BPS) revert Platform_InvalidParameter();
            _platformParams.tokenizationFee = value;
        } else if (parameter == PARAM_FEE_WITHDRAWAL) {
            if (value > MAX_FEE_BPS) revert Platform_InvalidParameter();
            _platformParams.withdrawalFee = value;
        } else if (parameter == PARAM_DELAY_MINIMO) {
            if (value == 0) revert Platform_InvalidParameter();
            _platformParams.minDelay = value;
        } else if (parameter == PARAM_QUORUM_MINIMO) {
            if (value > MAX_FEE_BPS) revert Platform_InvalidParameter();
            _platformParams.minQuorum = value;
        } else {
            revert Platform_InvalidParameter();
        }

        emit ParameterUpdated(parameter, value);
    }

    /**
     * @inheritdoc IPlatform
     * @notice Updates implementation contracts
     * @dev Only owner can update implementations
     * @dev Implementation version is incremented automatically
     * @param implementation New implementation address
     * @param implementationType Type of implementation ("NATILLERA" or "TOKENIZACION")
     */
    function updateImplementation(
        address implementation,
        bytes32 implementationType
    ) external override onlyOwner {
        if (implementation == address(0)) revert Platform_InvalidParameter();

        if (implementationType == "NATILLERA") {
            natilleraImplementation = implementation;
            ++natilleraVersion;
            emit ImplementationUpdated(
                "NATILLERA",
                implementation,
                natilleraVersion
            );
        } else if (implementationType == "TOKENIZACION") {
            tokenizacionImplementation = implementation;
            ++tokenizacionVersion;
            emit ImplementationUpdated(
                "TOKENIZACION",
                implementation,
                tokenizacionVersion
            );
        } else {
            revert Platform_InvalidParameter();
        }
    }

    /**
     * @notice Pauses the contract, stopping critical operations
     * @dev Only owner can pause the contract
     * @dev Prevents new project deployments and user registrations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, resuming normal operations
     * @dev Only owner can unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency function to rescue accidentally sent tokens
     * @dev Only for tokens not registered in the platform
     * @dev Only owner can rescue tokens
     * @param token Address of the token to rescue
     * @param amount Amount to rescue
     */
    function rescueToken(
        address token,
        uint256 amount
    ) external onlyOwner nonReentrant {
        require(
            !tokenStatus[token],
            "Platform: Cannot rescue registered tokens"
        );
        require(token != address(0), "Platform: Invalid token address");

        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance >= amount, "Platform: Insufficient balance");

        IERC20(token).safeTransfer(owner(), amount);

        emit ERC20FeesWithdrawn(token, owner(), amount);
    }

    /*///////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
     * @notice Returns current platform parameters
     * @return Current platform parameters
     */
    function getPlatformParameters()
        external
        view
        override
        returns (PlatformParams memory)
    {
        return _platformParams;
    }

    /**
     * @inheritdoc IPlatform
     * @notice Returns list of all registered tokens
     * @return Array of registered token addresses
     */
    function getRegisteredTokens()
        external
        view
        override
        returns (address[] memory)
    {
        return _registeredTokens;
    }

    /**
     * @inheritdoc IPlatform
     * @notice Returns user information for a specific wallet
     * @param user Address of the user
     * @return User information including email hash and project IDs
     */
    function getUserInfo(
        address user
    ) external view override returns (UserInfo memory) {
        return _userInfo[user];
    }

    /**
     * @inheritdoc IPlatform
     * @notice Returns balance of specific token held by platform
     * @param token Address of the ERC20 token
     * @return Current balance of the token
     */
    function getTokenBalance(
        address token
    ) external view override returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @inheritdoc IPlatform
     * @notice Checks if an address is registered as a user
     * @param user Address to check
     * @return True if registered, false otherwise
     */
    function isUserRegistered(
        address user
    ) external view override returns (bool) {
        return _isUserRegistered(user);
    }

    /**
     * @inheritdoc IPlatform
     * @notice Returns the total number of projects created
     * @return Number of projects (project IDs start from 1)
     */
    function totalProjects() external view override returns (uint256) {
        return _nextProjectId - 1; // Subtract 1 because we started from 1
    }

    /**
     * @inheritdoc IPlatform
     * @notice Returns project address by ID
     * @param projectId ID of the project
     * @return Address of the project contract
     */
    function getProjectById(
        uint256 projectId
    ) external view override returns (address) {
        return proyectoPorId[projectId];
    }

    /**
     * @inheritdoc IPlatform
     * @notice Checks if a token is registered and allowed
     * @param token Address of the token to check
     * @return True if registered, false otherwise
     */
    function isTokenRegistered(
        address token
    ) external view override returns (bool) {
        return tokenStatus[token];
    }

    /*///////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Generates configuration for the next project
     * @param creator Address of the project creator
     * @return projectConfig Configuration for the new project
     */
    function _generateNextProjectConfig(
        address creator
    ) internal returns (ProjectConfig memory projectConfig) {
        uint256 projectId = _nextProjectId;
        _nextProjectId = projectId + 1;

        projectConfig = ProjectConfig({
            projectId: projectId,
            creator: creator,
            platform: address(this)
        });
    }

    /**
     * @dev Removes a token from the registered tokens array
     * @dev Optimized to start from the end for efficiency
     * @param token Address of the token to remove
     */
    function _removeTokenFromRegistry(address token) internal {
        uint256 length = _registeredTokens.length;

        // Optimización: empezar desde el final
        for (uint256 i = length; i > 0; ) {
            unchecked {
                --i;
            }
            if (_registeredTokens[i] == token) {
                _registeredTokens[i] = _registeredTokens[length - 1];
                _registeredTokens.pop();
                break;
            }
        }
    }

    /**
     * @dev Refunds excess ETH sent by the caller
     * @param requiredAmount Amount that was actually required
     */
    function _refundExcessEth(uint256 requiredAmount) internal {
        if (msg.value > requiredAmount) {
            uint256 excess = msg.value - requiredAmount;
            (bool success, ) = payable(msg.sender).call{value: excess}("");
            if (!success) revert Platform_RefundFailed();

            emit ExcessEthRefunded(msg.sender, excess);
        }
    }

    /**
     * @dev Validates platform parameters during initialization/update
     * @param params Platform parameters to validate
     */
    function _validatePlatformParams(
        PlatformParams memory params
    ) internal pure {
        if (params.tokenizationFee > MAX_FEE_BPS)
            revert Platform_InvalidParameter();
        if (params.withdrawalFee > MAX_FEE_BPS)
            revert Platform_InvalidParameter();
        if (params.minQuorum > MAX_FEE_BPS) revert Platform_InvalidParameter();
        if (params.minDelay == 0) revert Platform_InvalidParameter();

        // Validate natillera fee is reasonable (optional)
        if (params.natilleraFee > 100 ether) {
            // Max 100 ETH fee
            revert Platform_InvalidParameter();
        }
    }

    /**
     * @dev Checks if a wallet is registered as a user
     * @param user Address to check
     * @return True if registered, false otherwise
     */
    function _isUserRegistered(address user) internal view returns (bool) {
        return _userInfo[user].emailHash != bytes32(0);
    }

    /*///////////////////////////////////////////////////////////////
                                RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the contract to receive ETH
     * @dev Required for fee collection in native currency
     */
    receive() external payable {}
}
