// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TestReturns {
  struct StaticStruct {
    uint256 a;
    uint256 b;
  }
  struct DynamicStruct {
    string a;
    uint256 b;
  }

  function getStatic() external pure returns (StaticStruct memory) {
    return StaticStruct(1, 2);
  }

  function getDynamic() external pure returns (DynamicStruct memory) {
    return DynamicStruct("1", 2);
  }

  function getStatics()
    external
    pure
    returns (StaticStruct memory, StaticStruct memory)
  {
    return (StaticStruct(1, 2), StaticStruct(3, 4));
  }

  function getDynamics()
    external
    pure
    returns (DynamicStruct memory, DynamicStruct memory)
  {
    return (DynamicStruct("1", 2), DynamicStruct("3", 4));
  }

  function getDynamicAndStatic()
    external
    pure
    returns (DynamicStruct memory, StaticStruct memory)
  {
    return (DynamicStruct("1", 2), StaticStruct(3, 4));
  }
}
