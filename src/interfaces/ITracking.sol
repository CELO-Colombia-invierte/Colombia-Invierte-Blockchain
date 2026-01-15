pragma solidity 0.8.30;

/**
 * @title Tracking Contract
 * @author K-Labs
 * @notice This is a contract for the tracking projects (Natilleras and Tokenizaciones) of the platform
 */
interface ITracking {
  /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/
  /**
   * @notice Returns the platform address
   * @return _platform The platform address
   */
  function PLATFORM() external view returns (address _platform);

  /**
   * @notice Returns the uuid of the project
   * @return _uuid The uuid of the project
   */
  function uuid() external view returns (uint256 _uuid);
}
