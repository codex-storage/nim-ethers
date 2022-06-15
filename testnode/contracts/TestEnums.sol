// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TestEnums {
  enum SomeEnum { One, Two }

  function returnValue(SomeEnum value) external pure returns (SomeEnum) {
    return value;
  }
}
