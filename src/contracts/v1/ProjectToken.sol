// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

/**
 * @title ProjectToken
 * @notice Simple ERC20 token for tokenization projects
 * @dev MVP V1: Basic mintable token controlled by Tokenizacion contract
 * @dev Minting can be permanently disabled by the issuer
 */
contract ProjectToken is ERC20 {
  /*///////////////////////////////////////////////////////////////
                              STATE VARIABLES
  //////////////////////////////////////////////////////////////*/

  /// @notice Token issuer address (Tokenizacion contract)
  address public immutable ISSUER;

  /// @notice Whether minting is permanently finished
  bool public mintingFinished;

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Error emitted when non-issuer tries to mint tokens
  error OnlyIssuer();
  /// @notice Error emitted when trying to mint after minting is finished
  error MintingFinished();

  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Event emitted when minting is permanently finished
   * @dev Emitted from `finishMinting()` function
   */
  event MintingFinalized();

  /*///////////////////////////////////////////////////////////////
                              CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploy a new project token with custom name and symbol
   * @param name_ Token name (e.g., "Project Token")
   * @param symbol_ Token symbol (e.g., "PRJ")
   * @param issuer_ Token issuer address (Tokenizacion contract)
   * @dev Sets the immutable issuer address that controls minting
   * @dev Inherits standard ERC20 functionality from OpenZeppelin
   */
  constructor(string memory name_, string memory symbol_, address issuer_) ERC20(name_, symbol_) {
    ISSUER = issuer_;
  }

  /*///////////////////////////////////////////////////////////////
                          MINTING FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Mint new tokens to a specified address
   * @param to Recipient address to receive minted tokens
   * @param amount Amount of tokens to mint (in token decimals)
   * @dev Can only be called by the issuer (Tokenizacion contract)
   * @dev Cannot mint after minting is permanently finished
   * @dev Uses internal `_mint()` function from ERC20
   */
  function mint(address to, uint256 amount) external {
    // Access control: only issuer can mint
    if (msg.sender != ISSUER) revert OnlyIssuer();

    // State validation: cannot mint after finishing
    if (mintingFinished) revert MintingFinished();

    // Mint tokens to recipient
    _mint(to, amount);
  }

  /**
   * @notice Permanently finish minting capability
   * @dev Can only be called by the issuer (Tokenizacion contract)
   * @dev Irreversible action - once finished, no more tokens can be minted
   * @dev Emits MintingFinalized event
   */
  function finishMinting() external {
    // Access control: only issuer can finish minting
    if (msg.sender != ISSUER) revert OnlyIssuer();

    // Permanently disable minting
    mintingFinished = true;
    emit MintingFinalized();
  }
}
