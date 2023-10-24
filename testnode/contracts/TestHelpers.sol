// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TestHelpers {

  function doRevert(string calldata reason) public pure {
    // Revert every tx with given reason
    require(false, reason);
  }
}
