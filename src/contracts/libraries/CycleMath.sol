// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title CycleMath
 * @author K-Labs
 * @notice Library for precise 30-day cycle calculations with overflow protection
 * @dev Handles cycle synchronization, duration calculations, and timestamp validations
 * @custom:precision Uses 30-day months (2,592,000 seconds) for consistent cycle calculations
 */
library CycleMath {
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Seconds in a standard 30-day month (2,592,000 seconds)
    uint256 internal constant SECONDS_PER_CYCLE = 30 days;

    /// @notice Maximum cycles to calculate in one synchronization (10 years)
    uint256 internal constant MAX_CYCLES_CALC = 120;

    /// @notice Precision factor for fractional calculations (1e18)
    uint256 internal constant PRECISION = 1e18;

    /// @notice Maximum safe timestamp (year 2106 to avoid overflow issues)
    uint256 internal constant MAX_TIMESTAMP = 2 ** 62 - 1;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Current timestamp is before the base timestamp
    error CurrentBeforeBase();

    /// @notice Timestamp exceeds maximum safe value
    error TimestampTooLarge();

    /// @notice Invalid timestamp range (end before start)
    error InvalidRange();

    /// @notice Multiplication overflow in cycle calculation
    error MultiplicationOverflow();

    /// @notice Addition overflow in timestamp calculation
    error AdditionOverflow();

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Cycle state tracking structure
     * @param currentCycle Current 30-day cycle number (0-indexed)
     * @param cycleDueDate Unix timestamp when current cycle contributions are due
     * @param baseTimestamp Unix timestamp for cycle 0 start
     */
    struct CycleState {
        uint256 currentCycle;
        uint256 cycleDueDate;
        uint256 baseTimestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            CYCLE SYNCHRONIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Synchronizes cycle state based on current timestamp
     * @dev Updates cycle number and due date if current time has passed cycle due date
     * @dev Limits cycle advancement to prevent unbounded gas consumption
     * @param state Cycle state storage reference to update
     * @param currentTime Current block timestamp to synchronize against
     */
    function syncCycle(CycleState storage state, uint256 currentTime) internal {
        // Early return if still within current cycle grace period
        if (currentTime <= state.cycleDueDate + SECONDS_PER_CYCLE) {
            return;
        }

        // Validate timestamp is after base and within safe range
        if (currentTime < state.baseTimestamp) revert CurrentBeforeBase();
        if (currentTime > MAX_TIMESTAMP) revert TimestampTooLarge();

        // Calculate elapsed time since base timestamp
        uint256 elapsed = currentTime - state.baseTimestamp;

        // Calculate new cycle number based on elapsed time
        uint256 newCycle = elapsed / SECONDS_PER_CYCLE;

        // Limit cycle advancement to prevent unbounded loops
        if (newCycle > state.currentCycle + MAX_CYCLES_CALC) {
            newCycle = state.currentCycle + MAX_CYCLES_CALC;
        }

        // Update state only if cycle has actually advanced
        if (newCycle > state.currentCycle) {
            state.currentCycle = newCycle;

            // Calculate new due date with overflow protection
            uint256 dueDate = state.baseTimestamp +
                (SECONDS_PER_CYCLE * newCycle);
            if (dueDate < state.baseTimestamp) revert AdditionOverflow();

            state.cycleDueDate = dueDate;
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CYCLE CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates number of complete cycles between two timestamps
     * @dev Returns floor(elapsed / SECONDS_PER_CYCLE)
     * @param fromTimestamp Start timestamp (inclusive)
     * @param toTimestamp End timestamp (exclusive)
     * @return cycles Number of complete 30-day cycles between timestamps
     */
    function calculateCyclesBetween(
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal pure returns (uint256 cycles) {
        if (toTimestamp < fromTimestamp) revert InvalidRange();
        if (toTimestamp > MAX_TIMESTAMP) revert TimestampTooLarge();

        uint256 elapsed = toTimestamp - fromTimestamp;
        cycles = elapsed / SECONDS_PER_CYCLE;
    }

    /**
     * @notice Calculates fractional cycles between timestamps with high precision
     * @dev Returns (elapsed * PRECISION) / SECONDS_PER_CYCLE for fractional calculations
     * @param fromTimestamp Start timestamp
     * @param toTimestamp End timestamp
     * @return cycles Fractional cycles with PRECISION (1e18) precision
     */
    function calculateCyclesBetweenPrecise(
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal pure returns (uint256 cycles) {
        if (toTimestamp < fromTimestamp) revert InvalidRange();
        if (toTimestamp > MAX_TIMESTAMP) revert TimestampTooLarge();

        uint256 elapsed = toTimestamp - fromTimestamp;
        cycles = (elapsed * PRECISION) / SECONDS_PER_CYCLE;
    }

    /**
     * @notice Adds specified number of cycles to a base timestamp
     * @dev Calculates: baseTimestamp + (cycles * SECONDS_PER_CYCLE)
     * @param timestamp Base timestamp to add cycles to
     * @param cycles Number of 30-day cycles to add
     * @return newTimestamp Resulting timestamp after adding cycles
     */
    function addCycles(
        uint256 timestamp,
        uint256 cycles
    ) internal pure returns (uint256 newTimestamp) {
        if (timestamp > MAX_TIMESTAMP) revert TimestampTooLarge();

        // Calculate seconds to add with overflow check
        uint256 secondsToAdd = cycles * SECONDS_PER_CYCLE;
        if (secondsToAdd / cycles != SECONDS_PER_CYCLE)
            revert MultiplicationOverflow();

        // Check addition overflow
        if (timestamp > type(uint256).max - secondsToAdd)
            revert AdditionOverflow();

        newTimestamp = timestamp + secondsToAdd;
    }

    /**
     * @notice Calculates due date for a specific cycle number
     * @dev Calculates: baseTimestamp + (cycleNumber * SECONDS_PER_CYCLE)
     * @param baseTimestamp Base timestamp for cycle 0
     * @param cycleNumber Cycle number to calculate due date for
     * @return dueDate Unix timestamp when the specified cycle is due
     */
    function calculateDueDate(
        uint256 baseTimestamp,
        uint256 cycleNumber
    ) internal pure returns (uint256 dueDate) {
        if (baseTimestamp > MAX_TIMESTAMP) revert TimestampTooLarge();

        dueDate = baseTimestamp + (cycleNumber * SECONDS_PER_CYCLE);
        if (dueDate < baseTimestamp) revert AdditionOverflow();
    }

    /*//////////////////////////////////////////////////////////////
                            VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates that a timestamp is within acceptable range
     * @dev Prevents timestamp values that could cause overflow in calculations
     * @param timestamp Unix timestamp to validate
     */
    function validateTimestamp(uint256 timestamp) internal pure {
        if (timestamp > MAX_TIMESTAMP) revert TimestampTooLarge();
    }

    /**
     * @notice Validates that cycles can be safely added to a timestamp
     * @dev Checks both multiplication and addition overflow scenarios
     * @param timestamp Base timestamp to validate
     * @param cycles Number of cycles to validate addition for
     */
    function validateCycleAddition(
        uint256 timestamp,
        uint256 cycles
    ) internal pure {
        if (timestamp > MAX_TIMESTAMP) revert TimestampTooLarge();

        uint256 secondsToAdd = cycles * SECONDS_PER_CYCLE;
        if (secondsToAdd / cycles != SECONDS_PER_CYCLE)
            revert MultiplicationOverflow();
        if (timestamp > type(uint256).max - secondsToAdd)
            revert AdditionOverflow();
    }
}
