// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IFeeManager
 * @notice Interface for managing module fees and treasury.
 */
interface IFeeManager {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error FeeTooHigh();
    error FeeNotConfigured();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeeUpdated(bytes32 indexed feeType, uint16 newBps);
    event TreasuryUpdated(address indexed newTreasury);

    /*//////////////////////////////////////////////////////////////
                                CORE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the FeeManager with a treasury address.
     * @param treasury_ Address that will receive collected fees
     */
    function initialize(address treasury_) external;

    /**
     * @notice Sets the fee for a specific module type.
     * @param feeType Identifier for the module (e.g., keccak256("NATILLERA_V2"))
     * @param bps Fee in basis points (1/100 of a percent)
     */
    function setFee(bytes32 feeType, uint16 bps) external;

    /**
     * @notice Updates the fee treasury address.
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external;

    /**
     * @notice Calculates fee and net amount for a given module and raw amount.
     * @param feeType Module identifier
     * @param amount Raw amount before fee deduction
     * @return feeAmount Amount to be sent to treasury
     * @return netAmount Amount to be sent to user
     */
    function calculateFee(
        bytes32 feeType,
        uint256 amount
    ) external view returns (uint256 feeAmount, uint256 netAmount);

    /**
     * @notice Returns the current fee treasury address.
     * @return Address of the fee treasury
     */
    function feeTreasury() external view returns (address);
}
