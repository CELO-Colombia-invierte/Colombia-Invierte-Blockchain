// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {Tracking} from "contracts/Tracking.sol";
import {INatillera} from "interfaces/INatillera.sol";
import {IPlatform} from "interfaces/IPlatform.sol";
import {ITokenizacion} from "interfaces/ITokenizacion.sol";

/**
 * @title Platform
 * @author K-Labs
 * @notice Factory and management contract for Natillera and Tokenization projects
 * @dev Implements factory pattern with upgradeable implementations and fee management
 * @custom:features Project deployment, user management, token registry, fee collection
 */
contract Platform is
    Initializable,
    Tracking,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IPlatform
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum fee percentage (100% in basis points)
    uint256 private constant MAX_FEE_BPS = 10_000;

    /// @notice Maximum number of tokens that can be registered
    uint256 private constant MAX_REGISTERED_TOKENS = 100;

    /// @notice Maximum future start time for natilleras (1 year)
    uint256 private constant MAX_FUTURE_START = 365 days;

    /// @notice Maximum flat fee for natillera deployment (100 ETH)
    uint256 private constant MAX_NATILLERA_FEE = 100 ether;

    /// @notice Parameter identifiers for updateParameter function
    bytes32 private constant PARAM_FEE_NATILLERA = "FEE_DE_NATILLERA";
    bytes32 private constant PARAM_FEE_TOKENIZACION = "FEE_DE_TOKENIZACION";
    bytes32 private constant PARAM_FEE_WITHDRAWAL = "FEE_DE_WITHDRAWAL";
    bytes32 private constant PARAM_DELAY_MINIMO = "DELAY_MINIMO";
    bytes32 private constant PARAM_QUORUM_MINIMO = "QUORUM_MINIMO";

    /*//////////////////////////////////////////////////////////////
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

    /// @notice Token registration status
    mapping(address => bool) public override isTokenRegistered;

    /// @notice Project addresses by ID
    mapping(uint256 => address) public override getProjectById;

    /// @notice Internal mapping of user information
    mapping(address => UserInfo) private _userInfo;

    /// @notice Counter for generating unique project IDs
    uint256 private _nextProjectId;

    /// @notice Platform configuration parameters
    PlatformParams private _platformParams;

    /// @notice List of registered ERC20 tokens
    address[] private _registeredTokens;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Verifies governance configuration meets minimum requirements
     * @param config Governance configuration to validate
     */
    modifier validateGovernanceConfig(GovernanceConfig calldata config) {
        if (config.governanceDelay < _platformParams.minDelay)
            revert InvalidParameter();
        if (config.minQuorum < _platformParams.minQuorum)
            revert InvalidParameter();
        _;
    }

    /**
     * @dev Restricts access to specific project only
     * @param projectId ID of the project
     */
    modifier onlyProject(uint256 projectId) {
        if (msg.sender != getProjectById[projectId]) revert InvalidCaller();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
     * @dev Validates implementation addresses and platform parameters
     * @dev The Tracking contract is initialized with this contract as platform
     */
    function initialize(
        address _natilleraImplementation,
        address _tokenizacionImplementation,
        PlatformParams calldata platformParams
    ) external override initializer {
        // Validate addresses
        if (
            _natilleraImplementation == address(0) ||
            _tokenizacionImplementation == address(0)
        ) revert InvalidParameter();

        // Validate platform parameters
        _validatePlatformParams(platformParams);

        // Initialize parent contracts
        __Tracking_init(address(this), 0, msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();

        // Set implementations and parameters
        natilleraImplementation = _natilleraImplementation;
        tokenizacionImplementation = _tokenizacionImplementation;
        _platformParams = platformParams;

        // Initialize versions
        natilleraVersion = 1;
        tokenizacionVersion = 1;

        // Start project IDs from 1 (0 is invalid/reserved)
        _nextProjectId = 1;

        emit PlatformInitialized(
            _natilleraImplementation,
            _tokenizacionImplementation,
            platformParams
        );
    }

    /*//////////////////////////////////////////////////////////////
                            PROJECT DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
     * @dev Automatically generates project config and clones implementation
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
        if (msg.value < requiredFee) revert InsufficientFee();

        // Validate start timestamp
        if (
            startTimestamp < block.timestamp ||
            startTimestamp > block.timestamp + MAX_FUTURE_START
        ) revert InvalidParameter();

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
        getProjectById[projectConfig.projectId] = natilleraClone;

        emit NatilleraDeployed(
            natilleraClone,
            projectConfig.projectId,
            msg.sender
        );
    }

    /**
     * @inheritdoc IPlatform
     * @dev Calculates fee based on total token value (price * quantity)
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
        ) revert InvalidParameter();

        // Calculate total value and fee
        uint256 totalValue = tokenizationParams.totalTokens *
            tokenizationParams.pricePerToken;
        uint256 feeAmount = (totalValue * _platformParams.tokenizationFee) /
            MAX_FEE_BPS;

        // Validate fee is not excessive (max 50% of total value)
        if (feeAmount > totalValue / 2) {
            revert InvalidParameter();
        }

        // Process fee payment
        if (tokenizationParams.paymentToken == address(0)) {
            // Native currency payment
            if (msg.value < feeAmount) revert InsufficientFee();
            _refundExcessEth(feeAmount);
        } else {
            // ERC20 payment
            if (!isTokenRegistered[tokenizationParams.paymentToken])
                revert TokenNotRegistered();

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
        getProjectById[projectConfig.projectId] = tokenizationClone;

        emit TokenizacionDeployed(
            tokenizationClone,
            projectConfig.projectId,
            msg.sender
        );
    }

    /*//////////////////////////////////////////////////////////////
                            USER MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
     */
    function registerUser(bytes32 emailHash) external override whenNotPaused {
        if (_isUserRegistered(msg.sender)) revert UserAlreadyRegistered();

        _userInfo[msg.sender] = UserInfo({
            emailHash: emailHash,
            projectIds: new uint256[](0)
        });

        emit UserRegistered(msg.sender, emailHash);
    }

    /**
     * @inheritdoc IPlatform
     */
    function addUserToProject(
        uint256 projectId,
        address user
    ) external override onlyProject(projectId) {
        if (!_isUserRegistered(user)) revert UserNotRegistered();

        _userInfo[user].projectIds.push(projectId);

        emit UserAddedToProject(projectId, user, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            FEE MANAGEMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
     */
    function withdrawNativeFees() external override onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert BalanceZero();

        (bool success, ) = payable(owner()).call{value: balance}("");
        if (!success) revert TransferFailed();

        emit NativeFeesWithdrawn(owner(), balance);
    }

    /**
     * @inheritdoc IPlatform
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
     */
    function withdrawERC20FeesByToken(
        address token
    ) external override onlyOwner nonReentrant {
        if (!isTokenRegistered[token]) revert TokenNotRegistered();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert BalanceZero();

        IERC20(token).safeTransfer(owner(), balance);

        emit ERC20FeesWithdrawn(token, owner(), balance);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMINISTRATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
     */
    function registerToken(address token) external override onlyOwner {
        if (token == address(0) || token == address(this))
            revert InvalidToken();
        if (isTokenRegistered[token]) revert TokenAlreadyRegistered();
        if (_registeredTokens.length >= MAX_REGISTERED_TOKENS)
            revert MaxTokensReached();

        // Validate it's a proper ERC20
        try IERC20(token).totalSupply() returns (uint256 totalSupply) {
            if (totalSupply == 0) revert InvalidToken();
        } catch {
            revert InvalidToken();
        }

        // Additional ERC20 validation
        try IERC20(token).balanceOf(address(this)) returns (uint256) {
            // Token supports balanceOf - good
        } catch {
            revert InvalidToken();
        }

        isTokenRegistered[token] = true;
        _registeredTokens.push(token);

        emit TokenStatusUpdated(token, true);
    }

    /**
     * @inheritdoc IPlatform
     */
    function deregisterToken(address token) external override onlyOwner {
        if (!isTokenRegistered[token]) revert TokenNotRegistered();

        isTokenRegistered[token] = false;
        _removeTokenFromRegistry(token);

        emit TokenStatusUpdated(token, false);
    }

    /**
     * @inheritdoc IPlatform
     */
    function updateParameter(
        bytes32 parameter,
        uint256 value
    ) external override onlyOwner {
        if (parameter == PARAM_FEE_NATILLERA) {
            // Flat fee in native token
            if (value > MAX_NATILLERA_FEE) revert InvalidParameter();
            _platformParams.natilleraFee = value;
        } else if (parameter == PARAM_FEE_TOKENIZACION) {
            // Percentage fee (basis points)
            if (value > MAX_FEE_BPS) revert InvalidParameter();
            _platformParams.tokenizationFee = value;
        } else if (parameter == PARAM_FEE_WITHDRAWAL) {
            if (value > MAX_FEE_BPS) revert InvalidParameter();
            _platformParams.withdrawalFee = value;
        } else if (parameter == PARAM_DELAY_MINIMO) {
            if (value == 0) revert InvalidParameter();
            _platformParams.minDelay = value;
        } else if (parameter == PARAM_QUORUM_MINIMO) {
            if (value > MAX_FEE_BPS) revert InvalidParameter();
            _platformParams.minQuorum = value;
        } else {
            revert InvalidParameter();
        }

        emit ParameterUpdated(parameter, value);
    }

    /**
     * @inheritdoc IPlatform
     */
    function updateImplementation(
        address implementation,
        bytes32 implementationType
    ) external override onlyOwner {
        if (implementation == address(0)) revert InvalidParameter();

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
            revert InvalidParameter();
        }
    }

    /**
     * @inheritdoc IPlatform
     */
    function pause() external override onlyOwner {
        _pause();
    }

    /**
     * @inheritdoc IPlatform
     */
    function unpause() external override onlyOwner {
        _unpause();
    }

    /**
     * @inheritdoc IPlatform
     */
    function rescueToken(
        address token,
        uint256 amount
    ) external override onlyOwner nonReentrant {
        if (token == address(0)) revert InvalidToken();
        if (isTokenRegistered[token]) revert CannotRescueRegisteredToken();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();

        IERC20(token).safeTransfer(owner(), amount);

        emit TokensRescued(token, owner(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPlatform
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
     */
    function getUserInfo(
        address user
    ) external view override returns (UserInfo memory) {
        return _userInfo[user];
    }

    /**
     * @inheritdoc IPlatform
     */
    function getTokenBalance(
        address token
    ) external view override returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @inheritdoc IPlatform
     */
    function isUserRegistered(
        address user
    ) external view override returns (bool) {
        return _isUserRegistered(user);
    }

    /**
     * @inheritdoc IPlatform
     */
    function totalProjects() external view override returns (uint256) {
        return _nextProjectId - 1;
    }

    /*//////////////////////////////////////////////////////////////
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
     * @param token Address of the token to remove
     */
    function _removeTokenFromRegistry(address token) internal {
        uint256 length = _registeredTokens.length;

        for (uint256 i = 0; i < length; ) {
            if (_registeredTokens[i] == token) {
                _registeredTokens[i] = _registeredTokens[length - 1];
                _registeredTokens.pop();
                break;
            }
            unchecked {
                ++i;
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
            if (!success) revert RefundFailed();

            emit ExcessEthRefunded(msg.sender, excess);
        }
    }

    /**
     * @dev Validates platform parameters during initialization/update
     * @param params Platform parameters to validate
     */
    function _validatePlatformParams(
        PlatformParams calldata params
    ) internal pure {
        if (params.tokenizationFee > MAX_FEE_BPS) revert InvalidParameter();
        if (params.withdrawalFee > MAX_FEE_BPS) revert InvalidParameter();
        if (params.minQuorum > MAX_FEE_BPS) revert InvalidParameter();
        if (params.minDelay == 0) revert InvalidParameter();

        // Validate natillera fee is reasonable
        if (params.natilleraFee > MAX_NATILLERA_FEE) {
            revert InvalidParameter();
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

    /*//////////////////////////////////////////////////////////////
                                RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows contract to receive ETH
     * @dev Required for fee collection in native currency
     */
    receive() external payable {}
}
