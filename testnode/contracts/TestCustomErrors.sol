// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract TestCustomErrors {

  error SimpleError();
  error ErrorWithArguments(uint256 one, bool two);
  error ErrorWithStaticStruct(StaticStruct one, StaticStruct two);
  error ErrorWithDynamicStruct(DynamicStruct one, DynamicStruct two);
  error ErrorWithDynamicAndStaticStruct(DynamicStruct one, StaticStruct two);

  struct StaticStruct {
    uint256 a;
    uint256 b;
  }

  struct DynamicStruct {
    string a;
    uint256 b;
  }

  function revertsSimpleError() public pure {
    revert SimpleError();
  }

  function revertsErrorWithArguments() public pure {
    revert ErrorWithArguments(1, true);
  }

  function revertsErrorWithStaticStruct() public pure {
    revert ErrorWithStaticStruct(StaticStruct(1, 2), StaticStruct(3, 4));
  }

  function revertsErrorWithDynamicStruct() public pure {
    revert ErrorWithDynamicStruct(DynamicStruct("1", 2), DynamicStruct("3", 4));
  }

  function revertsErrorWithDynamicAndStaticStruct() public pure {
    revert ErrorWithDynamicAndStaticStruct(
      DynamicStruct("1", 2),
      StaticStruct(3, 4)
    );
  }
}
