// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TestGasEstimation {

  uint lastCheckedTime;

  // this function returns a different value depending on whether
  // it is called on the latest block, or on the pending block
  function getTime() public view returns (uint) {
    return block.timestamp;
  }

  // this function is designed to require a different amount of
  // gas, depending on whether the parameter matches the block
  // timestamp
  function checkTimeEquals(uint expected) public {
    if (expected == block.timestamp) {
      lastCheckedTime = block.timestamp;
    }
  }
}
