// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
  constructor() ERC20("TestToken", "TST") {}

  function decimals() public view virtual override returns (uint8) {
    return 12;
  }

  function mint(address holder, uint amount) public {
    _mint(holder, amount);
  }

  function burn(address holder, uint amount) public {
    _burn(holder, amount);
  }

  function myBalance() public view returns (uint256)  {
    return balanceOf(msg.sender);
  }
}
