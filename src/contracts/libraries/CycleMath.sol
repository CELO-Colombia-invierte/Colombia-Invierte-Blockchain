// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title CycleMath
 * @dev Library for precise cycle calculations with overflow protection
 * @notice Handles 30-day cycle calculations with configurable precision
 * @author K-Labs
 */
library CycleMath {
    using SafeCast for uint256;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Seconds in a standard 30-day month
    uint256 internal constant SECONDS_PER_CYCLE = 30 days;

    /// @dev Maximum cycles to calculate in one operation (10 years)
    uint256 internal constant MAX_CYCLES_CALC = 120;

    /// @dev Precision factor for fractional calculations (1e18)
    uint256 internal constant PRECISION = 1e18;

    /// @dev Maximum safe timestamp (year 2106)
    uint256 internal constant MAX_TIMESTAMP = 2 ** 62 - 1;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Cycle state structure
     * @param currentCycle Current cycle number
     * @param cycleDueDate Due date of current cycle
     * @param baseTimestamp Base timestamp for cycle 0
     */
    struct CycleState {
        uint256 currentCycle;
        uint256 cycleDueDate;
        uint256 baseTimestamp;
    }

    /*//////////////////////////////////////////////////////////////
                                CYCLE CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Synchronizes cycle state based on current timestamp
     * @param state Cycle state to update
     * @param currentTime Current block timestamp
     */
    function syncCycle(CycleState storage state, uint256 currentTime) internal {
        if (currentTime <= state.cycleDueDate + SECONDS_PER_CYCLE) {
            return;
        }

        // Validate timestamp range
        require(
            currentTime >= state.baseTimestamp,
            "CycleMath: current before base"
        );
        require(currentTime <= MAX_TIMESTAMP, "CycleMath: timestamp too large");

        // Calculate elapsed time safely
        uint256 elapsed = currentTime - state.baseTimestamp;

        // Calculate new cycle
        uint256 newCycle = elapsed / SECONDS_PER_CYCLE;

        // Limit cycle advancement to prevent unbounded loops
        if (newCycle > state.currentCycle + MAX_CYCLES_CALC) {
            newCycle = state.currentCycle + MAX_CYCLES_CALC;
        }

        // Update state if cycle advanced
        if (newCycle > state.currentCycle) {
            state.currentCycle = newCycle;

            // Calculate new due date with overflow check
            uint256 dueDate = state.baseTimestamp +
                (SECONDS_PER_CYCLE * newCycle);
            require(dueDate >= state.baseTimestamp, "CycleMath: overflow");

            state.cycleDueDate = dueDate;
        }
    }

    /**
     * @dev Calculates cycles between two timestamps
     * @param fromTimestamp Start timestamp
     * @param toTimestamp End timestamp
     * @return cycles Number of complete cycles
     */
    function calculateCyclesBetween(
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal pure returns (uint256 cycles) {
        require(toTimestamp >= fromTimestamp, "CycleMath: invalid range");
        require(toTimestamp <= MAX_TIMESTAMP, "CycleMath: timestamp too large");

        uint256 elapsed = toTimestamp - fromTimestamp;
        cycles = elapsed / SECONDS_PER_CYCLE;
    }

    /**
     * @dev Calculates cycles between timestamps with fractional precision
     * @param fromTimestamp Start timestamp
     * @param toTimestamp End timestamp
     * @return cycles Number of cycles with PRECISION precision
     */
    function calculateCyclesBetweenPrecise(
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal pure returns (uint256 cycles) {
        require(toTimestamp >= fromTimestamp, "CycleMath: invalid range");
        require(toTimestamp <= MAX_TIMESTAMP, "CycleMath: timestamp too large");

        uint256 elapsed = toTimestamp - fromTimestamp;

        // Calculate with precision: elapsed * PRECISION / SECONDS_PER_CYCLE
        cycles = (elapsed * PRECISION) / SECONDS_PER_CYCLE;
    }

    /**
     * @dev Adds cycles to a timestamp
     * @param timestamp Base timestamp
     * @param cycles Number of cycles to add
     * @return newTimestamp Resulting timestamp
     */
    function addCycles(
        uint256 timestamp,
        uint256 cycles
    ) internal pure returns (uint256 newTimestamp) {
        require(timestamp <= MAX_TIMESTAMP, "CycleMath: timestamp too large");

        // Calculate seconds to add with overflow check
        uint256 secondsToAdd = cycles * SECONDS_PER_CYCLE;
        require(
            secondsToAdd / cycles == SECONDS_PER_CYCLE,
            "CycleMath: multiplication overflow"
        );

        // Check addition overflow
        require(
            timestamp <= type(uint256).max - secondsToAdd,
            "CycleMath: addition overflow"
        );

        newTimestamp = timestamp + secondsToAdd;
    }

    /**
     * @dev Calculates due date for a specific cycle
     * @param baseTimestamp Base timestamp for cycle 0
     * @param cycleNumber Cycle number
     * @return dueDate Due date for the cycle
     */
    function calculateDueDate(
        uint256 baseTimestamp,
        uint256 cycleNumber
    ) internal pure returns (uint256 dueDate) {
        require(
            baseTimestamp <= MAX_TIMESTAMP,
            "CycleMath: timestamp too large"
        );

        dueDate = baseTimestamp + (cycleNumber * SECONDS_PER_CYCLE);
        require(dueDate >= baseTimestamp, "CycleMath: overflow");
    }

    /*//////////////////////////////////////////////////////////////
                                VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Validates that a timestamp is within acceptable range
     * @param timestamp Timestamp to validate
     */
    function validateTimestamp(uint256 timestamp) internal pure {
        require(timestamp <= MAX_TIMESTAMP, "CycleMath: timestamp too large");
    }

    /**
     * @dev Validates that cycles can be safely added to timestamp
     * @param timestamp Base timestamp
     * @param cycles Number of cycles
     */
    function validateCycleAddition(
        uint256 timestamp,
        uint256 cycles
    ) internal pure {
        require(timestamp <= MAX_TIMESTAMP, "CycleMath: timestamp too large");

        uint256 secondsToAdd = cycles * SECONDS_PER_CYCLE;
        require(
            secondsToAdd / cycles == SECONDS_PER_CYCLE,
            "CycleMath: multiplication overflow"
        );
        require(
            timestamp <= type(uint256).max - secondsToAdd,
            "CycleMath: addition overflow"
        );
    }
}
