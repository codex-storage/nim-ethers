// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TestHelpers {

  function revertsWith(string calldata revertReason) public pure {
    require(false, revertReason);
  }
}
